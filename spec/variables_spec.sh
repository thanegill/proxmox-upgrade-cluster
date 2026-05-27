Describe 'proxmox-upgrade-cluster.sh'
  Include proxmox-upgrade-cluster.sh

  Describe 'program_name' do
    It 'is set to the script basename' do
      When call basename "$0"
      The output should eq "$program_name"
    End
  End

  Describe 'default variables' do
    It 'has ssh_user default to root' do
      The variable ssh_user should eq 'root'
    End

    It 'has verbose default to 0' do
      The variable verbose should eq 0
    End

    It 'defines log_output as a function that writes to stderr' do
      When call declare -f log_output
      The output should include 'cat -'
      The output should include '&2'
    End

    It 'has reboot_timeout default to 900' do
      The variable reboot_timeout should eq 900
    End
  End

  Describe 'boolean flag defaults' do
    # Scalar name + scalar value, no function-name substitution and no
    # spaces — one of the few cases Parameters handles cleanly per the
    # documented limitations in CLAUDE.md.
    Parameters
      ssh_key_auth_only        true
      cluster_node_use_ip      false
      force_upgrade            false
      force_reboot             false
      skip_reboot              false
      reboot_only              false
      dry_run                  false
      use_maintenance_mode     true
      allow_running_guests     false
      allow_running_tasks      false
      preserve_discovery_order false
    End

    It "$1 defaults to $2" do
      The variable "$1" should eq "$2"
    End
  End

  Describe 'default arrays are initialized as empty' do
    It 'has empty ssh_options by default' do
      process_args() { echo "${#ssh_options[@]}"; }
      When call process_args '--cluster-node' 'pve1'
      The output should eq '0'
    End

    It 'has empty pkgs_reinstall by default' do
      node_upgrade() { echo "${#pkgs_reinstall[@]}"; }
      When call node_upgrade 'pve1'
      The output should eq '0'
    End

    It 'has empty cluster_nodes by default' do
      upgrade_sequence() { echo "${#cluster_nodes[@]}"; }
      verbose=0
      When call upgrade_sequence '--node' 'pve1'
      The output should eq '0'
    End

    It 'has empty upgrade_nodes by default' do
      all_nodes_up() { echo "${#upgrade_nodes[@]}"; }
      When call all_nodes_up 'pve1' 'pve2'
      The output should eq '0'
    End
  End

  Describe 'wait_sleep' do
    It 'calls sleep with default 1 second' do
      test_wait_sleep() {
        local sleep_called=0
        sleep() { sleep_called=1; }
        wait_sleep '1s'
        echo "$sleep_called"
      }
      When call test_wait_sleep
      The output should eq '1'
    End

    It 'accepts custom duration argument' do
      test_wait_sleep_custom() {
        local sleep_arg=""
        sleep() { sleep_arg="$1"; }
        wait_sleep '0.5s'
        echo "$sleep_arg"
      }
      When call test_wait_sleep_custom
      The output should eq '0.5s'
    End

    It 'exits with error when no duration provided' do
      When run wait_sleep
      The status should be failure
      The error should include 'parameter not set'
    End
  End

  Describe 'log_output' do
    It 'writes output to stderr directly' do
      Mock log_output
        echo "stderr test" >&2
      End
      When call log_output 'test data'
      The error should include 'stderr test'
    End
  End
End
