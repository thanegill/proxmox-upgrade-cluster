Describe 'main'
  Include proxmox-upgrade-cluster.sh

  Describe 'jq prerequisite check' do
    It 'exits 1 with a clear error when jq is not on PATH' do
      # Override `command` so the jq lookup fails. `command -v jq` returns 1.
      command() {
        if [[ "$1" == '-v' && "$2" == 'jq' ]]; then
          return 1
        fi
        builtin command "$@"
      }

      When run main '--cluster-node' 'pve1'
      The status should be failure
      The status should eq 1
      The error should include "'jq' is required"
    End
  End

  Describe 'empty cluster discovery' do
    It 'exits 1 with a clear error when get_cluster_nodes returns nothing' do
      is_node_up() { return 0; }
      is_node_proxmox() { return 0; }
      get_cluster_nodes() { :; }  # emit nothing

      When run main '--cluster-node' 'pve1'
      The status should be failure
      The status should eq 1
      The error should include 'No cluster nodes to check.'
    End

    It 'does not reach node_get_offline_count when cluster discovery is empty' do
      # If the empty-array guard fails, ${cluster_nodes[0]} would expand and
      # call node_get_offline_count (or trigger nounset). This canary asserts
      # neither happens.
      is_node_up() { return 0; }
      is_node_proxmox() { return 0; }
      get_cluster_nodes() { :; }
      node_get_offline_count() { echo 'CANARY: should not be called'; }
      all_nodes_up() { return 0; }
      all_nodes_proxmox() { return 0; }

      When run main '--cluster-node' 'pve1'
      The status should be failure
      The output should not include 'CANARY'
      The error should include 'No cluster nodes to check.'
    End
  End
End
