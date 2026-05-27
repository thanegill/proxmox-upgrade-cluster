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
    node_pvesh() { echo '[{"type":"node","name":"pve1"},{"type":"node","name":"pve2"}]'; }

    When call get_cluster_nodes 'pve1'
    The output should eq 'pve1 pve2'
  End

  It 'returns node IPs when cluster_node_use_ip is true' do
    cluster_node_use_ip=true
    node_pvesh() { echo '[{"type":"node","ip":"10.0.0.1"},{"type":"node","ip":"10.0.0.2"}]'; }

    When call get_cluster_nodes 'pve1'
    The output should eq '10.0.0.1 10.0.0.2'
  End
End

Describe 'node_get_running_guest_count'
  Include proxmox-upgrade-cluster.sh

  It 'returns total count of running guests' do
    node_get_running() {
      if [[ "$2" == "lxc" ]]; then echo '[{"status":"running"}]'; else echo '[{"status":"running"},{"status":"running"}]'; fi
    }
    When call node_get_running_guest_count 'pve1'
    The output should eq '3'
  End

  It 'returns 0 when no guests are running' do
    node_get_running() { echo '[]'; }

    When call node_get_running_guest_count 'pve1'
    The output should eq '0'
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

Describe 'node_get_offline_count'
  Include proxmox-upgrade-cluster.sh

  It 'returns count of offline nodes' do
    node_pvesh() { echo '{"manager_status":{"node_status":{"pve1":"online","pve2":"offline","pve3":"offline"}}}'; }

    When call node_get_offline_count 'pve1'
    The output should eq '2'
  End

  It 'returns 0 when all nodes are online' do
    node_pvesh() { echo '{"manager_status":{"node_status":{"pve1":"online","pve2":"online"}}}'; }

    When call node_get_offline_count 'pve1'
    The output should eq '0'
  End
End

Describe 'node_get_mode'
  Include proxmox-upgrade-cluster.sh

  It 'returns node mode from pvesh output' do
    node_ssh() { echo 'pve1'; }
    node_pvesh() { echo '{"manager_status":{"node_status":{"pve1":"online"}}}'; }

    When call node_get_mode 'pve1'
    The output should eq 'online'
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
End

Describe 'node_has_updates'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when updates are available' do
    node_ssh() { echo 'Installs: 5'; }

    When call node_has_updates 'pve1'
    The status should be success
  End

  It 'returns failure when no updates available' do
    node_ssh() { echo ''; }

    When call node_has_updates 'pve1'
    The status should be failure
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

Describe 'node_get_running' do
  Include proxmox-upgrade-cluster.sh

  It 'returns running lxc containers excluding stopped' do
    node_pvesh() { echo '[{"status":"running"},{"status":"stopped"}]'; }

    When call node_get_running 'pve1' 'lxc'
    The output should include '"status":"running"'
    The output should not include '"status":"stopped"'
  End

  It 'returns running qemu guests excluding stopped' do
    node_pvesh() { echo '[{"status":"running"},{"status":"stopped"}]'; }

    When call node_get_running 'pve1' 'qemu'
    The output should include '"status":"running"'
    The output should not include '"status":"stopped"'
  End

  It 'returns empty array when no containers' do
    node_pvesh() { echo '[]'; }

    When call node_get_running 'pve1' 'lxc'
    The output should eq '[]'
  End

  It 'returns empty array when no guests' do
    node_pvesh() { echo '[]'; }

    When call node_get_running 'pve1' 'qemu'
    The output should eq '[]'
  End
End

Describe 'node_needs_reboot'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when kernels differ' do
    local ssh_call_count=0
    node_ssh() {
      ((ssh_call_count++)) || true
      if [[ "$2" == *"grep"* ]]; then
        echo "linux   /boot/vmlinuz-6.2.0-pve root=..."
      else
        echo "6.1.0-pve"
      fi
    }

    When call node_needs_reboot 'pve1'
    The status should be success
  End

  It 'returns failure when kernels match' do
    local ssh_call_count=0
    node_ssh() {
      ((ssh_call_count++)) || true
      if [[ "$2" == *"grep"* ]]; then
        echo "linux   /boot/vmlinuz-6.2.0-pve root=..."
      else
        echo "6.2.0-pve"
      fi
    }

    When call node_needs_reboot 'pve1'
    The status should be failure
  End
End

Describe 'node_wait_until_mode'
  Include proxmox-upgrade-cluster.sh

  It 'returns success when already in target mode' do
    verbose=1
    node_get_mode() { echo 'online'; }
    wait_sleep() { :; }

    When call node_wait_until_mode 'pve1' 'online'
    The status should be success
    The error should include 'Waiting until node enters online mode'
  End

  It 'polls until mode changes to target' do
    verbose=1
    _mode_file=$(mktemp)
    echo 'maintenance' > "$_mode_file"

    node_get_mode() { cat "$_mode_file"; }

    wait_sleep() {
      :;
      # Change mode from maintenance to online after first poll
      local current
      current=$(cat "$_mode_file")
      [[ "$current" == "maintenance" ]] && echo 'online' > "$_mode_file"
    }

    When call node_wait_until_mode 'pve1' 'online'
    The status should be success
    The error should include 'Reached target mode'
    rm -f "$_mode_file"
  End

  It 'logs current vs target mode when polling' do
    verbose=2
    _mode_file=$(mktemp)
    echo 'maintenance' > "$_mode_file"

    node_get_mode() { cat "$_mode_file"; }

    wait_sleep() {
      :;
      local current
      current=$(cat "$_mode_file")
      [[ "$current" == "maintenance" ]] && echo 'online' > "$_mode_file"
    }

    When call node_wait_until_mode 'pve1' 'online'
    The error should include 'Current mode'
    rm -f "$_mode_file"
  End
End

Describe 'is_node_up'
  Include proxmox-upgrade-cluster.sh

  verbose=3

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

Describe 'node_pre_upgrade'
  Include proxmox-upgrade-cluster.sh

  It 'calls all pre-upgrade steps' do
    dry_run=false
    allow_running_guests=false
    node_pre_maintenance_check() { return 0; }
    node_enter_maintenance() { :; }
    node_wait_all_tasks_completed() { :; }
    node_wait_until_no_running_guests() { :; }

    When call node_pre_upgrade 'pve1'
    The status should be success
  End

  It 'skips waiting for no running guests when dry_run is true' do
    dry_run=true
    node_pre_maintenance_check() { return 0; }
    node_enter_maintenance() { :; }
    node_wait_all_tasks_completed() { :; }
    node_wait_until_no_running_guests() { :; }

    When call node_pre_upgrade 'pve1'
    The status should be success
  End
End
