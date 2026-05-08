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

    It 'has log_output default to /dev/stderr' do
      The variable log_output should eq '/dev/stderr'
    End

    It 'has jq_bin default to jq' do
      The variable jq_bin should eq 'jq'
    End
  End

  Describe 'ssh_options default' do
    It 'has empty ssh_options array' do
      The length of variable ssh_options should eq 0
    End

    It 'has empty pkgs_reinstall array' do
      The length of variable pkgs_reinstall should eq 0
    End

    It 'has empty cluster_nodes array' do
      The length of variable cluster_nodes should eq 0
    End

    It 'has empty upgrade_nodes array' do
      The length of variable upgrade_nodes should eq 0
    End
  End
End
