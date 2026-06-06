Describe 'node_set_maintenance'
  Include proxmox-upgrade-cluster.sh

  Before 'verbose=1'

  It 'skips and warns when use_maintenance_mode is false (enable)' do
    use_maintenance_mode=false
    node_ssh_no_op() { echo 'skipped'; }
    When call node_set_maintenance 'pve1' enable
    The status should be success
    The error should include 'Not setting maintenance mode'
  End

  It 'enables maintenance and waits for maintenance mode' do
    use_maintenance_mode=true
    dry_run=false
    node_ssh_no_op() { echo 'maintenance set'; }
    # Not in target on the first poll, reached on the second, so the wait logs
    # one iteration rather than taking the early silent exit. The predicate is
    # called directly (not via command substitution), so a counter persists.
    _reached_polls=0
    node_reached_mode() {
      _reached_polls=$((_reached_polls + 1))
      [[ $_reached_polls -ge 2 ]]
    }
    wait_sleep() { :; }

    When call node_set_maintenance 'pve1' enable
    The status should be success
    The error should include 'Enabling maintenance mode'
    The error should include 'Waiting until node enters maintenance mode'
    The error should include "Reached target mode 'maintenance'"
  End

  It 'skips the mode wait when dry_run is true (enable)' do
    use_maintenance_mode=true
    dry_run=true
    node_ssh_no_op() { echo 'maintenance set'; }
    node_get_mode() { echo 'maintenance'; }  # if wrongly polled, completes fast
    wait_sleep() { :; }

    When call node_set_maintenance 'pve1' enable
    The status should be success
    The error should include 'Enabling maintenance mode'
    The error should not include 'Waiting until node enters'
  End

  It 'skips and warns when use_maintenance_mode is false (disable)' do
    use_maintenance_mode=false

    When call node_set_maintenance 'pve1' disable
    The status should be success
    The error should include 'Not setting maintenance mode'
  End

  It 'disables maintenance: brings up service, runs ssh, then waits for online mode' do
    use_maintenance_mode=true
    dry_run=false
    node_service_running() { return 0; }  # HA LRM already up -> silent service wait
    node_ssh_no_op() { echo 'maintenance disabled'; }
    _reached_polls=0
    node_reached_mode() {
      _reached_polls=$((_reached_polls + 1))
      [[ $_reached_polls -ge 2 ]]
    }
    wait_sleep() { :; }

    When call node_set_maintenance 'pve1' disable
    The status should be success
    The error should include 'maintenance disabled'
    The error should include 'Disabling maintenance mode'
    The error should include "Reached target mode 'online'"
  End

  It 'skips the mode wait when dry_run is true (disable)' do
    use_maintenance_mode=true
    dry_run=true
    node_service_running() { return 0; }  # HA LRM already up -> silent service wait
    node_ssh_no_op() { echo 'maintenance disabled'; }
    wait_sleep() { :; }

    When call node_set_maintenance 'pve1' disable
    The status should be success
    The error should include 'maintenance disabled'
    The error should include 'Disabling maintenance mode'
    The error should not include 'Waiting until node enters'
  End
End

Describe 'node_reboot'
  Include proxmox-upgrade-cluster.sh

  # File-scope helper: install the stubs needed to exercise the "real
  # reboot" code path without actually sleeping or ssh-ing. Each It-block
  # calls this and overrides only what differs.
  #
  # Defaults:
  #   verbose=1 (so log lines appear in stderr)
  #   force_reboot=false, skip_reboot=false, dry_run=false
  #   node_needs_reboot returns 1 (no reboot needed)
  #   is_node_up returns 0 (comes back immediately)
  #   wait_sleep and node_ssh_no_op are no-ops
  #   reboot_timeout retains its script default (900s)
  install_reboot_stubs() {
    verbose=1
    force_reboot=false
    skip_reboot=false
    dry_run=false
    node_needs_reboot() { return 1; }
    wait_sleep() { :; }
    node_ssh_no_op() { :; }
    is_node_up() { return 0; }
  }

  It 'returns early with success when no reboot is needed' do
    install_reboot_stubs
    When call node_reboot 'pve1'
    The status should be success
    The error should include "Doesn't need to be rebooted"
  End

  It 'reboots when force_reboot is true' do
    install_reboot_stubs
    force_reboot=true
    When call node_reboot 'pve1'
    The status should be success
    The error should include 'Forcing Reboot'
    The error should include 'Rebooting in 5 seconds'
    The error should include 'for node to come back up'
    The error should include 'Rebooted successfully'
  End

  It 'reports how long the reboot took on success' do
    install_reboot_stubs
    force_reboot=true
    When call node_reboot 'pve1'
    The status should be success
    The error should match pattern '*Rebooted successfully in [0-9]*s.*'
  End

  It 'reboots when node_needs_reboot is true and force_reboot is false' do
    install_reboot_stubs
    node_needs_reboot() { return 0; }
    When call node_reboot 'pve1'
    The status should be success
    The error should include "Needs to be rebooted"
    The error should include 'Rebooting in 5 seconds'
    The error should include 'for node to come back up'
    The error should include 'Rebooted successfully'
  End

  It 'skips reboot when dry_run is true and needs reboot' do
    install_reboot_stubs
    dry_run=true
    node_needs_reboot() { return 0; }
    When call node_reboot 'pve1'
    The status should be success
    The error should include "Needs to be rebooted"
    The error should include 'Not rebooting'
  End

  It 'skips reboot when dry_run is true even with force_reboot' do
    install_reboot_stubs
    dry_run=true
    force_reboot=true
    When call node_reboot 'pve1'
    The status should be success
    The error should include 'Forcing Reboot'
    The error should include 'Not rebooting'
    The error should not include 'Rebooting in 5 seconds'
  End

  It 'skips reboot when --skip-reboot is set and the kernel did not change' do
    install_reboot_stubs
    skip_reboot=true
    # Sentinels: if any of these run we have a regression.
    wait_sleep() { echo 'wait_sleep called' >&2; }
    node_ssh_no_op() { echo 'ssh_no_op called' >&2; }
    is_node_up() { echo 'is_node_up called' >&2; return 0; }

    When call node_reboot 'pve1'
    The status should be success
    The error should include 'Skipping reboot per --skip-reboot.'
    The error should not include 'WILL need a reboot'
    The error should not include 'wait_sleep called'
    The error should not include 'ssh_no_op called'
    The error should not include 'is_node_up called'
  End

  It 'skips reboot with a stronger warning when a kernel update is staged' do
    install_reboot_stubs
    skip_reboot=true
    node_needs_reboot() { return 0; }   # kernel did change

    When call node_reboot 'pve1'
    The status should be success
    The error should include 'Skipping reboot per --skip-reboot.'
    The error should include 'WILL need a reboot to pick up the new kernel'
  End

  It 'lets --skip-reboot win over --force-reboot (defense in depth)' do
    # CLI mutex prevents both being set simultaneously; this asserts the
    # in-function precedence (skip-reboot is checked first) in case the
    # mutex check is ever removed or bypassed.
    install_reboot_stubs
    skip_reboot=true
    force_reboot=true
    When call node_reboot 'pve1'
    The status should be success
    The error should include 'Skipping reboot per --skip-reboot.'
    The error should not include 'Forcing Reboot'
  End

  It 'issues reboot and follows dmesg over a single ssh session with keepalive opts' do
    install_reboot_stubs
    force_reboot=true
    verbose=1
    # node_ssh_no_op's stdout gets piped through log_pipe_level → stderr.
    node_ssh_no_op() {
      local node=$1; shift
      local cmd=$1; shift
      echo "ssh($node, $cmd, $*)"
    }

    When call node_reboot 'pve1'
    The status should be success
    # One combined invocation, not two — avoids the second-connection race that
    # lost the shutdown dmesg.
    The error should include 'ssh(pve1, reboot; exec dmesg -W, -oConnectTimeout=10 -oServerAliveInterval=5 -oServerAliveCountMax=2)'
  End

  It 'aborts with a timeout error when the node does not come back up' do
    install_reboot_stubs
    force_reboot=true
    reboot_timeout=0
    is_node_up() { return 1; }

    When run node_reboot 'pve1'
    The status should be failure
    The error should include 'Timed out after 0s'
    The error should include "'pve1'"
    The error should not include 'Rebooted successfully'
  End
End

Describe 'node_post_upgrade'
  Include proxmox-upgrade-cluster.sh

  # Exiting maintenance was lifted out of node_post_upgrade into
  # node_run_update_sequence (now a direct node_set_maintenance disable
  # call) so per-step early-returns don't strand a node in maintenance.
  # These tests cover just the apt-cleanup work that remains.

  It 'logs the no-reinstall path when pkgs_reinstall is empty' do
    pkgs_reinstall=()
    node_ssh_no_op() { :; }

    When call node_post_upgrade 'pve1'
    The error should include "No packages to force reinstall"
    The error should include 'Removing old packages'
  End

  It 'reinstalls packages when pkgs_reinstall is set' do
    pkgs_reinstall=("pve-firmware")
    node_ssh_no_op() { echo 'reinstalled'; }

    When call node_post_upgrade 'pve1'
    The error should include "Force reinstalling"
    The error should include 'Removing old packages'
  End

  It 'skips all apt cleanup and returns 0 when reboot_only=true' do
    reboot_only=true
    pkgs_reinstall=("pve-firmware")
    node_ssh_no_op() { echo 'ssh_no_op-called' >&2; }

    When call node_post_upgrade 'pve1'
    The status should be success
    The error should include 'Skipping apt cleanup (--reboot-only)'
    The error should not include 'ssh_no_op-called'
    The error should not include 'Force reinstalling'
    The error should not include 'Removing old packages'
  End
End

Describe 'node_run_update_sequence'
  Include proxmox-upgrade-cluster.sh
  # The trap fires via errexit propagation; tests must run with set -e on.
  Set errexit:on

  # Install no-op stubs for every step the orchestrator now calls. The
  # maintenance enter/exit calls and the pre-flight check were lifted out
  # of node_pre_upgrade/node_post_upgrade so node_run_update_sequence is
  # the canonical view of the lifecycle. Each It overrides whichever
  # stub(s) it wants to fail or trace. Mirrors install_main_happy_path_stubs.
  install_update_sequence_happy_stubs() {
    # The inlined pre-flight is the only node_wait_with_progress call here
    # (node_set_maintenance and the wait helpers are stubbed below).
    node_wait_with_progress()           { :; }
    node_set_maintenance()              { :; }
    node_wait_all_tasks_completed()     { :; }
    node_wait_until_no_running_guests() { :; }
    node_upgrade()                      { :; }
    node_reboot()                       { :; }
    node_post_upgrade()                 { :; }
  }

  It 'runs all upgrade steps on the success path without warning' do
    install_update_sequence_happy_stubs

    When call node_run_update_sequence 'pve1'
    The status should be success
    The error should include 'Starting upgrade'
    The error should include 'Successfully upgraded'
    The error should not include 'may still be in maintenance'
  End

  It 'enters maintenance before the work and exits maintenance after' do
    # Pin the lifecycle order: pre-flight → enter → upgrade → reboot →
    # post → exit. Use a single shared invocation log so we can assert
    # the relative ordering.
    invocations="$(mktemp)"
    # The inlined pre-flight is the only node_wait_with_progress call here.
    node_wait_with_progress()           { echo 'pre_flight' >> "$invocations"; }
    node_set_maintenance()              { echo "maintenance:$2" >> "$invocations"; }
    node_wait_all_tasks_completed()     { :; }
    node_wait_until_no_running_guests() { :; }
    node_upgrade()                      { echo 'upgrade' >> "$invocations"; }
    node_reboot()                       { echo 'reboot' >> "$invocations"; }
    node_post_upgrade()                 { echo 'post_upgrade' >> "$invocations"; }

    When call node_run_update_sequence 'pve1'
    The status should be success
    The error should include 'Starting upgrade'
    The error should include 'Successfully upgraded'
    The line 1 of contents of file "$invocations" should eq 'pre_flight'
    The line 2 of contents of file "$invocations" should eq 'maintenance:enable'
    The line 3 of contents of file "$invocations" should eq 'upgrade'
    The line 4 of contents of file "$invocations" should eq 'reboot'
    The line 5 of contents of file "$invocations" should eq 'post_upgrade'
    The line 6 of contents of file "$invocations" should eq 'maintenance:disable'
    rm -f "$invocations"
  End

  It 'warns about maintenance and does NOT auto-recover when node_upgrade fails' do
    install_update_sequence_happy_stubs
    use_maintenance_mode=true
    node_upgrade() { return 1; }
    node_reboot() { echo 'should not reach reboot' >&2; }
    node_post_upgrade() { echo 'should not reach post' >&2; }
    node_set_maintenance() { [[ "$2" == disable ]] && echo 'auto-recovery ran (BAD)' >&2; return 0; }

    When run node_run_update_sequence 'pve1'
    The status should be failure
    The error should include 'may still be in maintenance mode'
    The error should include 'ha-manager crm-command node-maintenance disable'
    The error should not include 'should not reach'
    The error should not include 'auto-recovery ran'
  End

  It 'fires the trap when entering maintenance fails' do
    install_update_sequence_happy_stubs
    use_maintenance_mode=true
    node_set_maintenance() { [[ "$2" == enable ]] && return 1; return 0; }
    node_upgrade() { echo 'should not reach upgrade' >&2; }
    node_reboot() { echo 'should not reach reboot' >&2; }
    node_post_upgrade() { echo 'should not reach post' >&2; }

    When run node_run_update_sequence 'pveX'
    The status should be failure
    The error should include 'may still be in maintenance mode'
    The error should not include 'should not reach'
  End

  It 'fires the trap when exiting maintenance fails' do
    install_update_sequence_happy_stubs
    use_maintenance_mode=true
    node_set_maintenance() { [[ "$2" == disable ]] && return 1; return 0; }

    When run node_run_update_sequence 'pveW'
    The status should be failure
    The error should include 'may still be in maintenance mode'
  End

  It 'fires the trap when node_reboot fails (post_upgrade never exits maintenance)' do
    install_update_sequence_happy_stubs
    use_maintenance_mode=true
    node_reboot() { return 1; }
    node_post_upgrade() { echo 'should not reach post' >&2; }

    When run node_run_update_sequence 'pveY'
    The status should be failure
    The error should include 'may still be in maintenance mode'
    The error should not include 'should not reach'
  End

  It 'fires the trap when node_post_upgrade fails (before maintenance can be exited)' do
    install_update_sequence_happy_stubs
    use_maintenance_mode=true
    node_post_upgrade() { return 1; }
    # If post_upgrade fails, the orchestrator never exits maintenance (disable).
    node_set_maintenance() { [[ "$2" == disable ]] && echo 'should not reach exit_maintenance' >&2; return 0; }

    When run node_run_update_sequence 'pveZ'
    The status should be failure
    The error should include 'may still be in maintenance mode'
    The error should not include 'should not reach exit_maintenance'
  End

  It 'cites the active node by name in the maintenance warning' do
    # Regression for trap stale-capture: the trap installed inside
    # node_run_update_sequence captures $node by value at install-time
    # (interpolated into the trap body). Verify with a non-default node
    # name; the log_prefix tags the warning with [<node>].
    install_update_sequence_happy_stubs
    use_maintenance_mode=true
    node_upgrade() { return 1; }

    When run node_run_update_sequence 'pveXYZ'
    The status should be failure
    The error should include '[pveXYZ]'
    The error should include 'may still be in maintenance mode'
  End

  It 'does not warn when use_maintenance_mode is false even on failure' do
    install_update_sequence_happy_stubs
    use_maintenance_mode=false
    node_upgrade() { return 1; }

    When run node_run_update_sequence 'pve1'
    The status should be failure
    The error should not include 'may still be in maintenance'
  End

  It 'clears the ERR trap on success so it does not leak across nodes' do
    install_update_sequence_happy_stubs

    check_trap() {
      node_run_update_sequence 'pve1' >/dev/null 2>&1
      trap -p ERR
    }

    When call check_trap
    The output should eq ''
  End

  It 'does not enable errtrace during the upgrade sequence' do
    # Regression for the smoke-test bug: with `set -E` (errtrace) the ERR trap
    # was inherited into process substitutions inside node_pvesh, and benign
    # internal non-zero exits fired the maintenance warning even though the
    # parent flow succeeded. Assert errtrace stays off — that's the contract
    # the trap design relies on.
    install_update_sequence_happy_stubs
    node_upgrade() {
      [[ $- == *E* ]] && echo "ERRTRACE-LEAKED" >&2
    }

    When call node_run_update_sequence 'pve1'
    The status should be success
    The error should not include 'ERRTRACE-LEAKED'
    The error should not include 'may still be in maintenance'
  End
End

Describe 'node_wait_until_no_running_guests'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when allow_running_guests is true' do
    allow_running_guests=true
    node_get_running_guest_count() { echo '5'; }
    wait_sleep() { return 0; }

    When call node_wait_until_no_running_guests 'pve1'
    The status should be success
    The error should include "Not checking for running guests"
  End

  It 'returns success silently when no guests are running' do
    allow_running_guests=false
    node_get_running_guest_count() { echo '0'; }
    wait_sleep() { return 0; }

    When call node_wait_until_no_running_guests 'pve1'
    The status should be success
    The error should not include "Waiting until all guests are migrated"
    The error should not include "Reached zero running guests"
  End
End

Describe 'node_wait_all_tasks_completed'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when allow_running_tasks is true' do
    allow_running_tasks=true
    node_number_of_running_tasks() { echo '5'; }
    wait_sleep() { return 0; }

    When call node_wait_all_tasks_completed 'pve1'
    The status should be success
    The error should include "Not checking for running tasks"
  End

  It 'returns success silently when no tasks are running' do
    allow_running_tasks=false
    node_number_of_running_tasks() { echo '0'; }
    wait_sleep() { return 0; }

    When call node_wait_all_tasks_completed 'pve1'
    The status should be success
    The error should not include "Waiting until all cluster tasks have completed"
    The error should not include "Cluster reached zero running tasks"
  End
End

Describe 'node_cluster_all_online'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when no cluster node is offline' do
    node_get_offline_count() { echo '0'; }

    When call node_cluster_all_online 'pve1'
    The status should be success
  End

  It 'logs a waiting notice and returns failure when a node is offline' do
    verbose=1
    node_get_offline_count() { echo '1'; }

    When call node_cluster_all_online 'pve1'
    The status should be failure
    The error should include 'At least one cluster node is currently offline'
  End

  # The pre-flight status/success wording lives at the run_update_sequence call
  # site; with every node already online there is nothing to wait for, so the
  # wait takes the early silent exit.
  It 'pre-flight wait exits silently when the cluster is already online' do
    node_get_offline_count() { echo '0'; }
    wait_sleep() { :; }

    When call node_wait_with_progress 'pve1' 1s \
      "Checking that no cluster nodes are currently offline..." \
      "All cluster nodes are online." \
      node_cluster_all_online 'pve1'
    The status should be success
    The error should not include "Checking that no cluster nodes are currently offline"
    The error should not include "All cluster nodes are online"
  End
End

Describe 'node_wait_with_progress'
  Include proxmox-upgrade-cluster.sh

  It 'exits early without logging when the predicate is already satisfied' do
    verbose=1
    already_done() { return 0; }
    wait_sleep() { echo 'SLEPT' >&2; }  # sentinel: must not be called

    When call node_wait_with_progress 'pve1' 1s 'Waiting for thing...' 'Thing ready.' already_done
    The status should be success
    The error should not include 'Waiting for thing...'
    The error should not include 'Thing ready.'
    The error should not include 'SLEPT'
  End

  It 'polls with progress until the predicate succeeds' do
    verbose=1
    _counter=$(mktemp)
    echo 0 > "$_counter"
    # Done once the counter reaches 2; wait_sleep advances it each iteration.
    counter_reaches_two() { [[ "$(cat "$_counter")" -ge 2 ]]; }
    wait_sleep() { echo $(($(cat "$_counter") + 1)) > "$_counter"; }

    When call node_wait_with_progress 'pve1' 1s 'Waiting...' 'Done.' counter_reaches_two
    The status should be success
    The error should include 'Done.'
    The contents of file "$_counter" should eq '2'
    rm -f "$_counter"
  End
End

# filter_nodes writes the kept nodes into a caller-named array (no stdout), so
# a When-call test can't read it across the subshell. This driver runs it into
# a local array and prints that array one node per line for the matchers.
filter_into() {
  local -a kept=()
  filter_nodes "$1" "$2" "$3" kept
  [[ ${#kept[@]} -gt 0 ]] && printf '%s\n' "${kept[@]}"
  return 0
}

Describe 'filter_nodes (upgradeable: node_has_updates)'
  Include proxmox-upgrade-cluster.sh

  # node_has_updates is stubbed here, so its own "Updates available." /
  # "No updates available." logging (covered in node_functions_spec.sh) does
  # not appear — these tests assert only the filter's emission + the
  # "Removed from upgrade sequence." line.

  It 'emits nodes that have updates, one per line, in input order' do
    Mock node_has_updates
      exit 0
    End
    cluster_nodes=("pve1" "pve2")

    When call filter_into node_has_updates cluster_nodes "Removed from upgrade sequence."
    The line 1 of output should eq 'pve1'
    The line 2 of output should eq 'pve2'
    The lines of output should eq 2
  End

  It 'excludes nodes without updates and logs them removed at verbose>=1' do
    verbose=1
    # Inline override — Mock's subshell would lose the persistent counter.
    node_has_updates() { [[ "$1" == 'pve1' ]]; }
    cluster_nodes=("pve1" "pve2")

    When call filter_into node_has_updates cluster_nodes "Removed from upgrade sequence."
    The output should eq 'pve1'
    The lines of output should eq 1
    The error should include 'Removed from upgrade sequence'
  End

  It 'returns empty output when called with empty array' do
    Mock node_has_updates
      exit 0
    End
    cluster_nodes=()

    When call filter_into node_has_updates cluster_nodes "Removed from upgrade sequence."
    The output should eq ''
  End

  It 'returns empty output when no nodes have updates' do
    Mock node_has_updates
      exit 1
    End
    cluster_nodes=("pve1" "pve2")

    When call filter_into node_has_updates cluster_nodes "Removed from upgrade sequence."
    The output should eq ''
  End
End

Describe 'filter_nodes (reboot: node_needs_reboot)'
  Include proxmox-upgrade-cluster.sh

  # node_needs_reboot is stubbed here, so its own kernel debug logging
  # (covered in node_functions_spec.sh) does not appear — these tests assert
  # the filter's emission/order + the "Removed from reboot sequence." line.

  It 'emits nodes that need a reboot, one per line, in input order' do
    node_needs_reboot() {
      case "$1" in
        pveA) return 1 ;;
        pveB) return 0 ;;
        pveC) return 0 ;;
      esac
    }
    cluster_nodes=("pveA" "pveB" "pveC")

    When call filter_into node_needs_reboot cluster_nodes "Removed from reboot sequence."
    The line 1 of output should eq 'pveB'
    The line 2 of output should eq 'pveC'
    The lines of output should eq 2
  End

  It 'emits all nodes when every node needs a reboot' do
    Mock node_needs_reboot
      exit 0
    End
    cluster_nodes=("pve1" "pve2" "pve3")

    When call filter_into node_needs_reboot cluster_nodes "Removed from reboot sequence."
    The line 1 of output should eq 'pve1'
    The line 2 of output should eq 'pve2'
    The line 3 of output should eq 'pve3'
    The lines of output should eq 3
  End

  It 'returns empty output when no nodes need a reboot' do
    Mock node_needs_reboot
      exit 1
    End
    cluster_nodes=("pve1" "pve2")

    When call filter_into node_needs_reboot cluster_nodes "Removed from reboot sequence."
    The output should eq ''
  End

  It 'returns empty output when called with an empty array' do
    Mock node_needs_reboot
      exit 0
    End
    cluster_nodes=()

    When call filter_into node_needs_reboot cluster_nodes "Removed from reboot sequence."
    The output should eq ''
  End

  It 'handles a single-element array that needs reboot' do
    Mock node_needs_reboot
      exit 0
    End
    cluster_nodes=("soloN")

    When call filter_into node_needs_reboot cluster_nodes "Removed from reboot sequence."
    The output should eq 'soloN'
    The lines of output should eq 1
  End

  It 'logs the verbose "Removed from reboot sequence" line at verbose>=1' do
    verbose=1
    node_needs_reboot() { [[ "$1" == 'pveSkip' ]] && return 1 || return 0; }
    cluster_nodes=("pveSkip" "pveKeep")

    When call filter_into node_needs_reboot cluster_nodes "Removed from reboot sequence."
    The output should eq 'pveKeep'
    The error should include 'Removed from reboot sequence'
  End
End

# Install a stub for $1 that appends its first argument to a temp file
# and returns 0. The temp-file path is set as `$invocations` for the
# caller to assert against via `The contents of file "$invocations"`.
#
# wait_all runs each invocation in a background subshell, so a regular
# `called_nodes=()` array would lose its appends — the tempfile survives
# the subshell boundary.
#
# Caller should `rm -f "$invocations"` after.
record_invocations() {
  invocations="$(mktemp)"
  eval "$1() { echo \"\$1\" >> \"$invocations\"; return 0; }"
}

Describe 'wait_all node_apt_update (apt update fan-out)'
  Include proxmox-upgrade-cluster.sh

  It 'calls node_apt_update for each node' do
    record_invocations node_apt_update
    cluster_nodes=("pve1" "pve2")

    When call wait_all node_apt_update cluster_nodes
    The status should be success
    The contents of file "$invocations" should include 'pve1'
    The contents of file "$invocations" should include 'pve2'
    rm -f "$invocations"
  End
End

# The down / not-proxmox / running-tasks health checks no longer have
# dedicated wrapper functions — main() captures failed nodes directly via
# `wait_all_failed <predicate> cluster_nodes`. wait_all and wait_all_failed
# are covered in spec/wait_all_spec.sh, and the health-check wiring is covered
# in spec/main_spec.sh.


# main() tests live in spec/main_spec.sh, organized by behavior with a
# Before-hook baseline.
