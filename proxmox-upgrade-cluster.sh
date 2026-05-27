#!/usr/bin/env bash

shopt -s extglob

set -o errexit -o nounset -o pipefail
shopt -s inherit_errexit

declare program_name
program_name="$(basename "$0")"
declare ssh_user="${PVE_UPGRADE_SSH_USER:-root}"
declare ssh_key_auth_only=true
declare cluster_node_use_ip=false
declare force_upgrade=false
declare force_reboot=false
declare dry_run=false
declare use_maintenance_mode=true
declare allow_running_guests=false
declare allow_running_tasks=false
declare jq_bin="jq"
declare -i reboot_timeout=600
declare -i verbose=0

declare cluster_node
declare -a pkgs_reinstall=()
declare -a cluster_nodes=()
declare -a upgrade_nodes=()
declare -a ssh_options=()


log_output() {
  cat - >&2
}

wait_sleep() {
  # Indirection so tests can override sleep without trapping the builtin.
  local duration=${1?}
  sleep "$duration"
}

log_pipe_level() {
  # pipe to log_output with prefix and optional timestamp
  local -i level=${1?}
  local prefix_arg="${2:-}"

  # Return if verbosity level is not met.
  test $verbose -lt $level && return 0

  local prefix="${LOG_PREFIX:-}${prefix_arg}"

  if [[ $verbose -ge 1 ]]; then
    declare -a log_level_map=(
      "INFO   "
      "VERBOSE"
      "DEBUG  "
      "DEBUG2 "
      "DEBUG3 "
      "SSH    "
      "BASH   "
      "SSH2   "
    )
    local level_name=${log_level_map[$level]:=$level}
    local prefix="[$level_name]${prefix}"
  fi

  # Log milliseconds when verbose >= 3 for high-resolution debugging
  if [[ $verbose -ge 3 ]]; then
    while IFS= read -r line; do
      local rt_sec="${EPOCHREALTIME%%.*}"
      local rt_usec="${EPOCHREALTIME##*.}"
      [ -z "$line" ] && continue
      printf "[%(%F %T)T.%s]$prefix %s\n" "$rt_sec" "$rt_usec" "$line" | log_output
    done
  else
    while IFS= read -r line; do
      local rt_sec="${EPOCHREALTIME%%.*}"
      [ -z "$line" ] && continue
      printf "[%(%F %T)T]$prefix %s\n" "$rt_sec" "$line" | log_output
    done
  fi

}

log_level() {
  local -i level=${1?}
  shift
  echo -e "$@" | log_pipe_level "$level"
}

log_prefix() {
  local prefix=${1?}
  shift
  LOG_PREFIX+="[$prefix]" "$@"
}

log_info() {
  # Alias for log_level 0
  log_level 0 "$@"
}

log_verbose() {
  # Alias for log_level 1
  log_level 1 "$@"
}

log_debug() {
  # Alias for log_level 2
  log_level 2 "$@"
}

log_debug2() {
  # Alias for log_level 3
  log_level 3 "$@"
}

log_debug3() {
  # Alias for log_level 4
  log_level 4 "$@"
}

log_color() {
  local -i color=${1?}
  shift
  log_level 0 "\033[0;${color}m${*}\033[0m"
}

log_alert() {
  # Log in red
  log_color 31 "$@"
}

log_error() {
  # Alias to log_alert
  log_alert "$@"
}

log_status() {
  # Log in purple
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

log_progress() {
  local duration=${1?}
  # Only log progress when no verbosity
  if [[ $verbose -eq 0 ]]; then
    echo -n '.' | log_output
  fi
  wait_sleep "$duration"
}

log_progress_end() {
  # Clears progress line
  # Only log progress when no verbosity
  if [[ $verbose -eq 0 ]]; then
    # Erase line, move cursor to start of line.
    printf "\033[2K\r" | log_output
  fi
}

wait_all_succeed() {
  local cmd=${1?}
  local -n args=${2?}

  local -A pids

  for arg in "${args[@]}"; do
    (
      # Inside the subshell BASHPID matches the parent's $!, so log lines
      # tagged with [pid] line up with pids[$pid] entries below.
      if [[ $verbose -ge 4 ]]; then
        LOG_PREFIX="[${BASHPID}]${LOG_PREFIX:-}"
      fi
      "$cmd" "$arg"
    ) &
    local pid=$!
    pids["$pid"]="$cmd $arg"
    log_prefix $pid log_prefix "${FUNCNAME[0]}" log_debug3 "Started Job: \`$cmd $arg\`"
  done

  local -i failed_count=0

  for pid in "${!pids[@]}"; do
    wait "$pid"
    local cmd_exit=$?
    local cmd="${pids["$pid"]}"
    log_prefix "$pid" log_prefix "${FUNCNAME[0]}" log_debug3 "Finished Job: \`$cmd\` exit: $cmd_exit"

    if [[ $cmd_exit -gt 0 ]]; then
      (( failed_count += 1 ))
      log_prefix "$pid" log_prefix "${FUNCNAME[0]}" log_error "Job Error: \`$cmd\` exit: $cmd_exit"
    fi
  done

  return $failed_count
}

local_ssh() {
  command ssh "$@"
}

node_ssh() {
  local host=${1?}; shift
  local cmd=${1?}; shift
  log_prefix "$host" log_debug "Running command '$cmd'"

  local_ssh "$host" "${ssh_options[@]}" "$@" "$cmd" 2> >(log_prefix "$host" log_pipe_level 3 "[stderr]")
}

node_ssh_no_op() {
  local node=${1?}; shift
  local cmd=${1?}; shift
  if [[ "$dry_run" = true ]]; then
    log_prefix "NO-OP" log_prefix "$node" log_warning " Not running '$cmd'"
    return 0
  fi
  node_ssh "$node" "$cmd" "$@"
}

node_pvesh() {
  local node=${1?}
  local path=${2?}
  local args=${3:-}
  log_prefix "$node" log_debug2 "JSON output:"
  node_ssh "$node" "pvesh get $path $args --output-form=json" | tee >($jq_bin | log_pipe_level 3 "[$node]")
}

is_node_up() {
  local node=${1?}
  local timeout=${2:-5}
  node_ssh "$node" whoami "-oConnectTimeout=$timeout" | log_pipe_level 3 "[$node]"
  local -i node_status=$?
  if [[ $node_status -eq 0 ]]; then
    log_prefix "$node" log_debug "Node is up."
  else
    log_prefix "$node" log_debug "Node is down."
  fi
  return $node_status
}

all_nodes_up() {
  local -n nodes=${1?}
  wait_all_succeed is_node_up nodes
}

get_cluster_nodes() {
  # Emit one node per line so callers can read into an array via mapfile -t.
  local node=${1?}
  if [[ "$cluster_node_use_ip" == true ]]; then
    node_pvesh "$node" "cluster/status" | $jq_bin -r '.[] | select(.type == "node") | .ip'
  else
    node_pvesh "$node" "cluster/status" | $jq_bin -r '.[] | select(.type == "node") | .name'
  fi
}

is_node_proxmox() {
  local node=${1?}
  node_ssh "$node" 'hash pvesh' | log_pipe_level 4 "[$node]"
  local -i node_status=$?
  if [[ $node_status -ne 0 ]]; then
    log_prefix "$node" log_alert "Node is not proxmox."
  fi
  return $node_status
}

all_nodes_proxmox() {
  local -n nodes=${1?}
  wait_all_succeed is_node_proxmox nodes
}

node_has_updates() {
  local node=${1?}
  local updates
  updates="$(node_ssh "$node" 'DEBIAN_FRONTEND=noninteractive apt-get -qq -s upgrade')"
  echo "$updates" | log_pipe_level 2 "[$node][apt]"
  [[ -n "$updates" ]]
}

get_nodes_upgradeable() {
  local -n nodes=${1?}
  local -a nodes_with_updates=()

  for node in "${nodes[@]}"; do
    if node_has_updates "$node"; then
      log_prefix "$node" log_success "Updates available."
      nodes_with_updates+=("$node")
    else
      log_prefix "$node" log_success "No updates available."
      log_prefix "$node" log_verbose "Removed from upgrade sequence."
    fi
  done
  # Emit one node per line so callers can read into an array via mapfile -t.
  # Guard against the empty case — printf '%s\n' "${empty[@]}" would emit
  # a single blank line.
  if [[ ${#nodes_with_updates[@]} -gt 0 ]]; then
    printf '%s\n' "${nodes_with_updates[@]}"
  fi
}

node_apt_update() {
  local node=${1?}
  node_ssh "$node" 'DEBIAN_FRONTEND=noninteractive apt-get update' | log_pipe_level 1 "[$node][apt]"
}

apt_update_nodes() {
  local -n nodes=${1?}
  wait_all_succeed node_apt_update nodes
}

node_get_running() {
  local node=${1?}
  local type=${2?}
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_pvesh "$node" "nodes/\$(hostname)/$type" | $jq_bin -rc '[.[] | select(.status != "stopped")]'
}

node_get_running_guest_count() {
  local node=${1?}

  local -i lxc_count
  lxc_count="$(node_get_running "$node" "lxc" | $jq_bin -rc '.|length')"
  log_prefix "$node" log_verbose "Running LXC count: $lxc_count"

  local -i qemu_count
  qemu_count="$(node_get_running "$node" "qemu" | $jq_bin -rc '.|length')"
  log_prefix "$node" log_verbose "Running QEMU count: $qemu_count"

  echo "$((lxc_count + qemu_count))"
}

node_get_offline_count() {
  local node=${1?}
  node_pvesh "$node" 'cluster/ha/status/manager_status' | $jq_bin -rc '[.manager_status.node_status[] | select(. != "online")] | length'
}

node_get_mode() {
  local node=${1?}
  local hostname
  hostname=$(node_ssh "$node" hostname)
  node_pvesh "$node" 'cluster/ha/status/manager_status' | $jq_bin -rc ".manager_status.node_status.$hostname"
}

node_service_running() {
  local node=${1?}
  local service=${2?}
  [[ "$(node_ssh "$node" "systemctl is-active $service")" == "active" ]]
}

node_wait_until_service_running() {
  local node=${1?}
  local service=${2?}

  # Exit early without logging if running.
  if node_service_running "$node" "$service"; then
    return 0
  fi

  log_prefix "$node" log_status "Waiting until service '$service' is running..."
  until node_service_running "$node" "$service"; do
    log_progress 1s
  done
  log_progress_end
  log_prefix "$node" log_success "Service '$service' started."
}

node_wait_until_mode() {
  local node=${1?}
  local target_mode=${2?}

  log_prefix "$node" log_status "Waiting until node enters $target_mode mode..."
  local mode
  mode=$(node_get_mode "$node")
  until [[ "$mode" == "$target_mode" ]]; do
    log_prefix "$node" log_verbose "Current mode '$mode' target mode '$target_mode'."
    log_progress 1s
    mode=$(node_get_mode "$node")
  done
  log_progress_end
  log_prefix "$node" log_success "Reached target mode '$target_mode'."
}

node_wait_until_no_running_guests() {
  local node=${1?}

  if [[ "$allow_running_guests" == true ]]; then
    log_prefix "$node" log_warning "Not checking for running guests."
    return 0
  fi

  log_prefix "$node" log_status "Waiting until all guests are migrated..."

  local -i count
  count="$(node_get_running_guest_count "$node")"
  until [[ $count -eq 0 ]]; do
    log_prefix "$node" log_verbose "Number of guests running: $count"
    log_progress 5s
    count="$(node_get_running_guest_count "$node")"
  done
  log_progress_end
  log_prefix "$node" log_success "Reached zero running guests."
}

node_number_of_running_tasks() {
  local node=${1?}
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_pvesh "$node" 'nodes/$(hostname)/tasks' '--source=active' | $jq_bin -rc '.|length'
}

node_not_running_task() {
  local node=${1?}
  local -i task_count
  task_count=$(node_number_of_running_tasks "$node")
  log_prefix "${FUNCNAME[0]}" log_prefix "$node" log_debug "Task Count: $task_count"
  if [[ $task_count -gt 0 ]]; then
    log_prefix "$node" log_info "Running a task. Task Count: $task_count"
  fi
  return $task_count
}

any_nodes_running_tasks() {
  local -n nodes=${1?}
  wait_all_succeed node_not_running_task nodes
}

node_wait_all_tasks_completed() {
  local node=${1?}

  if [[ "$allow_running_tasks" == true ]]; then
    log_prefix "$node" log_warning "Not checking for running tasks."
    return 0
  fi

  log_prefix "$node" log_status "Waiting until all cluster tasks have completed..."
  local -i task_count
  task_count=$(node_number_of_running_tasks "$node")
  until [[ $task_count -eq 0 ]]; do
    log_prefix "$node" log_verbose "Number of running cluster tasks: $task_count"
    log_progress 5s
    task_count=$(node_number_of_running_tasks "$node")
  done
  log_progress_end
  log_prefix "$node" log_success "Cluster reached zero running tasks."
}

node_pre_maintenance_check() {
  local node=${1?}

  log_prefix "$node" log_status "Checking that no cluster nodes are currently offline..."
  local -i count
  count="$(node_get_offline_count "$node")"
  until [[ "$count" -eq 0 ]]; do
    log_prefix "$node" log_verbose "At least one cluster node is currently offline. Waiting..."
    log_progress 1s
    count="$(node_get_offline_count "$node")"
  done
  log_progress_end
  log_prefix "$node" log_success "All cluster nodes are online."
}

node_enter_maintenance() {
  local node=${1?}

  if [[ "$use_maintenance_mode" == false ]]; then
    log_prefix "$node" log_warning "Not setting maintenance mode."
    return 0
  fi

  log_prefix "$node" log_status "Enabling maintenance mode."
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_ssh_no_op "$node" 'ha-manager crm-command node-maintenance enable $(hostname)' | log_pipe_level 1 "[$node]    "

  # Don't wait for maintenance when dry-run
  if [[ "$dry_run" == true ]]; then return 0; fi

  node_wait_until_mode "$node" "maintenance"
}

node_exit_maintenance() {
  local node=${1?}

  if [[ "$use_maintenance_mode" == false ]]; then
    return 0
  fi

  node_wait_until_service_running "$node" "pve-ha-lrm"

  log_prefix "$node" log_status "Disabling maintenance mode."
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_ssh_no_op "$node" 'ha-manager crm-command node-maintenance disable $(hostname)' | log_pipe_level 1 "[$node]    "

  # Don't wait for maintenance when dry-run
  if [[ "$dry_run" == true ]]; then return 0; fi

  node_wait_until_mode "$node" "online"
}

node_pre_upgrade() {
  local node=${1?}
  node_pre_maintenance_check "$node"
  node_enter_maintenance "$node"
  node_wait_all_tasks_completed "$node"

  # Don't wait for no running guests when dry-run
  if [[ "$dry_run" == true ]]; then return 0; fi

  node_wait_until_no_running_guests "$node"
}

node_upgrade() {
  local node=${1?}
  node_ssh_no_op "$node" 'DEBIAN_FRONTEND=noninteractive apt-get dist-upgrade -y' | log_pipe_level 0 "[$node][apt]"
}

node_needs_reboot() {
  local node=${1?}
  local expected_kernel booted_kernel

  booted_kernel=$(node_ssh "$node" 'uname -r')

  if node_ssh "$node" 'hash proxmox-boot-tool'; then
    # Manually pinned kernels override the automatic list; otherwise the
    # highest-versioned automatic entry is what boots next. Parse locally
    # to keep the remote command quoting simple.
    # Tolerate optional leading whitespace — `proxmox-boot-tool kernel list`
    # indents kernel entries on some installs.
    expected_kernel=$(node_ssh "$node" 'proxmox-boot-tool kernel list' | awk '
      /^Manually selected kernels:/{s="m";next}
      /^Automatically selected kernels:/{s="a";next}
      s=="m" && /^[[:space:]]*[0-9]/{m[++mc]=$1}
      s=="a" && /^[[:space:]]*[0-9]/{a[++ac]=$1}
      END {
        if (mc) for(i=1;i<=mc;i++) print m[i]
        else for(i=1;i<=ac;i++) print a[i]
      }
    ' | sort -V | tail -n1)
  else
    # Fallback for older installs without proxmox-boot-tool — parse grub.cfg.
    # The /ROOT/pve-1@ strip handles the default ZFS root dataset name.
    expected_kernel=$(node_ssh "$node" 'grep vmlinuz /boot/grub/grub.cfg' \
      | head -1 | awk '{ print $2 }' \
      | sed -e 's%/boot/vmlinuz-%%;s%/ROOT/pve-1@%%')
  fi

  test "$expected_kernel" != "$booted_kernel"
}

node_reboot() {
  local node=${1?}

  if [[ "$force_reboot" == true ]]; then
    log_prefix "$node" log_warning "Forcing Reboot."
  elif node_needs_reboot "$node"; then
    log_prefix "$node" log_warning "Needs to be rebooted."
  else
    log_prefix "$node" log_success "Doesn't need to be rebooted."
    return 0
  fi

  if [[ $dry_run == true ]]; then
    log_prefix "NO-OP" log_prefix "$node" log_warning "Not rebooting."
    return 0
  fi

  log_prefix "$node" log_alert "Rebooting in 5 seconds! Press CTRL-C to cancel..."
  wait_sleep 5s
  log_prefix "$node" log_status "Rebooting, logging shutdown dmesg:"
  # Keepalive options bound the time we will wait for ssh to drop while the
  # node is shutting down. Without these the dmesg -W follower can block until
  # the kernel's default TCP timeout, which delays the come-back-up poll loop.
  local -a reboot_ssh_opts=(-oConnectTimeout=10 -oServerAliveInterval=5 -oServerAliveCountMax=2)
  node_ssh_no_op "$node" 'reboot' "${reboot_ssh_opts[@]}" 2>&1 | log_pipe_level 3 "[$node]    " && true
  node_ssh_no_op "$node" 'dmesg -W' "${reboot_ssh_opts[@]}" 2>&1 | log_pipe_level 0 "[$node]    " && true

  log_prefix "$node" log_status "Waiting up to ${reboot_timeout}s for node to come back up..."
  SECONDS=0
  until is_node_up "$node"; do
    if (( SECONDS >= reboot_timeout )); then
      log_progress_end
      log_prefix "$node" log_error "Timed out after ${reboot_timeout}s waiting for '$node' to come back up."
      return 1
    fi
    log_progress 1s
  done
  log_progress_end

  log_prefix "$node" log_success "Rebooted successfully."
}

node_post_upgrade() {
  local node=${1?}

  if [[ ${#pkgs_reinstall[@]} -gt 0 ]]; then
    log_prefix "$node" log_success "Force reinstalling '${pkgs_reinstall[*]}'..."
    node_ssh_no_op "$node" "DEBIAN_FRONTEND=noninteractive apt-get reinstall ${pkgs_reinstall[*]}" | log_pipe_level 0 "[$node][apt]"
  else
    log_prefix "$node" log_info "No packages to force reinstall."
  fi
  log_prefix "$node" log_success "Removing old packages..."
  node_ssh_no_op "$node" "DEBIAN_FRONTEND=noninteractive apt-get autoremove -y && apt-get autoclean -y" | log_pipe_level 0 "[$node][apt]"
  node_exit_maintenance "$node"
}

node_run_update_sequence() {
  local node=${1?}
  local in_maintenance=false

  # Warn the operator if we abort while the node may still be in maintenance.
  # The trap does not auto-recover — the operator must investigate the failure
  # before returning the node to service. Do NOT enable `set -E` here: errtrace
  # propagates this trap into process substitutions (e.g. `tee >(jq | ...)`
  # inside node_pvesh) where it fires on benign internal non-zero exits.
  # Without errtrace the trap still fires correctly on the direct simple
  # commands below — node_pre_upgrade, node_upgrade, etc. — when they
  # propagate a failure back to this scope.
  # shellcheck disable=SC2064 # $node is intentionally expanded at trap-install
  trap "if [[ \"\$in_maintenance\" == true ]]; then
    log_prefix '$node' log_warning \"Upgrade aborted while node may still be in maintenance mode. Clear manually after investigation: ha-manager crm-command node-maintenance disable <hostname>\"
  fi" ERR

  log_prefix "$node" log_success "Starting upgrade."
  [[ "$use_maintenance_mode" == true ]] && in_maintenance=true
  node_pre_upgrade "$node"
  node_upgrade "$node"
  node_reboot "$node"
  node_post_upgrade "$node"
  in_maintenance=false

  trap - ERR

  log_prefix "$node" log_success "Successfully upgraded."
}

usage() {
cat << EOF
NAME
    $program_name - Perform a rolling upgrade for a Proxmox cluster

SYNOPSIS
    $program_name [OPTIONS] --cluster-node|-c [NODE]

    $program_name [OPTIONS] --node|-n [NODE] -n [NODE] [...]

    $program_name --help

OPTIONS

    -c HOSTNAME, --cluster-node HOSTNAME
        A node in a cluster to pull all nodes from.

    -n HOSTNAME, --node HOSTNAME
        Node(s) to upgrade. Can be passed multiple times.

    -u USER, --ssh-user USER
        SSH user to authenticate with. Defaults to "$ssh_user".

    -o SSH_OPT, --ssh-opt SSH_OPT
        Options to pass to ssh. Can be passed multiple times.

    --ssh-allow-password-auth
        Default is to force SSH key auth with 'PasswordAuthentication=no'. Set
        this to allow ssh password auth. This is strongly recommended against.
        You may have to enter your password hundreds of times.

    --cluster-node-use-ip
        When using '--cluster-node', use the IP address instead of the node name.

    --dry-run
        Flag to enable a dry run mode where no actions are taken.

    --pkg-reinstall PACKAGE
        Package(s) on the hosts to reinstall with 'apt-get reinstall' post
        upgrade. Can be passed multiple times. Defaults to "${pkgs_reinstall[@]}".

    --force-upgrade
        Flag to force all nodes to upgrade, and not only those with available upgrades.

    --force-reboot
        Flag to force all nodes to be rebooted during upgrade, and not only
        those that aren't booted with the same kernel as the currently installed
        one.

    --no-maintenance-mode
        Don't set node to maintenance mode when upgrading. This will disable
        HA migrations.

    --allow-running-guests
        Disable check for running guests on the node prior to upgrade.

    --allow-running-tasks
        Disable check for running tasks on the cluster prior to upgrade.

    --reboot-timeout SECONDS
        Maximum number of seconds to wait for a node to come back up after a
        reboot before aborting the upgrade. Defaults to $reboot_timeout.

    --jq-bin PATH
        Path to 'jq' binary.

    -v, --verbose
        Log actions and details to stdout. When multiple -v options are given,
        enable verbose logging for de-bugging purposes.

    -h, --help
        Show this message.

EXAMPLE

    Upgrade all nodes in a cluster, retrieving the cluster nodes from 'pve1':

        $program_name -c pve1


    Upgrade only nodes pve2, pve3:

        $program_name -n pve2 -n pve3
EOF
}

error_on_no_arg() {
  # allow_dash defaults to false: by default, reject values that look like
  # another flag (e.g. `--node --dry-run`). Pass `true` for flags whose values
  # legitimately start with a dash, like --ssh-opt.
  local arg=${1?}
  local value=${2:-}
  local allow_dash=${3:-false}
  if [[ -z $value ]]; then
    log_error "ERROR: No arg passed for '$arg'."
    log_error "See --help for usage."
    exit 1
  fi
  if [[ $allow_dash != true && $value == -* ]]; then
    log_error "ERROR: '$arg' requires a value, got flag '$value'."
    log_error "See --help for usage."
    exit 1
  fi
}

process_args() {
  if [[ $# -eq 0 ]]; then
    log_error "No arguments passed."
    usage
    exit 1
  fi;

  while [[ $# -ne 0 ]]; do
    case "${1?}" in
      --cluster-node|-c)
        shift
        error_on_no_arg "--cluster-node|-c" "${1:-}"
        cluster_node="$1"
        ;;
      --node|-n)
        shift
        error_on_no_arg "--node|-n" "${1:-}"
        cluster_nodes+=("$1")
        ;;
      --ssh-user|-u)
        shift
        error_on_no_arg "--ssh-user" "${1:-}"
        ssh_user="$1"
        ;;
      --ssh-opt|-o)
        shift
        error_on_no_arg "--ssh-opt" "${1:-}" true
        ssh_options+=("$1")
        ;;
      --ssh-allow-password-auth)
        ssh_key_auth_only=false
        ;;
      --cluster-node-use-ip)
        cluster_node_use_ip=true
        ;;
      --dry-run)
        dry_run=true
        ;;
      --pkg-reinstall)
        shift
        error_on_no_arg "--pkg-reinstall" "${1:-}"
        pkgs_reinstall+=("$1")
        ;;
      --force-upgrade)
        force_upgrade=true
        ;;
      --force-reboot)
        force_reboot=true
        ;;
      --no-maintenance-mode)
        use_maintenance_mode=false
        ;;
      --allow-running-guests)
        allow_running_guests=true
        ;;
      --allow-running-tasks)
        allow_running_tasks=true
        ;;
      --reboot-timeout)
        shift
        error_on_no_arg "--reboot-timeout" "${1:-}"
        reboot_timeout="$1"
        ;;
      --jq-bin)
        shift
        error_on_no_arg "--jq-bin" "${1:-}"
        jq_bin="$1"
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
        log_error "$program_name ERROR: unknown option '${1?}'"
        log_error "Use $program_name --help for help with command-line options."
        exit 1
        ;;
      *)
        break
        ;;
    esac
    shift
  done

  test $verbose -ge 5 && ssh_options+=("-v")
  test $verbose -ge 6 && set -x
  test $verbose -ge 7 && ssh_options+=("-v")

  ssh_options+=(-l "$ssh_user")
  [[ "$ssh_key_auth_only" == true ]] && ssh_options+=(-o "PasswordAuthentication=no")

  if [[ -z ${cluster_node:-} && ${#cluster_nodes[@]} -eq 0 ]]; then
    log_error "ERROR: One of --cluster-node, or --nodes must be used."
    log_error "See --help for usage."
    exit 1
  fi

  if [[ -n ${cluster_node:-} && ${#cluster_nodes[@]} -ne 0 ]]; then
    log_error "ERROR: Only one of --cluster-node, or --nodes can be used."
    log_error "See --help for usage."
    exit 1
  fi
}

main() {
  process_args "$@"

  if [[ "$dry_run" == true ]]; then
    log_warning "Running in dry run mode."
  fi

  if [[ -n ${cluster_node:-} ]]; then
    log_status "Getting all cluster nodes from node '$cluster_node'..."
    if ! is_node_up "$cluster_node"; then
      log_error "$cluster_node node is currently down."
      exit 1
    fi
    if ! is_node_proxmox "$cluster_node"; then
      exit 1
    fi
    mapfile -t cluster_nodes < <(get_cluster_nodes "$cluster_node")
  fi

  if [[ ${#cluster_nodes[@]} -eq 0 ]]; then
    log_error "No cluster nodes to check. Pass --node, or use --cluster-node with a node that returns cluster members."
    exit 1
  fi

  log_success "Using '${cluster_nodes[*]}' as all nodes to check."

  log_status "Checking if any nodes are currently down..."
  if ! all_nodes_up cluster_nodes; then
    log_error "At least one node is currently down."
    exit 1
  else
    log_success "All nodes are up."
  fi

  log_status "Checking if any nodes are not proxmox..."
  if ! all_nodes_proxmox cluster_nodes; then
    log_error "At least one node doesn't seem to be proxmox."
    exit 1
  else
    log_success "All nodes are proxmox."
  fi

  log_status "Checking if any nodes are currently not online..."
  if [[ $(node_get_offline_count "${cluster_nodes[0]}") -ne 0 ]]; then
    log_error "At least one node is currently not online."
    exit 1
  else
    log_success "All nodes are online."
  fi

  if [[ "$allow_running_tasks" == true ]]; then
    log_warning "Not checking for running cluster tasks."
  else
    log_status "Checking if any nodes currently have tasks running..."
    if ! any_nodes_running_tasks cluster_nodes; then
      log_error "At least one node is currently running tasks."
      exit 1
    else
      log_success "No tasks are running."
    fi
  fi

  log_status "Checking for updates on all nodes..."
  apt_update_nodes cluster_nodes

  if [[ "$force_upgrade" == true ]]; then
    upgrade_nodes=("${cluster_nodes[@]}")
    log_warning "Forcing upgrade for all nodes, not just those that have updates available."
  else
    mapfile -t upgrade_nodes < <(get_nodes_upgradeable cluster_nodes)
  fi

  if [[ "$use_maintenance_mode" == false ]]; then
    log_warning "Not using maintenance mode when upgrading."
  fi

  if [[ ${#upgrade_nodes[@]} -eq 0 ]]; then
    log_success "No nodes need updates. Exiting."
    exit 0
  fi

  log_success "Using '${upgrade_nodes[*]}' as node upgrade sequence."

  for node in "${upgrade_nodes[@]}"; do
    node_run_update_sequence "$node"
  done

  log_success "Nodes '${upgrade_nodes[*]}' successfully upgraded."
}

# Exit here if sourced by shellspec
${__SOURCED__:+return}

main "$@"
