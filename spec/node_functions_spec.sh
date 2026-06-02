Describe 'usage'
  Include proxmox-upgrade-cluster.sh

  It 'displays help text' do
    When call usage
    The output should include 'Proxmox cluster'
    The output should include 'OPTIONS'
    The output should include '--cluster-node'
    The output should include '--node'
  End
End

Describe 'get_cluster_nodes'
  Include proxmox-upgrade-cluster.sh

  It 'returns node names from pvesh output, one per line' do
    node_pvesh() { echo '[{"type":"node","name":"pve1"},{"type":"node","name":"pve2"}]'; }

    When call get_cluster_nodes 'pve1'
    The line 1 of output should eq 'pve1'
    The line 2 of output should eq 'pve2'
    The lines of output should eq 2
  End

  It 'returns node IPs when cluster_node_use_ip is true, one per line' do
    cluster_node_use_ip=true
    node_pvesh() { echo '[{"type":"node","ip":"10.0.0.1"},{"type":"node","ip":"10.0.0.2"}]'; }

    When call get_cluster_nodes 'pve1'
    The line 1 of output should eq '10.0.0.1'
    The line 2 of output should eq '10.0.0.2'
    The lines of output should eq 2
  End

  It 'returns empty output for a single-element cluster of non-node types' do
    node_pvesh() { echo '[{"type":"cluster","name":"mycluster"}]'; }

    When call get_cluster_nodes 'pve1'
    The output should eq ''
  End

  It 'returns a single line for a single-node cluster' do
    node_pvesh() { echo '[{"type":"node","name":"solo"}]'; }

    When call get_cluster_nodes 'pve1'
    The output should eq 'solo'
    The lines of output should eq 1
  End
End

Describe 'node_get_running_guest_count'
  Include proxmox-upgrade-cluster.sh

  It 'returns total count of running guests' do
    node_get_running_count() {
      if [[ "$2" == "lxc" ]]; then echo '1'; else echo '2'; fi
    }
    When call node_get_running_guest_count 'pve1'
    The output should eq '3'
  End

  It 'returns 0 when no guests are running' do
    node_get_running_count() { echo '0'; }

    When call node_get_running_guest_count 'pve1'
    The output should eq '0'
  End

  It 'logs the running total at verbose>=1' do
    verbose=1
    node_get_running_count() { if [[ "$2" == "lxc" ]]; then echo '4'; else echo '7'; fi; }

    When call node_get_running_guest_count 'pve1'
    The output should eq '11'
    The error should include 'Number of guests running: 11'
  End
End

Describe 'sort_nodes_by_guest_count'
  Include proxmox-upgrade-cluster.sh

  # The function uses `local -n nodes`, so the caller-side array must NOT
  # also be named `nodes` (bash would warn about a circular nameref).
  # main() passes `upgrade_nodes`, so these tests mirror that.

  It 'reorders an array ascending by running guest count' do
    node_get_running_guest_count() {
      case "$1" in
        pveA) echo '5' ;;
        pveB) echo '1' ;;
        pveC) echo '3' ;;
      esac
    }

    capture() {
      local -a upgrade_nodes=(pveA pveB pveC)
      sort_nodes_by_guest_count upgrade_nodes
      printf '%s\n' "${upgrade_nodes[@]}"
    }

    When call capture
    The line 1 of output should eq 'pveB'
    The line 2 of output should eq 'pveC'
    The line 3 of output should eq 'pveA'
    The error should include 'Reordering upgrade sequence'
  End

  It 'is stable on equal counts (preserves input order)' do
    node_get_running_guest_count() { echo '2'; }

    capture() {
      local -a upgrade_nodes=(pve3 pve1 pve2)
      sort_nodes_by_guest_count upgrade_nodes
      printf '%s\n' "${upgrade_nodes[@]}"
    }

    When call capture
    The line 1 of output should eq 'pve3'
    The line 2 of output should eq 'pve1'
    The line 3 of output should eq 'pve2'
    The error should include 'Reordering upgrade sequence'
  End

  It 'handles a single-element array' do
    node_get_running_guest_count() { echo '7'; }

    capture() {
      local -a upgrade_nodes=(soloN)
      sort_nodes_by_guest_count upgrade_nodes
      printf '%s\n' "${upgrade_nodes[@]}"
    }

    When call capture
    The output should eq 'soloN'
    The error should include 'Reordering upgrade sequence'
  End

  It 'leaves an empty array empty' do
    # Defensive: the function reads `${nodes[@]}` so an empty array is
    # fine, the for-loop just doesn't run, and `mapfile -t sorted` reads
    # an empty stream and stays empty.
    node_get_running_guest_count() { echo 'should-not-be-called' >&2; }

    capture() {
      local -a upgrade_nodes=()
      sort_nodes_by_guest_count upgrade_nodes
      echo "len=${#upgrade_nodes[@]}"
    }

    When call capture
    The output should eq 'len=0'
    The error should not include 'should-not-be-called'
  End

  It 'sorts correctly when counts exceed 255 (no mod-256 regression)' do
    # Same regression class as node_not_running_task's old
    # `return $task_count` bug — guard against any future refactor
    # that mistakenly treats the count as an exit code.
    node_get_running_guest_count() {
      case "$1" in
        pveBig)   echo '512' ;;
        pveSmall) echo '7' ;;
        pveZero)  echo '0' ;;
      esac
    }

    capture() {
      local -a upgrade_nodes=(pveBig pveSmall pveZero)
      sort_nodes_by_guest_count upgrade_nodes
      printf '%s\n' "${upgrade_nodes[@]}"
    }

    When call capture
    The line 1 of output should eq 'pveZero'
    The line 2 of output should eq 'pveSmall'
    The line 3 of output should eq 'pveBig'
    The error should include 'Reordering upgrade sequence'
  End
End

Describe 'node_number_of_running_tasks'
  Include proxmox-upgrade-cluster.sh

  It 'returns task count' do
    node_pvesh() { echo '[{"task":"backup"},{"task":"resize"}]'; }

    When call node_number_of_running_tasks 'pve1'
    The output should eq '2'
  End

  It 'returns 0 when no tasks' do
    node_pvesh() { echo '[]'; }

    When call node_number_of_running_tasks 'pve1'
    The output should eq '0'
  End
End

# Build a node_pvesh mock that returns a manager_status JSON document
# from (node, status) pairs:
#
#   make_manager_status_pvesh pve1 online pve2 offline pve3 offline
#
# Uses a global to thread the JSON to the mock — function definitions in
# bash don't close over caller-local variables, so the closure needs to
# live in the global scope (same trick as make_pbt_node_ssh).
make_manager_status_pvesh() {
  local pairs=()
  while (( $# )); do
    pairs+=("\"$1\":\"$2\"")
    shift 2
  done
  _mgr_status_json="{\"manager_status\":{\"node_status\":{$(IFS=,; echo "${pairs[*]}")}}}"
  node_pvesh() { echo "$_mgr_status_json"; }
}

# Build a node_ssh mock that responds to `hostname` with a fixed value and
# silently no-ops every other command. Use for node_get_mode tests where
# the ssh target ($node) and the remote hostname differ (e.g. ssh-by-IP).
#
#   make_hostname_node_ssh pve-prod-1
#
# Same global-closure rationale as the helpers above.
make_hostname_node_ssh() {
  _hostname_value=$1
  node_ssh() {
    [[ "$2" == 'hostname' ]] && echo "$_hostname_value"
  }
}

Describe 'node_get_offline_count'
  Include proxmox-upgrade-cluster.sh

  It 'returns count of offline nodes' do
    make_manager_status_pvesh pve1 online pve2 offline pve3 offline
    When call node_get_offline_count 'pve1'
    The output should eq '2'
  End

  It 'returns 0 when all nodes are online' do
    make_manager_status_pvesh pve1 online pve2 online
    When call node_get_offline_count 'pve1'
    The output should eq '0'
  End
End

Describe 'node_get_offline_nodes'
  Include proxmox-upgrade-cluster.sh

  It 'emits the names of offline nodes one per line' do
    make_manager_status_pvesh pve1 online pve2 offline pve3 offline
    When call node_get_offline_nodes 'pve1'
    The line 1 of output should eq 'pve2'
    The line 2 of output should eq 'pve3'
    The lines of output should eq 2
  End

  It 'emits nothing when all nodes are online' do
    make_manager_status_pvesh pve1 online pve2 online
    When call node_get_offline_nodes 'pve1'
    The output should eq ''
  End
End

Describe 'node_get_mode'
  Include proxmox-upgrade-cluster.sh

  It 'returns node mode from pvesh output' do
    make_hostname_node_ssh pve1
    make_manager_status_pvesh pve1 online
    When call node_get_mode 'pve1'
    The output should eq 'online'
  End

  It 'looks up the remote hostname via ssh, not the ssh-target argument' do
    # $node ("10.0.0.4") is the ssh target; the actual hostname returned by
    # `hostname` on the remote ("pve-prod-1") is what indexes node_status.
    make_hostname_node_ssh pve-prod-1
    make_manager_status_pvesh pve-prod-1 maintenance
    When call node_get_mode '10.0.0.4'
    The output should eq 'maintenance'
  End

  It 'handles hostnames containing dots without breaking the jq filter' do
    make_hostname_node_ssh pve.dc1.example.com
    make_manager_status_pvesh pve.dc1.example.com online
    When call node_get_mode 'pve1'
    The output should eq 'online'
  End

  It 'handles hostnames that start with a digit' do
    make_hostname_node_ssh 1node-prod
    make_manager_status_pvesh 1node-prod online
    When call node_get_mode 'pve1'
    The output should eq 'online'
  End

  It 'does not leak $hostname into the caller scope' do
    make_hostname_node_ssh pve1
    make_manager_status_pvesh pve1 online
    leak_check() {
      unset hostname
      node_get_mode 'pve1' >/dev/null
      [[ -z "${hostname+x}" ]] && echo 'no leak' || echo "leaked: $hostname"
    }

    When call leak_check
    The output should eq 'no leak'
  End
End

Describe 'node_service_running'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when service is active' do
    node_ssh() { echo 'active'; }

    When call node_service_running 'pve1' 'pve-ha-lrm'
    The status should be success
  End

  It 'returns failure when service is not active' do
    node_ssh() { echo 'inactive'; }

    When call node_service_running 'pve1' 'pve-ha-lrm'
    The status should be failure
  End
End

Describe 'node_not_running_task'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when no tasks running' do
    node_number_of_running_tasks() { echo '0'; }

    When call node_not_running_task 'pve1'
    The status should be success
  End

  It 'returns failure when tasks are running' do
    verbose=1
    node_number_of_running_tasks() { echo '3'; }

    When call node_not_running_task 'pve1'
    The status should be failure
    The error should include 'Running a task'
  End

  It 'returns failure (not 0) when task count is a multiple of 256' do
    # Old `return $task_count` wrapped mod-256, so 256 active tasks reported
    # success — i.e. "no tasks running" — to the caller.
    verbose=1
    node_number_of_running_tasks() { echo '256'; }

    When call node_not_running_task 'pve1'
    The status should be failure
    The error should include 'Running a task'
  End
End

Describe 'node_has_updates'
  Include proxmox-upgrade-cluster.sh

  It 'returns success and logs "Updates available." when updates are available' do
    node_ssh() { echo 'Installs: 5'; }

    When call node_has_updates 'pve1'
    The status should be success
    The error should include 'Updates available.'
  End

  It 'returns failure and logs "No updates available." when none' do
    node_ssh() { echo ''; }

    When call node_has_updates 'pve1'
    The status should be failure
    The error should include 'No updates available.'
  End

  It 'does not leak $updates into the caller scope' do
    node_ssh() { echo 'Installs: 5'; }
    leak_check() {
      unset updates
      node_has_updates 'pve1' >/dev/null 2>&1
      [[ -z "${updates+x}" ]] && echo 'no leak' || echo "leaked: $updates"
    }

    When call leak_check
    The output should eq 'no leak'
  End
End

Describe 'node_upgrade'
  Include proxmox-upgrade-cluster.sh

  It 'calls node_ssh_no_op with dist-upgrade command' do
    Mock node_ssh
      echo 'upgraded'
    End

    When call node_upgrade 'pve1'
    The error should include 'upgraded'
  End

  It 'skips apt dist-upgrade and returns 0 when reboot_only=true' do
    reboot_only=true
    node_ssh_no_op() { echo 'ssh_no_op-called' >&2; }

    When call node_upgrade 'pve1'
    The status should be success
    The error should include 'Skipping apt dist-upgrade (--reboot-only)'
    The error should not include 'ssh_no_op-called'
  End
End

Describe 'node_apt_update'
  Include proxmox-upgrade-cluster.sh

  It 'calls node_ssh with apt-get update' do
    verbose=1
    Mock node_ssh
      echo 'updated'
    End

    When call node_apt_update 'pve1'
    The error should include 'updated'
  End
End

Describe 'node_pvesh'
  Include proxmox-upgrade-cluster.sh

  It 'calls node_ssh with pvesh command' do
    Mock node_ssh
      echo '{"type":"node","name":"pve1"}'
    End

    When call node_pvesh 'pve1' 'cluster/status'
    The output should include '{"type":"node","name":"pve1"}'
  End
End

Describe 'node_ssh_no_op'
  Include proxmox-upgrade-cluster.sh

  It 'runs command when dry_run is false' do
    Mock node_ssh
      echo 'executed'
    End
    dry_run=false

    When call node_ssh_no_op 'pve1' 'whoami'
    The output should include 'executed'
  End

  It 'skips command when dry_run is true' do
    dry_run=true

    When call node_ssh_no_op 'pve1' 'whoami'
    The status should be success
    The output should eq ''
    The error should include 'NO-OP'
  End
End

# Build a node_pvesh mock that returns a JSON array of guest entries with
# the given status values. Usage:
#
#   make_status_array_pvesh running stopped running   # 3-element array
#   make_status_array_pvesh                            # empty array
#
# Same global-closure pattern as make_manager_status_pvesh.
make_status_array_pvesh() {
  local entries=()
  local s
  for s in "$@"; do entries+=("{\"status\":\"$s\"}"); done
  _status_array_json="[$(IFS=,; echo "${entries[*]}")]"
  node_pvesh() { echo "$_status_array_json"; }
}

Describe 'node_get_running_count' do
  Include proxmox-upgrade-cluster.sh

  It 'returns count of running lxc containers excluding stopped' do
    make_status_array_pvesh running stopped
    When call node_get_running_count 'pve1' 'lxc'
    The output should eq '1'
  End

  It 'returns count of running qemu guests excluding stopped' do
    make_status_array_pvesh running stopped running
    When call node_get_running_count 'pve1' 'qemu'
    The output should eq '2'
  End

  It 'returns 0 when no containers' do
    make_status_array_pvesh
    When call node_get_running_count 'pve1' 'lxc'
    The output should eq '0'
  End

  It 'returns 0 when no guests' do
    make_status_array_pvesh
    When call node_get_running_count 'pve1' 'qemu'
    The output should eq '0'
  End

  It 'logs the LXC count uppercased at verbose>=2' do
    verbose=2
    make_status_array_pvesh running running
    When call node_get_running_count 'pve1' 'lxc'
    The output should eq '2'
    The error should include 'Running LXC count: 2'
  End

  It 'logs the QEMU count uppercased at verbose>=2' do
    verbose=2
    make_status_array_pvesh running
    When call node_get_running_count 'pve1' 'qemu'
    The output should eq '1'
    The error should include 'Running QEMU count: 1'
  End
End

Describe 'node_needs_reboot'
  Include proxmox-upgrade-cluster.sh

  # These kernel-detection tests are about the success/failure result, not
  # the log line. verbose=-1 suppresses the level-0 "Reboot required." /
  # "No reboot required." output (asserted separately in 'pass/fail logging'
  # below) so it doesn't trip the stray-stderr warning.
  Before 'verbose=-1'

  # Helpers install a `node_ssh` mock parameterised on running kernel + the
  # remote `proxmox-boot-tool kernel list` / grub.cfg output. Globals are
  # used (not function-local) because function definitions in bash don't
  # form closures — the inner function reads the variables at call time,
  # not at definition time, so they need to live at script-wide scope.

  make_pbt_node_ssh() {
    # $1 = uname -r, $@ = lines of `proxmox-boot-tool kernel list` output.
    _pbt_uname=$1; shift
    _pbt_kernel_list=$(printf '%s\n' "$@")
    node_ssh() {
      case "$2" in
        'uname -r') echo "$_pbt_uname" ;;
        'hash proxmox-boot-tool') return 0 ;;
        'proxmox-boot-tool kernel list') printf '%s\n' "$_pbt_kernel_list" ;;
      esac
    }
  }

  make_grub_node_ssh() {
    # $1 = uname -r, $@ = lines emitted by `grep vmlinuz /boot/grub/grub.cfg`.
    _grub_uname=$1; shift
    _grub_lines=$(printf '%s\n' "$@")
    node_ssh() {
      case "$2" in
        'uname -r') echo "$_grub_uname" ;;
        'hash proxmox-boot-tool') return 1 ;;
        *grep*) printf '%s\n' "$_grub_lines" ;;
      esac
    }
  }

  Describe 'proxmox-boot-tool branch' do
    It 'returns failure when running kernel matches the latest auto kernel' do
      make_pbt_node_ssh '7.0.2-3-pve' \
        'Manually selected kernels:' 'None.' '' \
        'Automatically selected kernels:' '6.17.13-8-pve' '7.0.2-2-pve' '7.0.2-3-pve'
      When call node_needs_reboot 'pve1'
      The status should be failure
    End

    It 'returns success when running kernel is older than the latest auto kernel' do
      make_pbt_node_ssh '7.0.2-2-pve' \
        'Manually selected kernels:' 'None.' '' \
        'Automatically selected kernels:' '7.0.2-2-pve' '7.0.2-3-pve'
      When call node_needs_reboot 'pve1'
      The status should be success
    End

    It 'honors a manually pinned kernel even when a higher auto kernel exists' do
      # Pinned to an older kernel; running it = no reboot needed.
      make_pbt_node_ssh '6.17.13-8-pve' \
        'Manually selected kernels:' '6.17.13-8-pve' '' \
        'Automatically selected kernels:' '6.17.13-8-pve' '7.0.2-3-pve'
      When call node_needs_reboot 'pve1'
      The status should be failure
    End

    It 'returns success when pinned kernel differs from running kernel' do
      make_pbt_node_ssh '7.0.2-3-pve' \
        'Manually selected kernels:' '6.17.13-8-pve' '' \
        'Automatically selected kernels:' '6.17.13-8-pve' '7.0.2-3-pve'
      When call node_needs_reboot 'pve1'
      The status should be success
    End

    It 'picks the highest auto kernel even when the list is unsorted' do
      make_pbt_node_ssh '7.0.2-3-pve' \
        'Manually selected kernels:' 'None.' '' \
        'Automatically selected kernels:' '7.0.2-3-pve' '6.17.13-8-pve' '7.0.2-2-pve'
      When call node_needs_reboot 'pve1'
      The status should be failure
    End

    It 'parses indented kernel entries (auto list)' do
      make_pbt_node_ssh '7.0.2-3-pve' \
        'Manually selected kernels:' 'None.' '' \
        'Automatically selected kernels:' '        6.17.13-8-pve' '        7.0.2-2-pve' '        7.0.2-3-pve'
      When call node_needs_reboot 'pve1'
      The status should be failure
    End

    It 'parses indented kernel entries (manual pin)' do
      make_pbt_node_ssh '6.17.13-8-pve' \
        'Manually selected kernels:' '        6.17.13-8-pve' '' \
        'Automatically selected kernels:' '        6.17.13-8-pve' '        7.0.2-3-pve'
      When call node_needs_reboot 'pve1'
      The status should be failure
    End

    It 'reports needs-reboot when both kernel sections are effectively empty' do
      # ESP not configured or pbt brand-new; awk parser finds no kernel
      # entries and expected_kernel becomes empty. "" != "<running>" so
      # the function says "needs reboot" — conservative and the right
      # default (we can't prove the running kernel matches the target).
      make_pbt_node_ssh '7.0.2-3-pve' \
        'Manually selected kernels:' 'None.' '' \
        'Automatically selected kernels:' 'None.'
      When call node_needs_reboot 'pve1'
      The status should be success
    End
  End

  Describe 'grub.cfg fallback (no proxmox-boot-tool)' do
    It 'returns success when kernels differ' do
      make_grub_node_ssh '6.1.0-pve' \
        'linux   /boot/vmlinuz-6.2.0-pve root=...'
      When call node_needs_reboot 'pve1'
      The status should be success
    End

    It 'returns failure when kernels match' do
      make_grub_node_ssh '6.2.0-pve' \
        'linux   /boot/vmlinuz-6.2.0-pve root=...'
      When call node_needs_reboot 'pve1'
      The status should be failure
    End

    It 'picks the first vmlinuz line when grub.cfg has multiple entries' do
      # The script uses `head -1` on the grep output, so only the first
      # vmlinuz line is consulted. Running kernel matching the first → no
      # reboot needed even though older kernels also appear later in the
      # file.
      make_grub_node_ssh '6.2.0-pve' \
        'linux   /boot/vmlinuz-6.2.0-pve root=...' \
        'linux   /boot/vmlinuz-6.1.0-pve root=...' \
        'linux   /boot/vmlinuz-6.0.0-pve root=...'
      When call node_needs_reboot 'pve1'
      The status should be failure
    End
  End

  Describe 'pass/fail logging' do
    It 'logs "Reboot required." when the kernel changed' do
      verbose=0  # override the block-level Before 'verbose=-1'
      make_pbt_node_ssh '7.0.2-2-pve' \
        'Manually selected kernels:' 'None.' '' \
        'Automatically selected kernels:' '7.0.2-2-pve' '7.0.2-3-pve'
      When call node_needs_reboot 'pve1'
      The status should be success
      The error should include 'Reboot required.'
    End

    It 'logs "No reboot required." when the kernel is current' do
      verbose=0  # override the block-level Before 'verbose=-1'
      make_pbt_node_ssh '7.0.2-3-pve' \
        'Manually selected kernels:' 'None.' '' \
        'Automatically selected kernels:' '7.0.2-2-pve' '7.0.2-3-pve'
      When call node_needs_reboot 'pve1'
      The status should be failure
      The error should include 'No reboot required.'
    End
  End
End

Describe 'node_reached_mode'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when already in target mode' do
    node_get_mode() { echo 'online'; }

    When call node_reached_mode 'pve1' 'online'
    The status should be success
  End

  It 'logs current vs target and returns failure when not yet in target mode' do
    verbose=1
    node_get_mode() { echo 'maintenance'; }

    When call node_reached_mode 'pve1' 'online'
    The status should be failure
    The error should include "Current mode 'maintenance' target mode 'online'"
  End

  It 'does not leak $mode into the caller scope' do
    node_get_mode() { echo 'online'; }
    leak_check() {
      unset mode
      node_reached_mode 'pve1' 'online' 2>/dev/null
      [[ -z "${mode+x}" ]] && echo 'no leak' || echo "leaked: $mode"
    }

    When call leak_check
    The output should eq 'no leak'
  End
End

Describe 'is_node_up'
  Include proxmox-upgrade-cluster.sh

  Before 'verbose=3'

  It 'returns success when node is up' do
    Mock node_ssh
      echo 'root'
    End

    When call is_node_up 'pve1'
    The status should be success
    The error should include 'Node is up'
  End

  It 'returns failure when node is down' do
    Mock node_ssh
      exit 1
    End

    When call is_node_up 'pve1'
    The status should be failure
    The error should include 'Node is down'
  End

  It 'passes default timeout of 5 seconds when none provided' do
    node_ssh() { echo "args: $*"; }

    When call is_node_up 'pve1'
    The error should include '-oConnectTimeout=5'
  End

  It 'passes the custom timeout when provided as second arg' do
    node_ssh() { echo "args: $*"; }

    When call is_node_up 'pve1' '10'
    The error should include '-oConnectTimeout=10'
  End
End

Describe 'is_node_proxmox'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when pvesh is available' do
    Mock node_ssh
      exit 0
    End

    When call is_node_proxmox 'pve1'
    The status should be success
  End

  It 'returns failure when pvesh is not available' do
    verbose=1
    Mock node_ssh
      exit 1
    End

    When call is_node_proxmox 'pve1'
    The status should be failure
    The error should include 'Node is not proxmox'
  End
End

Describe 'local_ssh'
  Include proxmox-upgrade-cluster.sh

  It 'passes all arguments to ssh command' do
    Mock local_ssh
      echo "ssh: $@"
    End

    When call local_ssh '-o StrictHostKeyChecking=no' 'pve1' 'whoami'
    The output should include 'ssh:'
    The output should include '-o StrictHostKeyChecking=no'
  End
End

Describe 'node_ssh'
  Include proxmox-upgrade-cluster.sh

  It 'logs debug message with host and command' do
    verbose=2
    Mock local_ssh
      echo 'command executed'
    End

    When call node_ssh 'pve1' 'uptime'
    The output should include 'command executed'
    The error should include '[pve1]'
    The error should include "Running command 'uptime'"
  End

  It 'passes arguments to local_ssh with ssh_options expansion' do
    verbose=2
    Mock local_ssh
      echo "args: $@"
    End
    ssh_options=('-o StrictHostKeyChecking=no')

    When call node_ssh 'pve1' 'whoami'
    The output should include 'args:'
    The error should include '[pve1]'
  End
End

# node_pre_upgrade was deleted in favour of inlining its three steps (the
# offline pre-flight wait, node_wait_all_tasks_completed, and
# node_wait_until_no_running_guests) into node_run_update_sequence.
# Each sub-step still has its own Describe block (see this file and
# spec/upgrade_sequence_spec.sh).
