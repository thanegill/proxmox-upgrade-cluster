#!/usr/bin/env bash

shopt -s extglob

set -o errexit -o pipefail

program_name="$(basename "$0")"
ssh_user="${PVE_UPGRADE_SSH_USER:-root}"
use_cluster_node=false
force_upgrade=false
force_reboot=false
pkgs_reinstall=("proxmox-truenas")

declare cluster_node
declare -na cluster_nodes
declare -na upgrade_nodes
declare -a ssh_options

declare -i verbose=0
testing=false
log_output="/dev/stderr"
log_prefix="[%F %T]"

log_pipe_level() {
  # pipe to $log_output with prefix and optional timestamp
  local -i level=$1
  local prefix=${2:-""}
  local prefix="$log_prefix$prefix"

  if [[ $verbose -lt $level ]]; then return 0; fi

  if [[ "$prefix" = "" ]]; then
    cat - > $log_output
  else
    cat - | ts "$prefix" > $log_output
  fi
}

log_level() {
  local -i level=$1
  shift
  echo -e "$@" | log_pipe_level "$level"
}

log() {
  log_level 0 "$*"
}

log_color() {
  local -i color=$1
  shift
  log_level 0 "\033[0;${color}m${*}\033[0m"
}

log_alert() {
  # Log in red
  log_color 31 "$@"
}

log_error() {
  log_alert "$@"
}

log_status() {
  # Log in red
  log_color 35 "$@"
}

log_success() {
  # Log in green
  log_color 32 "$@"
}

log_warning() {
  # Log in orange
  log_color 33 "$@"
}

log_verbose() {
  log_level 1 "$@"
}

log_debug() {
  log_level 2 "$@"
}

log_progress_start_end() {
  # Just a newline
  # Only log progress when no verbosity
  if [[ $verbose -eq 0 ]]; then
    log
  fi
}

log_progress() {
  # Only log progress when no verbosity
  if [[ $verbose -eq 0 ]]; then
    echo -n '.' | log_pipe_level 0
  fi
}

local_ssh() {
  # shellcheck disable=2068
  command ssh $@
}

node_ssh() {
  local host=$1; shift
  local cmd=$1; shift
  log_debug "[$host] Running command '$cmd'"

  # shellcheck disable=SC2048,2086 # Need to expand ssh_options with all whitespace.
  local_ssh "$host" ${ssh_options[*]} $* "$cmd"
}

node_ssh_no_op() {
  local node=$1; shift
  local cmd=$1; shift
  if [[ "$testing" = true ]]; then
    log_warning "[$node][NO-OP] Not running '$cmd'"
    return 0
  fi
  # shellcheck disable=SC2048,2086 # Need to expand ssh_options with all whitespace.
  node_ssh "$node" "$cmd" "$@"
}

node_pvesh() {
  local node=$1
  local path=$2
  local args=$3
  json="$(node_ssh "$node" "pvesh get $path $args --output-form=json")"
  log_level 3 "[$node] JSON output:"
  echo "$json" | jq | log_pipe_level 3 "[$node]"
  echo "$json"
}

is_node_up() {
  local node=$1
  node_ssh "$node" whoami "-oConnectTimeout=5" | log_pipe_level 3 "[$node]"
}

all_nodes_up() {
  local -n nodes=$1
  for node in "${nodes[@]}"; do
    if is_node_up "$node"; then
      log_verbose "[$node] Is up."
    else
      log_alert "[$node] Is down."
      return 1
    fi
  done
}

get_cluster_nodes() {
  # Get list of all custer nodes from a node
  local node=$1
  local -a nodes
  node_pvesh "$node" "cluster/status" | jq -rc '[.[] | select(.type == "node") | .ip] | join(" ")'
}

node_has_updates() {
  local node=$1
  updates="$(node_ssh "$node" 'apt-get -qq -s upgrade')"
  echo "$updates" | log_pipe_level 2 "[$node]    "
  if [[ "$updates" == "" ]]; then
    return 1
  else
    log_debug "$updates"
    return 0
  fi
}

is_node_proxmox() {
  local node=$1
  node_ssh "$node" 'hash pvesh' >/dev/null
}

check_if_nodes_are_proxmox() {
  local -n nodes=$1
  for node in "${nodes[@]}"; do
    is_node_proxmox "$node"
  done
}

get_nodes_upgradeable() {
  local -n nodes=$1
  local -a nodes_with_updates
  for node in "${nodes[@]}"; do
    if node_has_updates "$node"; then
      log_success "[$node] Updates available."
      nodes_with_updates+=("$node")
    else
      log_success "[$node] No updates available."
      log_verbose "[$node] Removed from upgrade sequence."
    fi
  done
  echo "${nodes_with_updates[@]}"
}

node_apt_update() {
  local node=$1
  node_ssh "$node" 'apt-get update' | log_pipe_level 1 "[$node]    "
}

apt_update_nodes() {
  local -n nodes=$1
  for node in "${nodes[@]}"; do
    node_apt_update "$node"
  done
}

node_get_running_lxc() {
  local node=$1
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_pvesh "$node" 'nodes/$(hostname)/lxc' | jq -rc '[.[] | select(.status != "stopped")]'
}

node_get_running_qemu() {
  local node=$1
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_pvesh "$node" 'nodes/$(hostname)/qemu' | jq -rc '[.[] | select(.status != "stopped")]'
}

node_get_running_count() {
  local node=$1
  lxc_count="$(node_get_running_lxc "$node" | jq -rc '.|length')"
  log_verbose "[$node] Running LXC count: $lxc_count"

  qemu_count="$(node_get_running_qemu "$node" | jq -rc '.|length')"
  log_verbose "[$node] Running QEMU count: $qemu_count"
  echo "$((lxc_count + qemu_count))"
}

node_get_offline_count() {
  local node=$1
  node_pvesh "$node" 'cluster/ha/status/manager_status' | jq -rc '[.manager_status.node_status[] | select(. != "online")] | length'
}

node_get_mode() {
  local node=$1
  hostname=$(node_ssh "$node" hostname)
  node_pvesh "$node" 'cluster/ha/status/manager_status' | jq -rc ".manager_status.node_status.$hostname"
}

node_wait_until_mode() {
  local node=$1
  local target_mode=$2

  log_status "[$node] Waiting until node enters $target_mode mode..."
  log_progress_start_end
  mode=$(node_get_mode "$node")
  until [[ "$mode" == "$target_mode" ]]; do
    log_verbose "[$node] Current mode: '$mode' target mode: '$target_mode'"
    log_progress
    sleep 1s
    mode=$(node_get_mode "$node")
  done
  log_progress_start_end
  log_success "[$node] Has reached target mode: '$target_mode'"
}

node_wait_until_no_running_vms() {
  local node=$1
  log_status "[$node] Waiting until all QEMU and LXC are migrated..."
  count="$(node_get_running_count "$node")"
  until [[ $count -eq 0 ]]; do
    log "[$node] Number of qemu+lxc running: $count"
    sleep 5s
    count="$(node_get_running_count "$node")"
  done
  log_success "[$node] Has reached zero running qemu+lxc"
}

node_get_running_tasks() {
  local node=$1
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_pvesh "$node" 'nodes/$(hostname)/tasks' '--source=active'
}

node_is_running_task() {
  local node=$1
  task_count=$(node_get_running_tasks "$node" | jq -rc '.|length')
  if [[ "$task_count" != "0" ]]; then
    return 1 # false
  fi
}

any_nodes_running_tasks() {
  local -n nodes=$1
  for node in "${nodes[@]}"; do
    if node_is_running_task "$node"; then
        return 1
    fi
  done
}

node_wait_all_tasks_completed() {
  local node=$1

  log_status "[cluster] Waiting until all tasks have completed..."
  task_count=$(node_get_running_tasks "$node" | jq -rc '.|length')
  until [[ "$task_count" == "0" ]]; do
    log "[cluster] Number of running tasks $task_count"
    sleep 5s
    task_count=$(node_get_running_tasks "$node" | jq -rc '.|length')
  done
  log_success "[cluster] Has reached zero running tasks"
}

node_pre_maintenance_check() {
  local node=$1

  log_status "[cluster] Checking that no nodes are currently offline..."
  count="$(node_get_offline_count "$node")"
  until [[ "$count" == "0" ]]; do
    log "[cluster] At least one node is currently offline. Waiting..."
    sleep 1s
    count="$(node_get_offline_count "$node")"
  done
  log_success "[$node] No nodes in maintenance mode."
}

node_enter_maintenance() {
  local node=$1

  log "[$node] Enabling maintenance mode"
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_ssh_no_op "$node" 'ha-manager crm-command node-maintenance enable $(hostname)' | log_pipe_level 1 "[$node]    "

  # Don't wait for maintenance when no-op
  if [[ "$testing" == true ]]; then return 0; fi

  node_wait_until_mode "$node" "maintenance"
}

node_exit_maintenance() {
  local node=$1

  log "[$node] Disabling maintenance mode"
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_ssh_no_op "$node" 'ha-manager crm-command node-maintenance disable $(hostname)' | log_pipe_level 1 "[$node]    "

  # Don't wait for maintenance when no-op
  if [[ "$testing" == true ]]; then return 0; fi

  node_wait_until_mode "$node" "online"
}

node_pre_upgrade() {
  local node=$1
  node_pre_maintenance_check "$node"
  node_enter_maintenance "$node"
  node_wait_all_tasks_completed "$node"

  # Don't wait for no running vms when no-op
  if [[ "$testing" == true ]]; then return 0; fi

  node_wait_until_no_running_vms "$node"
}

node_upgrade() {
  local node=$1
  node_ssh_no_op "$node" 'apt-get dist-upgrade -y' | log_pipe_level 0 "[$node]    "
}

node_needs_reboot() {
  local node=$1

  expected_kernal="$(node_ssh "$node" 'grep vmlinuz /boot/grub/grub.cfg' | head -1 | awk '{ print $2 }' | sed -e 's%/boot/vmlinuz-%%;s%/ROOT/pve-1@%%')"
  booted_kernal=$(node_ssh "$node" 'uname -r')

  test "$expected_kernal" != "$booted_kernal"
}

node_reboot() {
  local node=$1

  if [[ "$force_reboot" == true ]]; then
    log_warning "[$node] Forcing Reboot"
  elif node_needs_reboot "$node"; then
    log_warning "[$node] Needs to be rebooted"
  else
    log_success "[$node] Doesn't need to be rebooted"
    return 0
  fi

  if [[ $testing == true ]]; then
    log_warning "[$node][NO-OP] Not rebooting"
    return 0
  fi

  log_alert "[$node] Rebooting in 5 seconds! Press CTRL-C to cancel..."
  sleep 5s
  log "[$node] Rebooting, logging shutdown dmesg:"
  node_ssh_no_op "$node" 'reboot' >/dev/null
  node_ssh_no_op "$node" 'dmesg -W' | log_pipe_level 0 "[$node]    " && true

  log_status "[$node] Waiting to come back up..."
  log_progress_start_end
  until is_node_up "$node"; do
    log_progress
  done
  log_progress_start_end

  log_success "[$node] Rebooted successfully"
}

node_post_upgrade() {
  local node=$1
  log_success "[$node] Force reinstalling '${pkgs_reinstall[*]}'..."
  node_ssh_no_op "$node" "apt-get reinstall ${pkgs_reinstall[*]}" | log_pipe_level 0 "[$node]    "
  log_success "[$node] Removing old packages..."
  node_ssh_no_op "$node" "apt-get autoremove -y && apt-get autoremove -y" | log_pipe_level 0 "[$node]    "
  node_exit_maintenance "$node"
}

usage() {
cat << EOF
NAME
    $program_name -

SYNOPSIS
    $program_name [--help|-h]

OPTIONS

    --cluster-node|-c
        A node in a cluster to pull all nodes from.

    --node|-n
        Node(s) to upgrade. Can be passed muliple times.

    --ssh-user|-u
        SSH user to authenticate with. Defaults to "$ssh_user".

    --ssh-opt|-o
        Options to pass to ssh. Can be passed muliple times.

    --testing
        Flag to enable a testing mode where no actions are taken.

    --pkg-reinstall
        Package(s) on the hosts to reinstall with 'apt-get reinstall' post
        upgrade. Can be passed muliple times.

    --force-upgrade
        Flag to force all nodes to upgrade, and not only those with avaible upgrades.

    --force-reboot
        Flag to forace all nodes to be rebooted durring upgrade, and not only
        those that aren't booted with the same kernal as the currenlty installed
        one.

    --verbose, -v
        Log actions and details to stdout. When multiple -v options are given,
        enable verbose logging for de-bugging purposes.

    --help, -h
        Show this message

EXAMPLE
    $program_name -c pve1
EOF
}

# Exit here if sourceing for tests
if [[ -n $ONLY_SOURCE_FUNCTIONS ]]; then return 0; fi

if [[ $# -eq 0 ]]; then
  log_error "No args passed"
  usage
  exit 1
fi;

while true; do
  case "$1" in
    --cluster-node|-c)
      shift
      use_cluster_node=true
      cluster_node="$1"
      ;;
    --node|-n)
      shift
      cluster_nodes+=("$1")
      ;;
    --ssh-user|-u)
      shift
      ssh_user="$1"
      ;;
    --ssh-opt|-o)
      shift
      ssh_options+=("$1")
      ;;
    --testing)
      testing=true
      ;;
    --pkg-reinstall)
      shift
      pkgs_reinstall+=("$1")
      ;;
    --force-upgrade)
      force_upgrade=true
      ;;
    --force-reboot)
      force_reboot=true
      ;;
    --verbose)
      verbose=$((verbose + 1))
      ;;
    -+(v))
      verbose=$((verbose + ${#1} - 1))
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      log_error "$program_name ERROR: unknown option '$1'"
      log_error "Use $program_name --help for help with command-line options."
      exit 1
      ;;
    *)
      break
      ;;
  esac
  shift
done

test $verbose -ge 5 && set -x
test $verbose -ge 4 && ssh_options+=("-v")

ssh_options+=("-l $ssh_user")

if [[ "$use_cluster_node" = true && ${#cluster_nodes[@]} -ne 0 ]]; then
  log_error "ERROR: Only one of --cluster-node, or --nodes can be used."
  log_error "See --help for usage."
  exit 1
fi

if [[ "$use_cluster_node" == false && ${#cluster_nodes[@]} -eq 0 ]]; then
  log_error "ERROR: One of --cluster-node, or --nodes must be used."
  log_error "See --help for usage."
  exit 1
fi

if [[ "$testing" == true ]]; then
  log_warning "Running in testing mode."
fi

if [[ "$use_cluster_node" = true ]]; then
  log_status "Getting all cluster nodes from node '$cluster_node'..."
  if ! is_node_up "$cluster_node"; then
    log_error "$cluster_node node is currently down."
    exit 1
  fi
  if ! is_node_proxmox "$cluster_node"; then
    exit 1
  fi
  # shellcheck disable=2207
  cluster_nodes=($(get_cluster_nodes "$cluster_node"))
fi
log_success "Using '${cluster_nodes[*]}' as all nodes to check."

log_status "Checking if any nodes are not proxmox..."
if ! check_if_nodes_are_proxmox cluster_nodes; then
  log_error "At least one node doesn't seem to be proxmox."
  exit 1
else
  log_success "All nodes are proxmox."
fi

log_status "Checking if any nodes are currently down..."
if ! all_nodes_up cluster_nodes; then
  log_error "At least one node is currently down."
  exit 1
else
  log_success "All nodes are up."
fi

log_status "Checking if any nodes are currently not online..."
if [[ $(node_get_offline_count "${cluster_nodes[0]}") -ne 0 ]]; then
  log_error "At least one node is currently not online."
  exit 1
else
  log_success "All nodes are online."
fi

log_status "Checking if any nodes currently have tasks running..."
if any_nodes_running_tasks cluster_nodes; then
  log_error "At least one node is currently running tasks."
  exit 1
else
  log_success "No tasks are running."
fi

apt_update_nodes cluster_nodes
if [[ "$force_upgrade" == true ]]; then
  upgrade_nodes=("${cluster_nodes[@]}")
  log_warning "Forcing upgrade for all nodes, not just those that have updates available."
else
  # shellcheck disable=2207
  upgrade_nodes=($(get_nodes_upgradeable cluster_nodes))
fi

if [[ ${#upgrade_nodes[@]} -eq 0 ]]; then
  log_success "No nodes need updates. Exiting."
  exit 0
fi

log_success "Using '${upgrade_nodes[*]}' as node upgrade sequence."

for node in "${upgrade_nodes[@]}"; do
   log_success "[$node] Starting upgrade steps for node"
   node_pre_upgrade "$node"
   node_upgrade "$node"
   node_reboot "$node"
   node_post_upgrade "$node"
   log_success "[$node] Node successfully upgraded."
done

log_success "Nodes '${upgrade_nodes[*]}' successfully upgraded."
