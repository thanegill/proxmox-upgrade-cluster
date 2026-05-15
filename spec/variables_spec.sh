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

    It 'has jq_bin default to jq' do
      The variable jq_bin should eq 'jq'
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
End
