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

  Describe 'upgrade-sequence sorting' do
    # Shared stubs: get past all health checks, no apt updates available, then
    # exit before the upgrade loop runs. node_run_update_sequence is mocked so
    # we don't actually exercise the upgrade flow.
    pass_health_checks() {
      is_node_up() { return 0; }
      is_node_proxmox() { return 0; }
      all_nodes_up() { return 0; }
      all_nodes_proxmox() { return 0; }
      node_get_offline_count() { echo '0'; }
      any_nodes_running_tasks() { return 0; }
      apt_update_nodes() { :; }
      node_run_update_sequence() { echo "RUN: $1"; }
    }

    It 'sorts upgrade_nodes by guest count when --cluster-node is used and flag is default' do
      pass_health_checks
      get_cluster_nodes() { printf '%s\n' pveA pveB pveC; }
      node_has_updates() { return 0; }   # everyone has updates → upgrade_nodes = cluster_nodes
      node_get_running_guest_count() {
        case "$1" in
          pveA) echo '5' ;;
          pveB) echo '1' ;;
          pveC) echo '3' ;;
        esac
      }

      When run main '--cluster-node' 'pve1'
      The status should be success
      The line 1 of output should eq 'RUN: pveB'
      The line 2 of output should eq 'RUN: pveC'
      The line 3 of output should eq 'RUN: pveA'
      The error should include 'Reordering upgrade sequence'
    End

    It 'preserves discovery order when --preserve-discovery-order is set' do
      pass_health_checks
      get_cluster_nodes() { printf '%s\n' pveA pveB pveC; }
      node_has_updates() { return 0; }
      # Sentinel: if the sort runs, this would be called.
      node_get_running_guest_count() { echo 'SORT-RAN' >&2; echo '0'; }

      When run main '--cluster-node' 'pve1' '--preserve-discovery-order'
      The status should be success
      The line 1 of output should eq 'RUN: pveA'
      The line 2 of output should eq 'RUN: pveB'
      The line 3 of output should eq 'RUN: pveC'
      The error should not include 'SORT-RAN'
      The error should not include 'Reordering upgrade sequence'
    End

    It 'preserves manual order when --node is used (no cluster discovery)' do
      pass_health_checks
      node_has_updates() { return 0; }
      node_get_running_guest_count() { echo 'SORT-RAN' >&2; echo '0'; }

      When run main '--node' 'pve3' '--node' 'pve1' '--node' 'pve2'
      The status should be success
      The line 1 of output should eq 'RUN: pve3'
      The line 2 of output should eq 'RUN: pve1'
      The line 3 of output should eq 'RUN: pve2'
      The error should not include 'SORT-RAN'
      The error should not include 'Reordering upgrade sequence'
    End
  End
End
