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

  It 'returns node names from pvesh output' do
    Mock node_pvesh
      echo '[{"type":"node","name":"pve1"},{"type":"node","name":"pve2"}]' | jq -rc '[.[] | select(.type == "node") | .name] | join(" ")'
    End

    When call get_cluster_nodes 'pve1'
    The output should eq 'pve1 pve2'
  End

  It 'returns node IPs when cluster_node_use_ip is true' do
    cluster_node_use_ip=true
    Mock node_pvesh
      echo '[{"type":"node","ip":"10.0.0.1"},{"type":"node","ip":"10.0.0.2"}]' | jq -rc '[.[] | select(.type == "node") | .ip] | join(" ")'
    End

    When call get_cluster_nodes 'pve1'
    The output should eq '10.0.0.1 10.0.0.2'
  End
End

Describe 'node_get_running_guest_count'
  Include proxmox-upgrade-cluster.sh

  It 'returns total count of running guests' do
    Mock node_get_running_lxc
      echo '[{"status":"running"}]'
    End
    Mock node_get_running_qemu
      echo '[{"status":"running"},{"status":"running"},{"status":"stopped"}]'
    End

    When call node_get_running_guest_count 'pve1'
    The output should eq '3'
  End

  It 'returns 0 when no guests are running' do
    Mock node_get_running_lxc
      echo '[]'
    End
    Mock node_get_running_qemu
      echo '[]'
    End

    When call node_get_running_guest_count 'pve1'
    The output should eq '0'
  End
End

Describe 'node_number_of_running_tasks'
  Include proxmox-upgrade-cluster.sh

  It 'returns task count' do
    Mock node_pvesh
      echo '[{"task":"backup"},{"task":"resize"}]'
    End

    When call node_number_of_running_tasks 'pve1'
    The output should eq '2'
  End

  It 'returns 0 when no tasks' do
    Mock node_pvesh
      echo '[]'
    End

    When call node_number_of_running_tasks 'pve1'
    The output should eq '0'
  End
End

Describe 'node_get_offline_count'
  Include proxmox-upgrade-cluster.sh

  It 'returns count of offline nodes' do
    Mock node_pvesh
      echo '{"manager_status":{"node_status":{"pve1":"online","pve2":"offline","pve3":"offline"}}}'
    End

    When call node_get_offline_count 'pve1'
    The output should eq '2'
  End

  It 'returns 0 when all nodes are online' do
    Mock node_pvesh
      echo '{"manager_status":{"node_status":{"pve1":"online","pve2":"online"}}}'
    End

    When call node_get_offline_count 'pve1'
    The output should eq '0'
  End
End

Describe 'node_get_mode'
  Include proxmox-upgrade-cluster.sh

  It 'returns node mode from pvesh output' do
    Mock node_ssh
      echo 'pve1'
    End
    Mock node_pvesh
      echo '{"manager_status":{"node_status":{"pve1":"online"}}}'
    End

    When call node_get_mode 'pve1'
    The output should eq 'online'
  End
End

Describe 'node_service_running'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when service is active' do
    Mock node_ssh
      echo 'active'
    End

    When call node_service_running 'pve1' 'pve-ha-lrm'
    The status should be success
  End

  It 'returns failure when service is not active' do
    Mock node_ssh
      echo 'inactive'
    End

    When call node_service_running 'pve1' 'pve-ha-lrm'
    The status should be failure
  End
End

Describe 'node_not_running_task'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when no tasks running' do
    Mock node_number_of_running_tasks
      echo '0'
    End

    When call node_not_running_task 'pve1'
    The status should be success
  End

  It 'returns failure when tasks are running' do
    Mock node_number_of_running_tasks
      echo '3'
    End

    When call node_not_running_task 'pve1'
    The status should be failure
  End
End

Describe 'node_has_updates'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when updates are available' do
    Mock node_ssh
      echo 'Installs: 5'
    End

    When call node_has_updates 'pve1'
    The status should be success
  End

  It 'returns failure when no updates available' do
    Mock node_ssh
      echo ''
    End

    When call node_has_updates 'pve1'
    The status should be failure
  End
End

Describe 'node_upgrade'
  Include proxmox-upgrade-cluster.sh

  It 'calls node_ssh_no_op with dist-upgrade command' do
    Mock node_ssh_no_op
      echo 'upgraded'
    End

    When call node_upgrade 'pve1'
    The output should include 'upgraded'
  End
End

Describe 'node_apt_update'
  Include proxmox-upgrade-cluster.sh

  It 'calls node_ssh with apt-get update' do
    Mock node_ssh
      echo 'updated'
    End

    When call node_apt_update 'pve1'
    The output should include 'updated'
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
    Mock node_ssh
      echo 'executed'
    End
    dry_run=true

    When call node_ssh_no_op 'pve1' 'whoami'
    The status should be success
    The output should be empty
  End
End

Describe 'is_node_up'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when node is up' do
    Mock node_ssh
      echo 'root'
    End

    When call is_node_up 'pve1'
    The status should be success
  End

  It 'returns failure when node is down' do
    Mock node_ssh
      return 1
    End

    When call is_node_up 'pve1'
    The status should be failure
  End
End

Describe 'is_node_proxmox'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when pvesh is available' do
    Mock node_ssh
      return 0
    End

    When call is_node_proxmox 'pve1'
    The status should be success
  End

  It 'returns failure when pvesh is not available' do
    Mock node_ssh
      return 1
    End

    When call is_node_proxmox 'pve1'
    The status should be failure
  End
End

Describe 'node_pre_upgrade'
  Include proxmox-upgrade-cluster.sh

  It 'calls all pre-upgrade steps' do
    called=()
    node_pre_maintenance_check() { called+=("pre_maintenance_check"); }
    node_enter_maintenance() { called+=("enter_maintenance"); }
    node_wait_all_tasks_completed() { called+=("wait_tasks_completed"); }
    node_wait_until_no_running_guests() { called+=("no_running_guests"); }
    dry_run=false
    allow_running_guests=false

    When call node_pre_upgrade 'pve1'
    The status should be success
  End

  It 'skips waiting for no running guests when dry_run is true' do
    called=()
    node_pre_maintenance_check() { called+=("pre_maintenance_check"); }
    node_enter_maintenance() { called+=("enter_maintenance"); }
    node_wait_all_tasks_completed() { called+=("wait_tasks_completed"); }
    node_wait_until_no_running_guests() { called+=("no_running_guests"); }
    dry_run=true

    When call node_pre_upgrade 'pve1'
    The status should be success
  End
End
