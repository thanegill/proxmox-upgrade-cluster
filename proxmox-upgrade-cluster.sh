#!/usr/bin/env bash

shopt -s extglob

set -o errexit -o nounset -o pipefail
shopt -s inherit_errexit

declare program_name
program_name="$(basename "$0")"
declare ssh_user="${PVE_UPGRADE_SSH_USER:-root}"
declare ssh_key_auth_only=true
declare ssh_multiplexing=true
declare cluster_node_use_ip=false
declare force_upgrade=false
declare force_reboot=false
declare skip_reboot=false
declare dry_run=false
declare use_maintenance_mode=true
declare allow_running_guests=false
declare allow_running_tasks=false
declare preserve_discovery_order=false
declare reboot_only=false
declare -i reboot_timeout=900
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

  # EPOCHREALTIME uses the locale's decimal separator; in non-C locales (e.g.
  # de_DE.UTF-8 uses ','), the %%.* / ##.* expansions would not split and the
  # printf %s arg below would be the entire timestamp string. Force C numeric.
  local LC_NUMERIC=C

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
    local level_name=${log_level_map[$level]:-$level}
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

log_color() {
  local -i color=${1?}
  shift
  log_level 0 "\033[0;${color}m${*}\033[0m"
}

log_error() {
  # Log in red
  log_color 31 "$@"
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

node_wait_with_progress() {
  # Poll until a predicate succeeds, showing progress dots. The remaining args
  # ("$@" after the first four) are the predicate command: it returns 0 when
  # done waiting and logs its own per-iteration detail while still waiting.
  local node=${1?}
  local interval=${2?}
  local status_msg=${3?}
  local success_msg=${4?}
  shift 4

  log_prefix "$node" log_status "$status_msg"
  until "$@"; do
    log_progress "$interval"
  done
  log_progress_end
  log_prefix "$node" log_success "$success_msg"
}

health_check() {
  # Run a pre-flight health check: emit the status line, capture the failing
  # nodes produced by the command in "$@" (one node name per line), then
  # either log success or name the offenders and exit 1.
  local status_msg=${1?}
  local error_msg=${2?}
  local success_msg=${3?}
  shift 3

  log_status "$status_msg"
  local -a bad=()
  mapfile -t bad < <("$@")
  if [[ ${#bad[@]} -gt 0 ]]; then
    # Node names contain no spaces, so a default-IFS join with the spaces
    # rewritten to ", " yields a human-readable "pveA, pveB".
    local joined="${bad[*]}"
    log_error "$error_msg: ${joined// /, }."
    exit 1
  fi
  log_success "$success_msg"
}

wait_all() {
  local cmd=${1?}
  local -n _args=${2?}
  # Optional out-array names: 3rd receives the args of FAILED jobs, 4th the
  # args of SUCCEEDED jobs. Both come back in input order.
  local failed_out_name=${3:-}
  local succeeded_out_name=${4:-}

  # Indexed (not associative) so the result loop iterates in start order and
  # the collected args preserve the caller's input order.
  local -a job_pids=()
  local -a job_args=()

  for arg in "${_args[@]}"; do
    (
      # Inside the subshell BASHPID matches the parent's $!, so log lines
      # tagged with [pid] line up with the job_pids entries below.
      if [[ $verbose -ge 4 ]]; then
        LOG_PREFIX="[${BASHPID}]${LOG_PREFIX:-}"
      fi
      "$cmd" "$arg"
    ) &
    job_pids+=("$!")
    job_args+=("$arg")
    log_prefix "$!" log_prefix "${FUNCNAME[0]}" log_level 4 "Started Job: \`$cmd $arg\`"
  done

  local -i failed_count=0
  local -a failed_args=()
  local -a succeeded_args=()

  local i
  for i in "${!job_pids[@]}"; do
    local pid="${job_pids[$i]}"
    local arg="${job_args[$i]}"
    wait "$pid"
    local cmd_exit=$?
    log_prefix "$pid" log_prefix "${FUNCNAME[0]}" log_level 4 "Finished Job: \`$cmd $arg\` exit: $cmd_exit"

    if [[ $cmd_exit -gt 0 ]]; then
      ((failed_count += 1))
      failed_args+=("$arg")
      log_prefix "$pid" log_prefix "${FUNCNAME[0]}" log_level 2 "Job Error: \`$cmd $arg\` exit: $cmd_exit"
    else
      log_prefix "$pid" log_prefix "${FUNCNAME[0]}" log_level 2 "Job succeeded: \`$cmd $arg\` exit: $cmd_exit"
      succeeded_args+=("$arg")
    fi
  done

  # Copy results back to the caller's named arrays. The result loop above runs
  # in the caller's shell (only the jobs are subshells), so these nameref
  # writes persist.
  if [[ -n "$failed_out_name" ]]; then
    local -n _failed_out=$failed_out_name
    _failed_out=("${failed_args[@]}")
  fi
  if [[ -n "$succeeded_out_name" ]]; then
    local -n _succeeded_out=$succeeded_out_name
    _succeeded_out=("${succeeded_args[@]}")
  fi

  return $failed_count
}

wait_all_failed() {
  # Emit (one per line) the args whose command failed.
  local cmd=${1?}
  local args_name=${2?}
  local -a _failed=()

  wait_all "$cmd" "$args_name" _failed || true
  if [[ ${#_failed[@]} -gt 0 ]]; then
    printf '%s\n' "${_failed[@]}"
  fi
}

local_ssh() {
  command ssh "$@"
}

node_ssh() {
  local host=${1?}
  local cmd=${2?}
  shift 2
  log_prefix "$host" log_level 2 "Running command '$cmd'"

  local_ssh "$host" "${ssh_options[@]}" "$@" "$cmd" 2> >(log_prefix "$host" log_pipe_level 3 "[stderr]")
}

node_ssh_no_op() {
  local node=${1?}
  local cmd=${2?}
  shift 2
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
  log_prefix "$node" log_level 3 "JSON output:"
  node_ssh "$node" "pvesh get $path $args --output-form=json" | tee >(jq | log_pipe_level 3 "[$node]")
}

is_node_up() {
  local node=${1?}
  local timeout=${2:-5}
  node_ssh "$node" whoami "-oConnectTimeout=$timeout" | log_pipe_level 3 "[$node]"
  local -i node_status=$?
  if [[ $node_status -eq 0 ]]; then
    log_prefix "$node" log_level 2 "Node is up."
  else
    log_prefix "$node" log_level 2 "Node is down."
  fi
  return $node_status
}

get_cluster_nodes() {
  # Emit one node per line so callers can read into an array via mapfile -t.
  local node=${1?}
  if [[ "$cluster_node_use_ip" == true ]]; then
    node_pvesh "$node" "cluster/status" | jq -r '.[] | select(.type == "node") | .ip'
  else
    node_pvesh "$node" "cluster/status" | jq -r '.[] | select(.type == "node") | .name'
  fi
}

is_node_proxmox() {
  local node=${1?}
  node_ssh "$node" 'hash pvesh' | log_pipe_level 4 "[$node]"
  local -i node_status=$?
  if [[ $node_status -ne 0 ]]; then
    log_prefix "$node" log_error "Node is not proxmox."
  fi
  return $node_status
}

node_has_updates() {
  local node=${1?}
  local updates
  updates="$(node_ssh "$node" 'DEBIAN_FRONTEND=noninteractive apt-get -qq -s upgrade')"
  echo "$updates" | log_pipe_level 2 "[$node][apt]"
  if [[ -n "$updates" ]]; then
    log_prefix "$node" log_success "Updates available."
    return 0
  fi
  log_prefix "$node" log_success "No updates available."
  return 1
}

# Populate the array named by $4 (in input order) with the nodes for which
# `predicate` succeeds, logging the rest as dropped from the sequence. Used by
# main() for the upgradeable and reboot-needed filters; the predicate itself
# logs the per-node pass/fail.
filter_nodes() {
  local predicate=${1?}
  local nodes_name=${2?}
  local removed_msg=${3?}
  local out_name=${4?}
  local -n _nodes=$nodes_name

  # wait_all writes the kept (succeeded) nodes into the caller's array via its
  # 4th arg. A failing predicate (no updates / no reboot needed) is the normal
  # "drop this node" signal, so swallow wait_all's non-zero failed count.
  wait_all "$predicate" "$nodes_name" "" "$out_name" || true

  local -n _kept=$out_name
  local node
  for node in "${_nodes[@]}"; do
    # Node names contain no spaces, so this membership test is safe.
    [[ " ${_kept[*]} " == *" $node "* ]] ||
      log_prefix "$node" log_level 1 "$removed_msg"
  done
}

node_apt_update() {
  local node=${1?}
  node_ssh "$node" 'DEBIAN_FRONTEND=noninteractive apt-get update' | log_pipe_level 1 "[$node][apt]"
}

node_get_running_count() {
  local node=${1?}
  local type=${2?}
  local -i count
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  count="$(node_pvesh "$node" "nodes/\$(hostname)/$type" | jq -rc '[.[] | select(.status != "stopped")] | length')"
  log_prefix "$node" log_level 2 "Running ${type^^} count: $count"
  echo "$count"
}

node_get_running_guest_count() {
  local node=${1?}
  local -i lxc_count qemu_count total

  lxc_count="$(node_get_running_count "$node" "lxc")"
  qemu_count="$(node_get_running_count "$node" "qemu")"
  total=$((lxc_count + qemu_count))

  log_prefix "$node" log_level 1 "Number of guests running: $total"
  echo "$total"
}

sort_nodes_by_guest_count() {
  # Reorder the named array ascending by running guest count. Stable so
  # equal-count nodes keep their input order. The nameref is named
  # `nodes_inout` (not `nodes` like read-only helpers above) so shellcheck
  # doesn't conflate the array-write with the read-only namerefs.
  local -n nodes_inout=${1?}
  local -a sorted=()
  local node count
  local lines=""

  log_status "Reordering upgrade sequence by running guest count (ascending)..."
  for node in "${nodes_inout[@]}"; do
    count=$(node_get_running_guest_count "$node")
    lines+="$count $node"$'\n'
  done

  mapfile -t sorted < <(printf '%s' "$lines" | sort -ns -k1,1 | awk '{print $2}')
  nodes_inout=("${sorted[@]}")
}

node_get_offline_nodes() {
  # Emit one offline node name per line so callers can read into an array.
  local node=${1?}
  node_pvesh "$node" 'cluster/ha/status/manager_status' | jq -r '.manager_status.node_status | to_entries[] | select(.value != "online") | .key'
}

node_get_offline_count() {
  local node=${1?}
  local -a offline
  mapfile -t offline < <(node_get_offline_nodes "$node")
  echo "${#offline[@]}"
}

node_get_mode() {
  local node=${1?}
  # The ssh target ($node) may be an IP, short name, or DNS name; the cluster's
  # ha node_status is keyed by the machine's own hostname, so we ask for that
  # over ssh rather than reusing $node.
  local hostname
  hostname=$(node_ssh "$node" hostname)
  # Pass hostname via --arg so values containing '.', leading digits, or other
  # jq-syntax characters don't break the filter.
  node_pvesh "$node" 'cluster/ha/status/manager_status' |
    jq -rc --arg name "$hostname" '.manager_status.node_status[$name]'
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

  node_wait_with_progress "$node" 1s \
    "Waiting until service '$service' is running..." \
    "Service '$service' started." \
    node_service_running "$node" "$service"
}

node_reached_mode() {
  # Polling predicate for the node_set_maintenance mode wait: 0 once in target
  # mode, otherwise log the current/target mode and return non-zero (keep
  # waiting).
  local node=${1?}
  local target_mode=${2?}
  local mode
  mode=$(node_get_mode "$node")
  [[ "$mode" == "$target_mode" ]] && return 0
  log_prefix "$node" log_level 1 "Current mode '$mode' target mode '$target_mode'."
  return 1
}

node_no_running_guests() {
  local node=${1?}
  [[ "$(node_get_running_guest_count "$node")" -eq 0 ]]
}

node_wait_until_no_running_guests() {
  local node=${1?}

  if [[ "$allow_running_guests" == true ]]; then
    log_prefix "$node" log_warning "Not checking for running guests."
    return 0
  fi

  node_wait_with_progress "$node" 5s \
    "Waiting until all guests are migrated..." \
    "Reached zero running guests." \
    node_no_running_guests "$node"
}

node_number_of_running_tasks() {
  local node=${1?}
  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_pvesh "$node" 'nodes/$(hostname)/tasks' '--source=active' | jq -rc '.|length'
}

node_not_running_task() {
  local node=${1?}
  local -i task_count
  task_count=$(node_number_of_running_tasks "$node")
  log_prefix "${FUNCNAME[0]}" log_prefix "$node" log_level 2 "Task Count: $task_count"
  if ((task_count > 0)); then
    log_prefix "$node" log_level 1 "Running a task. Task Count: $task_count"
    return 1
  fi
  return 0
}

node_wait_all_tasks_completed() {
  local node=${1?}

  if [[ "$allow_running_tasks" == true ]]; then
    log_prefix "$node" log_warning "Not checking for running tasks."
    return 0
  fi

  node_wait_with_progress "$node" 5s \
    "Waiting until all cluster tasks have completed..." \
    "Cluster reached zero running tasks." \
    node_no_running_tasks "$node"
}

node_no_running_tasks() {
  # Polling predicate for node_wait_all_tasks_completed: 0 once no tasks are
  # running, otherwise log the count and return non-zero (keep waiting).
  local node=${1?}
  local -i task_count
  task_count=$(node_number_of_running_tasks "$node")
  [[ $task_count -eq 0 ]] && return 0
  log_prefix "$node" log_level 1 "Number of running cluster tasks: $task_count"
  return 1
}

node_cluster_all_online() {
  # Polling predicate for the run_update_sequence pre-flight wait: 0 once no
  # cluster node is offline, otherwise log a waiting notice and return non-zero
  # (keep waiting).
  local node=${1?}
  local -i count
  count="$(node_get_offline_count "$node")"
  [[ $count -eq 0 ]] && return 0
  log_prefix "$node" log_level 1 "At least one cluster node is currently offline. Waiting..."
  return 1
}

node_set_maintenance() {
  local node=${1?}
  # action is "enable" (entering maintenance) or "disable" (exiting).
  local action=${2?}

  if [[ "$use_maintenance_mode" == false ]]; then
    log_prefix "$node" log_warning "Not setting maintenance mode."
    return 0
  fi

  local target_mode
  if [[ "$action" == enable ]]; then
    log_prefix "$node" log_status "Enabling maintenance mode."
    target_mode="maintenance"
  else
    log_prefix "$node" log_status "Disabling maintenance mode."
    target_mode="online"
    # Exiting maintenance needs the HA LRM service up before we can disable it.
    node_wait_until_service_running "$node" "pve-ha-lrm"
  fi

  # shellcheck disable=SC2016 # $(hostname) is supposed to run in remote host.
  node_ssh_no_op "$node" "ha-manager crm-command node-maintenance $action "'$(hostname)' | log_pipe_level 1 "[$node]    "

  # Don't wait for the mode transition when dry-run.
  if [[ "$dry_run" == true ]]; then
    return 0
  fi

  node_wait_with_progress "$node" 1s \
    "Waiting until node enters $target_mode mode..." \
    "Reached target mode '$target_mode'." \
    node_reached_mode "$node" "$target_mode"
}

node_upgrade() {
  local node=${1?}
  if [[ "$reboot_only" == true ]]; then
    log_prefix "$node" log_status "Skipping apt dist-upgrade (--reboot-only)."
    return 0
  fi
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
    expected_kernel=$(node_ssh "$node" 'grep vmlinuz /boot/grub/grub.cfg' |
      head -1 | awk '{ print $2 }' |
      sed -e 's%/boot/vmlinuz-%%;s%/ROOT/pve-1@%%')
  fi

  if [[ "$expected_kernel" != "$booted_kernel" ]]; then
    log_prefix "$node" log_success "Reboot required."
    return 0
  fi
  log_prefix "$node" log_success "No reboot required."
  return 1
}

node_reboot() {
  local node=${1?}

  if [[ "$skip_reboot" == true ]]; then
    if node_needs_reboot "$node"; then
      log_prefix "$node" log_warning "Skipping reboot per --skip-reboot. Node WILL need a reboot to pick up the new kernel."
    else
      log_prefix "$node" log_warning "Skipping reboot per --skip-reboot."
    fi
    return 0
  fi

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

  log_prefix "$node" log_error "Rebooting in 5 seconds! Press CTRL-C to cancel..."
  wait_sleep 5s
  log_prefix "$node" log_status "Rebooting, logging shutdown dmesg:"

  # Time the full reboot (shutdown + boot) from here until the node answers
  # again. SECONDS below bounds only the come-back-up wait, so use a wall
  # clock that spans the whole cycle.
  local -i reboot_started=$EPOCHSECONDS

  # Keepalive options bound the time we will wait for ssh to drop while the
  # node is shutting down. Without these the dmesg -W follower can block until
  # the kernel's default TCP timeout, which delays the come-back-up poll loop.
  local -a reboot_ssh_opts=(-oConnectTimeout=10 -oServerAliveInterval=5 -oServerAliveCountMax=2)
  node_ssh_no_op "$node" 'reboot' "${reboot_ssh_opts[@]}" 2>&1 | log_pipe_level 3 "[$node]    " && true
  node_ssh_no_op "$node" 'dmesg -W' "${reboot_ssh_opts[@]}" 2>&1 | log_pipe_level 0 "[$node]    " && true

  log_prefix "$node" log_status "Waiting up to ${reboot_timeout}s for node to come back up..."
  SECONDS=0
  until is_node_up "$node"; do
    if ((SECONDS >= reboot_timeout)); then
      log_progress_end
      log_prefix "$node" log_error "Timed out after ${reboot_timeout}s waiting for '$node' to come back up."
      return 1
    fi
    log_progress 1s
  done
  log_progress_end

  log_prefix "$node" log_success "Rebooted successfully in $((EPOCHSECONDS - reboot_started))s."
}

node_post_upgrade() {
  local node=${1?}
  if [[ "$reboot_only" == true ]]; then
    log_prefix "$node" log_status "Skipping apt cleanup (--reboot-only)."
    return 0
  fi

  if [[ ${#pkgs_reinstall[@]} -gt 0 ]]; then
    log_prefix "$node" log_success "Force reinstalling '${pkgs_reinstall[*]}'..."
    node_ssh_no_op "$node" "DEBIAN_FRONTEND=noninteractive apt-get reinstall ${pkgs_reinstall[*]}" | log_pipe_level 0 "[$node][apt]"
  else
    log_prefix "$node" log_level 0 "No packages to force reinstall."
  fi
  log_prefix "$node" log_success "Removing old packages..."
  node_ssh_no_op "$node" "DEBIAN_FRONTEND=noninteractive apt-get autoremove -y && apt-get autoclean -y" | log_pipe_level 0 "[$node][apt]"
}

node_run_update_sequence() {
  local node=${1?}
  local in_maintenance=false

  # Maintenance-warning trap.
  #
  # WHAT
  #   If the function aborts (via errexit propagating from any of the four
  #   stage calls below) while `in_maintenance` is true, log a warning that
  #   the node may still be in HA maintenance mode and tell the operator how
  #   to clear it manually. The trap does NOT attempt recovery — operators
  #   need to investigate the upstream failure before returning the node to
  #   service, and an automatic exit-maintenance could mask or race that.
  #
  # WHY no `set -E` (errtrace) here
  #   errtrace propagates ERR traps into nested functions, command
  #   substitutions, and process substitutions. node_pvesh internally pipes
  #   through `tee >(jq | log_pipe_level 3 ...)`; the process substitution
  #   regularly exits non-zero on benign conditions (e.g. log_pipe_level
  #   returning early at verbose<3 closes the pipe, jq gets SIGPIPE). With
  #   errtrace on, the trap fired inside every such process sub and emitted
  #   a spurious "may still be in maintenance" warning on every node, every
  #   upgrade — even when the parent flow succeeded cleanly (see the smoke
  #   test in 59c518d -> 2c544f4). Without errtrace the trap only fires at
  #   THIS scope, when one of the direct stage calls (node_set_maintenance,
  #   node_upgrade, node_reboot, node_post_upgrade, etc.) returns non-zero
  #   — which is exactly the signal we care about.
  #
  # The "does not enable errtrace" test in spec/upgrade_sequence_spec.sh
  # pins this contract: changing the function to `set -E` would re-introduce
  # the spurious-warning regression.
  # shellcheck disable=SC2064 # $node is intentionally expanded at trap-install
  trap "if [[ \"\$in_maintenance\" == true ]]; then
    log_prefix '$node' log_warning \"Upgrade aborted while node may still be in maintenance mode. Clear manually after investigation: ha-manager crm-command node-maintenance disable <hostname>\"
  fi" ERR

  log_prefix "$node" log_success "Starting upgrade."

  # Pre-flight: verify cluster is healthy before touching anything.
  node_wait_with_progress "$node" 1s \
    "Checking that no cluster nodes are currently offline..." \
    "All cluster nodes are online." \
    node_cluster_all_online "$node"

  # Enter maintenance and wait for HA to migrate guests onto peers.
  [[ "$use_maintenance_mode" == true ]] && in_maintenance=true
  node_set_maintenance "$node" enable
  node_wait_all_tasks_completed "$node"
  if [[ "$dry_run" != true ]]; then
    node_wait_until_no_running_guests "$node"
  fi

  # The work.
  node_upgrade "$node"
  node_reboot "$node"
  node_post_upgrade "$node"

  # Exit maintenance.
  node_set_maintenance "$node" disable
  in_maintenance=false

  trap - ERR

  log_prefix "$node" log_success "Successfully upgraded."
}

usage() {
  cat <<EOF
NAME
    $program_name - Perform a rolling upgrade for a Proxmox cluster

SYNOPSIS
    $program_name [OPTIONS] --cluster-node HOSTNAME

    $program_name [OPTIONS] --node HOSTNAME [--node HOSTNAME]...

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
        Allow ssh password auth. Default is to force SSH key auth with
        'PasswordAuthentication=no'.

    --no-ssh-multiplexing
        Disable SSH connection multiplexing. By default a single master
        connection per host is reused (ControlMaster/ControlPath/ControlPersist)
        so the many per-node commands avoid a fresh TCP+auth handshake each time.

    --cluster-node-use-ip
        When using '--cluster-node', use the IP address instead of the node name.

    --dry-run
        Enable dry-run mode; no destructive actions are taken.

    --pkg-reinstall PACKAGE
        Package(s) on the hosts to reinstall with 'apt-get reinstall' post
        upgrade. Can be passed multiple times. Defaults to none.

    --force-upgrade
        Force all nodes to upgrade, and not only those with available upgrades.

    --reboot-only
        Skip apt-update and apt-get dist-upgrade entirely. Filter
        cluster_nodes via node_needs_reboot and reboot just the ones
        running a kernel older than the one staged for boot. Mutually
        exclusive with --force-upgrade, --force-reboot, and
        --skip-reboot.

    --no-maintenance-mode
        Don't set node to maintenance mode when upgrading. This will disable
        HA migrations. Default: maintenance mode is enabled.

    --force-reboot
        Force all nodes to be rebooted during upgrade, and not only those that
        aren't booted with the same kernel as the currently installed one.
        Mutually exclusive with --skip-reboot.

    --skip-reboot
        Skip the reboot step entirely, even when a new kernel is staged for
        boot. Mutually exclusive with --force-reboot.

    --reboot-timeout SECONDS
        Maximum number of seconds to wait for a node to come back up after a
        reboot before aborting the upgrade. Defaults to $reboot_timeout.

    --allow-running-guests
        Disable check for running guests on the node prior to upgrade.

    --allow-running-tasks
        Disable check for running tasks on the cluster prior to upgrade.

    --preserve-discovery-order
        When using --cluster-node, do not reorder the upgrade sequence
        ascending by running guest count. Default is to sort so the node
        with the fewest guests upgrades first.

    -v, --verbose
        Log actions and details. Each repetition unlocks an additional log
        level (all lower levels stay enabled):

            (none)    INFO — status, warnings, errors
            -v        + VERBOSE — high-level script-flow notes
            -vv       + DEBUG — per-node ssh commands as they run
            -vvv      + DEBUG2 — full pvesh JSON responses; timestamps
                       also gain millisecond precision
            -vvvv     + DEBUG3 — internal background-job lifecycle

        Levels beyond -vvvv are for script development:

            -vvvvv    also pass -v to ssh (remote login verbose)
            -vvvvvv   also enable bash 'set -x' (command trace)
            -vvvvvvv  also pass another -v to ssh (ssh -vv)

    -h, --help
        Show this message.

EXAMPLE

    Upgrade all nodes in a cluster, retrieving the cluster nodes from 'pve1':

        $program_name -c pve1


    Upgrade only nodes pve2, pve3:

        $program_name -n pve2 -n pve3


    Reach the cluster through a bastion via an ssh ProxyCommand. Pass each
    ssh option as its own --ssh-opt value:

        $program_name -c pve1 \\
            --ssh-opt "-o ProxyCommand=ssh -W %h:%p bastion.example.com"
EOF
}

error_exit_usage() {
  log_error "ERROR: $1"
  log_error "See --help for usage."
  exit 1
}

error_on_no_arg() {
  # allow_dash defaults to false: by default, reject values that look like
  # another flag (e.g. `--node --dry-run`). Pass `true` for flags whose values
  # legitimately start with a dash, like --ssh-opt.
  local arg=${1?}
  local value=${2:-}
  local allow_dash=${3:-false}
  if [[ -z $value ]]; then
    error_exit_usage "No arg passed for '$arg'."
  fi
  if [[ $allow_dash != true && $value == -* ]]; then
    error_exit_usage "'$arg' requires a value, got flag '$value'."
  fi
}

process_args() {
  if [[ $# -eq 0 ]]; then
    error_exit_usage "No arguments passed."
  fi

  while [[ $# -ne 0 ]]; do
    case "${1?}" in
      --cluster-node | -c)
        error_on_no_arg "${1?}" "${2:-}"
        shift
        cluster_node="$1"
        ;;
      --node | -n)
        error_on_no_arg "${1?}" "${2:-}"
        shift
        cluster_nodes+=("$1")
        ;;
      --ssh-user | -u)
        error_on_no_arg "${1?}" "${2:-}"
        shift
        ssh_user="$1"
        ;;
      --ssh-opt | -o)
        error_on_no_arg "${1?}" "${2:-}" true
        shift
        ssh_options+=("$1")
        ;;
      --ssh-allow-password-auth)
        ssh_key_auth_only=false
        ;;
      --no-ssh-multiplexing)
        ssh_multiplexing=false
        ;;
      --cluster-node-use-ip)
        cluster_node_use_ip=true
        ;;
      --dry-run)
        dry_run=true
        ;;
      --pkg-reinstall)
        error_on_no_arg "${1?}" "${2:-}"
        shift
        pkgs_reinstall+=("$1")
        ;;
      --force-upgrade)
        force_upgrade=true
        ;;
      --reboot-only)
        reboot_only=true
        ;;
      --force-reboot)
        force_reboot=true
        ;;
      --skip-reboot)
        skip_reboot=true
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
      --preserve-discovery-order)
        preserve_discovery_order=true
        ;;
      --reboot-timeout)
        error_on_no_arg "${1?}" "${2:-}"
        shift
        reboot_timeout="$1"
        ;;
      --verbose)
        verbose=$((verbose + 1))
        ;;
      -+(v))
        verbose=$((verbose + ${#1} - 1))
        ;;
      --help | -h)
        usage
        exit 0
        ;;
      -*)
        error_exit_usage "Unknown option '${1?}'"
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

  # Multiplex SSH: the first connection to a host opens a master that the many
  # subsequent per-node commands (probes + 1-5s poll loops) reuse, avoiding a
  # fresh TCP+auth handshake each time. ServerAlive* lets the shared master
  # notice a host dropping (e.g. during reboot) instead of hanging on the
  # dmesg -W follower until the kernel TCP timeout. Quote the values so bash
  # leaves '~' and '%C' for ssh to expand.
  if [[ "$ssh_multiplexing" == true ]]; then
    ssh_options+=(
      -o "ControlMaster=auto"
      -o "ControlPath=~/.ssh/control-%C"
      -o "ControlPersist=60"
      -o "ServerAliveInterval=5"
      -o "ServerAliveCountMax=2"
    )
  fi

  if [[ -z ${cluster_node:-} && ${#cluster_nodes[@]} -eq 0 ]]; then
    error_exit_usage "One of --cluster-node, or --nodes must be used."
  fi

  if [[ -n ${cluster_node:-} && ${#cluster_nodes[@]} -ne 0 ]]; then
    error_exit_usage "Only one of --cluster-node, or --nodes can be used."
  fi

  if [[ "$force_reboot" == true && "$skip_reboot" == true ]]; then
    error_exit_usage "--force-reboot and --skip-reboot cannot be used together."
  fi

  if [[ "$reboot_only" == true ]]; then
    if [[ "$force_upgrade" == true ]]; then
      error_exit_usage "--reboot-only and --force-upgrade cannot be used together."
    fi
    if [[ "$skip_reboot" == true ]]; then
      error_exit_usage "--reboot-only and --skip-reboot cannot be used together."
    fi
    if [[ "$force_reboot" == true ]]; then
      error_exit_usage "--reboot-only and --force-reboot cannot be used together."
    fi
  fi
}

main() {
  process_args "$@"

  if ! command -v jq >/dev/null 2>&1; then
    log_error "ERROR: 'jq' is required but was not found on PATH."
    exit 1
  fi

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

  health_check \
    "Checking if any nodes are currently down..." \
    "At least one node is currently down" \
    "All nodes are up." \
    wait_all_failed is_node_up cluster_nodes

  health_check \
    "Checking if any nodes are not proxmox..." \
    "At least one node doesn't seem to be proxmox" \
    "All nodes are proxmox." \
    wait_all_failed is_node_proxmox cluster_nodes

  health_check \
    "Checking if any nodes are currently not online..." \
    "At least one node is currently not online" \
    "All nodes are online." \
    node_get_offline_nodes "${cluster_nodes[0]}"

  if [[ "$allow_running_tasks" == true ]]; then
    log_warning "Not checking for running cluster tasks."
  else
    health_check \
      "Checking if any nodes currently have tasks running..." \
      "At least one node is currently running tasks" \
      "No tasks are running." \
      wait_all_failed node_not_running_task cluster_nodes
  fi

  if [[ "$reboot_only" == true ]]; then
    log_warning "Reboot-only mode: skipping apt-update and dist-upgrade."
    log_status "Checking which nodes need a reboot..."
    filter_nodes node_needs_reboot cluster_nodes "Removed from reboot sequence." upgrade_nodes
  else
    log_status "Checking for updates on all nodes..."
    wait_all node_apt_update cluster_nodes

    if [[ "$force_upgrade" == true ]]; then
      upgrade_nodes=("${cluster_nodes[@]}")
      log_warning "Forcing upgrade for all nodes, not just those that have updates available."
    else
      filter_nodes node_has_updates cluster_nodes "Removed from upgrade sequence." upgrade_nodes
    fi
  fi

  if [[ "$use_maintenance_mode" == false ]]; then
    log_warning "Not using maintenance mode when upgrading."
  fi

  if [[ ${#upgrade_nodes[@]} -eq 0 ]]; then
    log_success "No nodes need updates. Exiting."
    exit 0
  fi

  if [[ -n "${cluster_node:-}" && "$preserve_discovery_order" == false && ${#upgrade_nodes[@]} -gt 1 ]]; then
    sort_nodes_by_guest_count upgrade_nodes
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
