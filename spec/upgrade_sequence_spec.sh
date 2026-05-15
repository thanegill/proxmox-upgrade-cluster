Describe 'node_enter_maintenance'
  Include proxmox-upgrade-cluster.sh

  verbose=1

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
    The error should include 'Waiting to come back up'
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

  It 'runs all upgrade steps' do
    called=()
    node_pre_upgrade() { called+=("pre"); }
    node_upgrade() { called+=("upgrade"); }
    node_reboot() { called+=("reboot"); }
    node_post_upgrade() { called+=("post"); }

    When call node_run_update_sequence 'pve1'
    The status should be success
    The error should include 'Starting upgrade'
    The error should include 'Successfully upgraded'
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

  It 'returns nodes that have updates' do
    Mock node_has_updates
      exit 0
    End
    cluster_nodes=("pve1" "pve2")

    When call get_nodes_upgradeable cluster_nodes
    The output should include 'pve1'
    The output should include 'pve2'
    The error should include 'Updates available'
  End

  It 'excludes nodes without updates' do
    call_count=0
    Mock node_has_updates
      call_count=$((call_count + 1))
      [[ $call_count -eq 1 ]] && exit 0 || exit 1
    End
    cluster_nodes=("pve1" "pve2")

    When call get_nodes_upgradeable cluster_nodes
    The output should include 'pve1'
    The error should include 'Updates available'
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
      get_nodes_upgradeable() { echo ''; }
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
      node_get_offline_count() { echo '0'; }; apt_update_nodes() { :; }; get_nodes_upgradeable() { echo ''; }
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
      get_nodes_upgradeable() { echo ''; }
      main
    }
    When run test_main_run_sequence
    The status should be success
    The error should include 'No nodes need updates'
  End

  It 'uses cluster_nodes directly when --node is passed instead of --cluster-node' do
    test_main_node_array() {
      process_args() { :; }
      verbose=0; dry_run=false; get_cluster_nodes() { echo ''; }
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
End
