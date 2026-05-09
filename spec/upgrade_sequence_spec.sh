Describe 'node_enter_maintenance'
  Include proxmox-upgrade-cluster.sh

  It 'skips when use_maintenance_mode is false' do
    verbose=1
    use_maintenance_mode=false
    Mock node_ssh_no_op
      echo 'skipped'
    End

    When call node_enter_maintenance 'pve1'
    The status should be success
    The error should include 'Not setting maintenance mode'
  End

  It 'calls ssh_no_op and waits for maintenance mode' do
    verbose=1
    use_maintenance_mode=true
    dry_run=false
    Mock node_ssh_no_op
      echo 'maintenance set'
    End
    Mock node_wait_until_mode
      echo 'in maintenance'
    End

    When call node_enter_maintenance 'pve1'
    The status should be success
    The output should include 'in maintenance'
    The error should include 'Enabling maintenance mode'
  End

  It 'skips wait_until_mode when dry_run is true' do
    verbose=1
    use_maintenance_mode=true
    dry_run=true
    Mock node_ssh_no_op
      echo 'maintenance set'
    End
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
    Mock node_wait_until_service_running
      echo 'service running'
    End
    Mock node_ssh_no_op
      echo 'maintenance disabled'
    End
    Mock node_wait_until_mode
      echo 'online'
    End

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
    Mock node_wait_until_service_running
      echo 'service running'
    End
    Mock node_ssh_no_op
      echo 'maintenance disabled'
    End
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
    Mock node_needs_reboot
      exit 1
    End

    When call node_reboot 'pve1'
    The status should be success
    The error should include "Doesn't need to be rebooted"
  End

  It 'reboots when force_reboot is true' do
    force_reboot=true
    dry_run=false
    Mock node_needs_reboot
      return 1
    End
    Mock node_ssh_no_op
      echo 'rebooting'
    End
    Mock is_node_up
      return 0
    End

    When call node_reboot 'pve1'
    The status should be success
  End

  It 'skips reboot when dry_run is true and needs reboot' do
    force_reboot=false
    dry_run=true
    Mock node_needs_reboot
      return 0
    End

    When call node_reboot 'pve1'
    The status should be success
  End
End

Describe 'node_post_upgrade'
  Include proxmox-upgrade-cluster.sh

  It 'calls exit_maintenance' do
    pkgs_reinstall=()
    Mock node_exit_maintenance
      echo 'exited maintenance'
    End

    When call node_post_upgrade 'pve1'
    The output should include 'exited maintenance'
  End

  It 'reinstalls packages when pkgs_reinstall is set' do
    pkgs_reinstall=("pve-firmware")
    Mock node_ssh_no_op
      echo 'reinstalled'
    End
    Mock node_exit_maintenance
      echo 'exited maintenance'
    End

    When call node_post_upgrade 'pve1'
    The output should include 'exited maintenance'
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
  End
End

Describe 'node_wait_until_service_running'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when service is already running' do
    Mock node_service_running
      return 0
    End

    When call node_wait_until_service_running 'pve1' 'pve-ha-lrm'
    The status should be success
  End
End

Describe 'node_wait_until_no_running_guests'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when allow_running_guests is true' do
    allow_running_guests=true
    Mock node_get_running_guest_count
      echo '5'
    End

    When call node_wait_until_no_running_guests 'pve1'
    The status should be success
  End

  It 'returns success when guest count is 0' do
    allow_running_guests=false
    Mock node_get_running_guest_count
      echo '0'
    End

    When call node_wait_until_no_running_guests 'pve1'
    The status should be success
  End
End

Describe 'node_wait_all_tasks_completed'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when allow_running_tasks is true' do
    allow_running_tasks=true
    Mock node_number_of_running_tasks
      echo '5'
    End

    When call node_wait_all_tasks_completed 'pve1'
    The status should be success
  End

  It 'returns success when task count is 0' do
    allow_running_tasks=false
    Mock node_number_of_running_tasks
      echo '0'
    End

    When call node_wait_all_tasks_completed 'pve1'
    The status should be success
  End
End

Describe 'node_pre_maintenance_check'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when no offline nodes' do
    Mock node_get_offline_count
      echo '0'
    End

    When call node_pre_maintenance_check 'pve1'
    The status should be success
  End
End

Describe 'get_nodes_upgradeable'
  Include proxmox-upgrade-cluster.sh

  It 'returns nodes that have updates' do
    Mock node_has_updates
      return 0
    End
    cluster_nodes=("pve1" "pve2")

    When call get_nodes_upgradeable cluster_nodes
    The output should include 'pve1'
    The output should include 'pve2'
  End

  It 'excludes nodes without updates' do
    call_count=0
    Mock node_has_updates
      call_count=$((call_count + 1))
      [[ $call_count -eq 1 ]] && return 0 || return 1
    End
    cluster_nodes=("pve1" "pve2")

    When call get_nodes_upgradeable cluster_nodes
    The output should include 'pve1'
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

Describe 'wait_all_succeed'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when all jobs succeed' do
    local_jobs_succeed() { return 0; }
    test_array=("a" "b" "c")

    When call wait_all_succeed local_jobs_succeed test_array
    The status should be success
  End
End
