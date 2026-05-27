# Install the happy-path stubs for main()'s health-check + apt-update +
# upgrade flow. Each main test calls this near the top, then overrides
# specific stubs to drive the branch under test.
#
# Note: this lives at file scope (not inside `Before`) because ShellSpec
# runs Before hooks in their own subshell — function definitions made there
# don't survive into the It-block body. A regular helper function works
# because function definitions inside a called function are visible at
# the global scope of the caller in bash.
install_main_happy_path_stubs() {
  is_node_up() { return 0; }
  is_node_proxmox() { return 0; }
  all_nodes_up() { return 0; }
  all_nodes_proxmox() { return 0; }
  node_get_offline_count() { echo '0'; }
  any_nodes_running_tasks() { return 0; }
  apt_update_nodes() { :; }
  get_nodes_upgradeable() { :; }
  node_run_update_sequence() { echo "UPGRADE: $1"; }
  get_cluster_nodes() { echo 'pve1'; }
}

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

  Describe 'flow control' do
    # Each It calls install_main_happy_path_stubs (file-scope helper),
    # then overrides specific stubs to drive the branch under test.

    It 'logs dry run warning when dry_run is true' do
      install_main_happy_path_stubs
      When run main '--cluster-node' 'pve1' '--dry-run'
      The status should be success
      The error should include 'dry run mode'
    End

    It 'exits with error when the cluster_node is down' do
      install_main_happy_path_stubs
      is_node_up() { return 1; }
      When run main '--cluster-node' 'pve1'
      The status should be failure
      The error should include 'node is currently down'
    End

    It 'exits with error when the cluster_node is not proxmox' do
      install_main_happy_path_stubs
      # is_node_proxmox logs "Node is not proxmox." itself via log_alert before
      # returning non-zero; main then exits 1 with no additional log line.
      is_node_proxmox() { log_alert "Node is not proxmox."; return 1; }
      When run main '--cluster-node' 'pve1'
      The status should be failure
      The error should include 'Node is not proxmox'
    End

    It 'exits with error when all_nodes_up fails after discovery' do
      install_main_happy_path_stubs
      all_nodes_up() { return 1; }
      When run main '--cluster-node' 'pve1'
      The status should be failure
      The error should include 'At least one node is currently down'
    End

    It 'exits with error when nodes fail the parallel proxmox check' do
      install_main_happy_path_stubs
      all_nodes_proxmox() { log_alert "Node is not proxmox"; return 1; }
      When run main '--cluster-node' 'pve1'
      The status should be failure
      The error should include 'Node is not proxmox'
    End

    It 'exits with error when at least one node is offline' do
      install_main_happy_path_stubs
      node_get_offline_count() { echo '1'; }
      When run main '--cluster-node' 'pve1'
      The status should be failure
      The error should include 'not online'
    End

    It 'exits with error when running tasks exist (default)' do
      install_main_happy_path_stubs
      any_nodes_running_tasks() { return 1; }
      When run main '--cluster-node' 'pve1'
      The status should be failure
      The error should include 'running tasks'
    End

    It 'skips the running-tasks check when allow_running_tasks is true' do
      install_main_happy_path_stubs
      any_nodes_running_tasks() { echo 'TASK_CHECK_RAN' >&2; return 1; }
      When run main '--cluster-node' 'pve1' '--allow-running-tasks'
      The status should be success
      The error should include 'Not checking for running cluster tasks'
      The error should not include 'TASK_CHECK_RAN'
    End

    It 'exits 0 when no nodes have updates and force_upgrade is false' do
      # get_nodes_upgradeable returns empty by default in the happy-path stubs.
      install_main_happy_path_stubs
      When run main '--cluster-node' 'pve1'
      The status should be success
      The error should include 'No nodes need updates'
    End

    It 'upgrades every cluster node when --force-upgrade is set' do
      install_main_happy_path_stubs
      get_cluster_nodes() { printf '%s\n' pveA pveB pveC; }
      node_get_running_guest_count() { echo '0'; }  # for the sort step

      When run main '--cluster-node' 'pve1' '--force-upgrade'
      The status should be success
      The error should include 'Forcing upgrade'
      The output should include 'UPGRADE: pveA'
      The output should include 'UPGRADE: pveB'
      The output should include 'UPGRADE: pveC'
    End

    It 'uses cluster_nodes as-is when --node is passed instead of --cluster-node' do
      install_main_happy_path_stubs
      get_cluster_nodes() { echo 'should-not-be-called' >&2; }

      When run main '--node' 'pve1'
      The status should be success
      The error should include 'No nodes need updates'
      The error should not include 'should-not-be-called'
    End

    It 'logs warning when --no-maintenance-mode is set' do
      install_main_happy_path_stubs
      When run main '--cluster-node' 'pve1' '--no-maintenance-mode' '--force-upgrade'
      The status should be success
      The error should include 'Not using maintenance mode'
      The output should include 'UPGRADE: pve1'
    End
  End

  Describe 'reboot-only mode' do
    pass_health_checks_reboot_only() {
      is_node_up() { return 0; }
      is_node_proxmox() { return 0; }
      all_nodes_up() { return 0; }
      all_nodes_proxmox() { return 0; }
      node_get_offline_count() { echo '0'; }
      any_nodes_running_tasks() { return 0; }
      node_run_update_sequence() { echo "RUN: $1"; }
      get_cluster_nodes() { printf '%s\n' pveA pveB pveC; }
    }

    It 'skips apt_update_nodes when --reboot-only is set' do
      pass_health_checks_reboot_only
      apt_update_nodes() { echo 'apt_update_nodes-called' >&2; }
      node_needs_reboot() { return 1; }   # nobody needs reboot → upgrade_nodes empty → exit 0

      When run main '--cluster-node' 'pve1' '--reboot-only'
      The status should be success
      The error should include 'Reboot-only mode'
      The error should not include 'apt_update_nodes-called'
    End

    It 'populates upgrade_nodes from get_nodes_needing_reboot' do
      pass_health_checks_reboot_only
      apt_update_nodes() { :; }
      node_needs_reboot() {
        case "$1" in
          pveA) return 0 ;;
          pveB) return 1 ;;
          pveC) return 0 ;;
        esac
      }
      # The sort step runs on the filtered upgrade_nodes; mock its dependency.
      node_get_running_guest_count() { echo '0'; }

      When run main '--cluster-node' 'pve1' '--reboot-only'
      The status should be success
      The output should include 'RUN: pveA'
      The output should include 'RUN: pveC'
      The output should not include 'RUN: pveB'
      The error should include 'Reboot-only mode'
    End

    It 'exits 0 when no node needs a reboot' do
      pass_health_checks_reboot_only
      apt_update_nodes() { :; }
      node_needs_reboot() { return 1; }

      When run main '--cluster-node' 'pve1' '--reboot-only'
      The status should be success
      The error should include 'No nodes need updates'
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

    It 'skips the sort when upgrade_nodes has a single element' do
      pass_health_checks
      get_cluster_nodes() { printf '%s\n' soloN; }
      node_has_updates() { return 0; }
      node_get_running_guest_count() { echo 'SORT-RAN' >&2; echo '0'; }

      When run main '--cluster-node' 'pve1'
      The status should be success
      The line 1 of output should eq 'RUN: soloN'
      The error should not include 'SORT-RAN'
      The error should not include 'Reordering upgrade sequence'
    End
  End
End
