Describe 'node_enter_maintenance'
  Include proxmox-upgrade-cluster.sh

  Before 'verbose=1'

  It 'skips when use_maintenance_mode is false' do
    use_maintenance_mode=false
    node_ssh_no_op() { echo 'skipped'; }
    When call node_enter_maintenance 'pve1'
    The status should be success
    The error should include 'Not setting maintenance mode'
  End

  It 'calls ssh_no_op and waits for maintenance mode' do
    verbose=1
    use_maintenance_mode=true
    dry_run=false
    node_ssh_no_op() { echo 'maintenance set'; }
    node_wait_until_mode() { echo 'in maintenance'; }

    When call node_enter_maintenance 'pve1'
    The status should be success
    The output should include 'in maintenance'
    The error should include 'Enabling maintenance mode'
  End

  It 'skips wait_until_mode when dry_run is true' do
    verbose=1
    use_maintenance_mode=true
    dry_run=true
    node_ssh_no_op() { echo 'maintenance set'; }
    called_wait=0
    node_wait_until_mode() { called_wait=1; }

    When call node_enter_maintenance 'pve1'
    The status should be success
    The error should include 'Enabling maintenance mode'
  End
End

Describe 'node_exit_maintenance'
  Include proxmox-upgrade-cluster.sh

  It 'skips when use_maintenance_mode is false' do
    verbose=1
    use_maintenance_mode=false

    When call node_exit_maintenance 'pve1'
    The status should be success
  End

  It 'calls service wait, ssh_no_op, and mode wait' do
    verbose=1
    use_maintenance_mode=true
    dry_run=false
    node_wait_until_service_running() { echo 'service running'; }
    node_ssh_no_op() { echo 'maintenance disabled'; }
    node_wait_until_mode() { echo 'online'; }

    When call node_exit_maintenance 'pve1'
    The status should be success
    The output should include 'service running'
    The output should include 'online'
    The error should include 'Disabling maintenance mode'
  End

  It 'skips wait_until_mode when dry_run is true' do
    verbose=1
    use_maintenance_mode=true
    dry_run=true
    node_wait_until_service_running() { echo 'service running'; }
    node_ssh_no_op() { echo 'maintenance disabled'; }
    called_wait=0
    node_wait_until_mode() { called_wait=1; }

    When call node_exit_maintenance 'pve1'
    The status should be success
    The output should include 'service running'
    The error should include 'Disabling maintenance mode'
  End
End

Describe 'node_reboot'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when neither force_reboot nor needs_reboot' do
    verbose=1
    force_reboot=false
    node_needs_reboot() { return 1; }

    When call node_reboot 'pve1'
    The status should be success
    The error should include "Doesn't need to be rebooted"
  End

  It 'reboots when force_reboot is true' do
    force_reboot=true
    dry_run=false
    verbose=1
    node_needs_reboot() { return 1; }
    wait_sleep() { :; }
    node_ssh_no_op() { echo 'rebooting'; }
    is_node_up() { return 0; }
    When call node_reboot 'pve1'
    The status should be success
    The error should include 'Forcing Reboot'
    The error should include 'Rebooting in 5 seconds'
    The error should include 'for node to come back up'
    The error should include 'Rebooted successfully'
  End

  It 'skips reboot when dry_run is true and needs reboot' do
    force_reboot=false
    dry_run=true
    node_needs_reboot() { return 0; }

    When call node_reboot 'pve1'
    The status should be success
    The error should include "Needs to be rebooted"
    The error should include 'Not rebooting'
  End

  It 'reboots when needs_reboot is true and force_reboot is false' do
    force_reboot=false
    dry_run=false
    verbose=1
    node_needs_reboot() { return 0; }
    wait_sleep() { :; }
    node_ssh_no_op() { echo 'rebooting'; }
    is_node_up() { return 0; }

    When call node_reboot 'pve1'
    The status should be success
    The error should include "Needs to be rebooted"
    The error should include 'Rebooting in 5 seconds'
    The error should include 'for node to come back up'
    The error should include 'Rebooted successfully'
  End

  It 'passes ssh keepalive options when invoking reboot and dmesg -W' do
    force_reboot=true
    dry_run=false
    verbose=3  # log_pipe_level 3 (reboot pipe) only emits when verbose>=3
    node_needs_reboot() { return 1; }
    wait_sleep() { :; }
    # node_ssh_no_op's stdout gets piped through log_pipe_level → log_output → stderr,
    # so assert against stderr.
    node_ssh_no_op() {
      local node=$1; shift
      local cmd=$1; shift
      echo "ssh($node, $cmd, $*)"
    }
    is_node_up() { return 0; }

    When call node_reboot 'pve1'
    The status should be success
    The error should include 'ssh(pve1, reboot, -oConnectTimeout=10 -oServerAliveInterval=5 -oServerAliveCountMax=2)'
    The error should include 'ssh(pve1, dmesg -W, -oConnectTimeout=10 -oServerAliveInterval=5 -oServerAliveCountMax=2)'
  End

  It 'aborts with a timeout error when the node does not come back up' do
    force_reboot=true
    dry_run=false
    verbose=1
    reboot_timeout=0
    node_needs_reboot() { return 1; }
    wait_sleep() { :; }
    node_ssh_no_op() { :; }
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

  It 'calls exit_maintenance' do
    pkgs_reinstall=()
    node_ssh_no_op() { :; }
    node_exit_maintenance() { echo 'exited maintenance'; }

    When call node_post_upgrade 'pve1'
    The output should include 'exited maintenance'
    The error should include "No packages to force reinstall"
    The error should include 'Removing old packages'
  End

  It 'reinstalls packages when pkgs_reinstall is set' do
    pkgs_reinstall=("pve-firmware")
    node_ssh_no_op() { echo 'reinstalled'; }
    node_exit_maintenance() { echo 'exited maintenance'; }

    When call node_post_upgrade 'pve1'
    The output should include 'exited maintenance'
    The error should include "Force reinstalling"
    The error should include 'Removing old packages'
  End
End

Describe 'node_run_update_sequence'
  Include proxmox-upgrade-cluster.sh
  Set errexit:on

  It 'runs all upgrade steps on the success path without warning' do
    node_pre_upgrade() { :; }
    node_upgrade() { :; }
    node_reboot() { :; }
    node_post_upgrade() { :; }

    When call node_run_update_sequence 'pve1'
    The status should be success
    The error should include 'Starting upgrade'
    The error should include 'Successfully upgraded'
    The error should not include 'may still be in maintenance'
  End

  It 'warns about maintenance and does NOT auto-recover when an upgrade step fails' do
    use_maintenance_mode=true
    node_pre_upgrade() { :; }
    node_upgrade() { return 1; }
    node_reboot() { echo 'should not reach reboot' >&2; }
    node_post_upgrade() { echo 'should not reach post' >&2; }
    node_exit_maintenance() { echo 'auto-recovery ran (BAD)' >&2; }

    When run node_run_update_sequence 'pve1'
    The status should be failure
    The error should include 'may still be in maintenance mode'
    The error should include 'ha-manager crm-command node-maintenance disable'
    The error should not include 'should not reach'
    The error should not include 'auto-recovery ran'
  End

  It 'does not warn when use_maintenance_mode is false even on failure' do
    use_maintenance_mode=false
    node_pre_upgrade() { :; }
    node_upgrade() { return 1; }
    node_reboot() { :; }
    node_post_upgrade() { :; }

    When run node_run_update_sequence 'pve1'
    The status should be failure
    The error should not include 'may still be in maintenance'
  End

  It 'clears the ERR trap on success so it does not leak across nodes' do
    node_pre_upgrade() { :; }
    node_upgrade() { :; }
    node_reboot() { :; }
    node_post_upgrade() { :; }

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
    node_pre_upgrade() {
      [[ $- == *E* ]] && echo "ERRTRACE-LEAKED" >&2
    }
    node_upgrade()      { :; }
    node_reboot()       { :; }
    node_post_upgrade() { :; }

    When call node_run_update_sequence 'pve1'
    The status should be success
    The error should not include 'ERRTRACE-LEAKED'
    The error should not include 'may still be in maintenance'
  End
End

Describe 'node_wait_until_service_running'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when service is already running' do
    node_service_running() { return 0; }
    wait_sleep() { return 0; }

    When call node_wait_until_service_running 'pve1' 'pve-ha-lrm'
    The status should be success
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

  It 'returns success when guest count is 0' do
    allow_running_guests=false
    node_get_running_guest_count() { echo '0'; }
    wait_sleep() { return 0; }

    When call node_wait_until_no_running_guests 'pve1'
    The status should be success
    The error should include "Waiting until all guests are migrated"
    The error should include "Reached zero running guests"
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

  It 'returns success when task count is 0' do
    allow_running_tasks=false
    node_number_of_running_tasks() { echo '0'; }
    wait_sleep() { return 0; }

    When call node_wait_all_tasks_completed 'pve1'
    The status should be success
    The error should include "Waiting until all cluster tasks have completed"
    The error should include "Cluster reached zero running tasks"
  End
End

Describe 'node_pre_maintenance_check'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when no offline nodes' do
    node_get_offline_count() { echo '0'; }
    wait_sleep() { return 0; }

    When call node_pre_maintenance_check 'pve1'
    The status should be success
    The error should include "Checking that no cluster nodes are currently offline"
    The error should include "All cluster nodes are online"
  End
End

Describe 'get_nodes_upgradeable'
  Include proxmox-upgrade-cluster.sh

  It 'emits nodes that have updates, one per line' do
    Mock node_has_updates
      exit 0
    End
    cluster_nodes=("pve1" "pve2")

    When call get_nodes_upgradeable cluster_nodes
    The line 1 of output should eq 'pve1'
    The line 2 of output should eq 'pve2'
    The lines of output should eq 2
    The error should include 'Updates available'
  End

  It 'excludes nodes without updates' do
    # Inline override — Mock's subshell would lose the persistent counter.
    node_has_updates() { [[ "$1" == 'pve1' ]]; }
    cluster_nodes=("pve1" "pve2")

    When call get_nodes_upgradeable cluster_nodes
    The output should eq 'pve1'
    The lines of output should eq 1
    The error should include 'Updates available'
  End

  It 'returns empty output when called with empty array' do
    Mock node_has_updates
      exit 0
    End
    cluster_nodes=()

    When call get_nodes_upgradeable cluster_nodes
    The output should eq ''
  End

  It 'returns empty output when no nodes have updates' do
    Mock node_has_updates
      exit 1
    End
    cluster_nodes=("pve1" "pve2")

    When call get_nodes_upgradeable cluster_nodes
    The output should eq ''
    The error should include 'No updates available'
  End
End

Describe 'apt_update_nodes'
  Include proxmox-upgrade-cluster.sh

  It 'calls node_apt_update for each node' do
    called_nodes=()
    node_apt_update() { called_nodes+=("$1"); }
    cluster_nodes=("pve1" "pve2")

    When call apt_update_nodes cluster_nodes
    The status should be success
  End
End

Describe 'all_nodes_up'
  Include proxmox-upgrade-cluster.sh

  It 'calls is_node_up for each node' do
    called_nodes=()
    is_node_up() { called_nodes+=("$1"); return 0; }
    cluster_nodes=("pve1" "pve2")

    When call all_nodes_up cluster_nodes
    The status should be success
  End
End

Describe 'all_nodes_proxmox'
  Include proxmox-upgrade-cluster.sh

  It 'calls is_node_proxmox for each node' do
    called_nodes=()
    is_node_proxmox() { called_nodes+=("$1"); return 0; }
    cluster_nodes=("pve1" "pve2")

    When call all_nodes_proxmox cluster_nodes
    The status should be success
  End
End

Describe 'any_nodes_running_tasks'
  Include proxmox-upgrade-cluster.sh

  It 'calls node_not_running_task for each node' do
    called_nodes=()
    node_not_running_task() { return 0; called_nodes+=("$1"); }
    cluster_nodes=("pve1" "pve2")

    When call any_nodes_running_tasks cluster_nodes
    The status should be success
  End
End


Describe 'main'
  Include proxmox-upgrade-cluster.sh

  It 'logs dry run warning when dry_run is true' do
    test_main_dry_run() {
      process_args() { :; }
      verbose=0; dry_run=true; cluster_nodes=('pve1')
      all_nodes_up() { return 0; }
      all_nodes_proxmox() { return 0; }
      node_get_offline_count() { echo '0'; }
      any_nodes_running_tasks() { :; }
      apt_update_nodes() { :; }
      get_nodes_upgradeable() { :; }
      main
    }
    When run test_main_dry_run
    The status should be success
    The error should include 'dry run mode'
  End

  It 'exits with error when cluster_node is down' do
    test_main_cluster_down() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 1; }
      main
    }
    When run test_main_cluster_down
    The status should be failure
    The error should include 'node is currently down'
  End

  It 'exits with error when all_nodes_up fails' do
    test_main_nodes_down() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 0; }; is_node_proxmox() { return 0; }; all_nodes_up() { return 1; }
      main
    }
    When run test_main_nodes_down
    The status should be failure
    The error should include 'At least one node is currently down'
  End

  It 'exits with error when nodes are not proxmox' do
    test_main_not_proxmox() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 0; }; all_nodes_up() { return 0; }
      all_nodes_proxmox() { log_alert "Node is not proxmox"; return 1; }
      main
    }
    When run test_main_not_proxmox
    The status should be failure
    The error should include 'Node is not proxmox'
  End

  It 'exits with error when offline nodes exist' do
    test_main_offline() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 0; }; is_node_proxmox() { return 0; }; all_nodes_up() { return 0; }
      node_get_offline_count() { echo '1'; }
      main
    }
    When run test_main_offline
    The status should be failure
    The error should include 'not online'
  End

  It 'exits with error when running tasks exist (default)' do
    test_main_tasks_running() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 0; }; is_node_proxmox() { return 0; }; all_nodes_up() { return 0; }
      node_get_offline_count() { echo '0'; }; any_nodes_running_tasks() { return 1; }
      main
    }
    When run test_main_tasks_running
    The status should be failure
    The error should include 'running tasks'
  End

  It 'skips task check when allow_running_tasks is true' do
    test_main_allow_tasks() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      allow_running_tasks=true
      is_node_up() { return 0; }; is_node_proxmox() { return 0; }; all_nodes_up() { return 0; }
      node_get_offline_count() { echo '0'; }; apt_update_nodes() { :; }; get_nodes_upgradeable() { :; }
      main
    }
    When run test_main_allow_tasks
    The status should be success
    The error should include 'Not checking for running cluster tasks'
  End

  It 'exits 0 when no nodes have updates and force_upgrade is false' do
    test_main_no_updates() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 0; }; is_node_proxmox() { return 0; }; all_nodes_up() { return 0; }
      node_get_offline_count() { echo '0'; }; any_nodes_running_tasks() { :; }; apt_update_nodes() { :; }
      main
    }
    When run test_main_no_updates
    The status should be success
    The error should include 'No nodes need updates'
  End

  It 'forces upgrade for all nodes when force_upgrade is true' do
    test_main_force_upgrade() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 0; }; is_node_proxmox() { return 0; }; all_nodes_up() { return 0; }
      node_get_offline_count() { echo '0'; }; any_nodes_running_tasks() { :; }; apt_update_nodes() { :; }
      force_upgrade=true
      node_run_update_sequence() { :; }
      main
    }
    When run test_main_force_upgrade
    The status should be success
    The error should include 'Forcing upgrade'
  End

  It 'runs upgrade sequence for each upgradeable node' do
    test_main_run_sequence() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 0; }; is_node_proxmox() { return 0; }; all_nodes_up() { return 0; }
      node_get_offline_count() { echo '0'; }; any_nodes_running_tasks() { :; }; apt_update_nodes() { :; }
      get_nodes_upgradeable() { :; }
      main
    }
    When run test_main_run_sequence
    The status should be success
    The error should include 'No nodes need updates'
  End

  It 'uses cluster_nodes directly when --node is passed instead of --cluster-node' do
    test_main_node_array() {
      process_args() { :; }
      verbose=0; dry_run=false; get_cluster_nodes() { :; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 0; }; is_node_proxmox() { return 0; }; all_nodes_up() { return 0; }
      node_get_offline_count() { echo '0'; }; any_nodes_running_tasks() { :; }; apt_update_nodes() { :; }
      cluster_nodes=("pve1" "pve2")
      main
    }
    When run test_main_node_array
    The status should be success
    The error should include 'No nodes need updates'
  End

  It 'logs warning when maintenance mode is disabled' do
    test_main_no_maintenance() {
      process_args() { :; }
      verbose=0; dry_run=false; cluster_node='pve1'; get_cluster_nodes() { echo 'pve1'; }
      Mock local_ssh
        exit 0
      End
      is_node_up() { return 0; }; is_node_proxmox() { return 0; }; all_nodes_up() { return 0; }
      node_get_offline_count() { echo '0'; }; any_nodes_running_tasks() { :; }; apt_update_nodes() { :; }
      get_nodes_upgradeable() { :; }
      use_maintenance_mode=false
      main
    }
    When run test_main_no_maintenance
    The status should be success
    The error should include 'Not using maintenance mode'
  End
End
