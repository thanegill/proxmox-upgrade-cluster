# Print each element of the named array, one per line, bracketed so
# whitespace boundaries are visible. Use when verifying that an
# accumulator-style flag (--ssh-opt, --node, --pkg-reinstall, ...)
# populates the real script-level array correctly through process_args.
# Arrays don't persist back to the test from a `When call` subprocess,
# so the verification has to happen inside the same wrapped function.
capture_array() {
  local -n arr=$1
  shift
  process_args "$@"
  printf '[%s]\n' "${arr[@]}"
}

Describe 'error_on_no_arg'
  Include proxmox-upgrade-cluster.sh

  It 'exits with error when value is empty' do
    When run error_on_no_arg '--test' ''
    The status should be failure
    The error should include "No arg passed"
  End

  It 'exits with error when value is not provided' do
    When run error_on_no_arg '--test'
    The status should be failure
    The error should include "No arg passed"
  End

  It 'exits with error when the next token is a long flag' do
    When run error_on_no_arg '--node' '--dry-run'
    The status should be failure
    The error should include "requires a value, got flag '--dry-run'"
  End

  It 'exits with error when the next token is a short flag' do
    When run error_on_no_arg '--node' '-n'
    The status should be failure
    The error should include "requires a value, got flag '-n'"
  End

  It 'accepts a value that starts with a letter' do
    When run error_on_no_arg '--node' 'pve1'
    The status should be success
  End

  It 'accepts a dash-prefixed value when allow_dash is true' do
    When run error_on_no_arg '--ssh-opt' '-o StrictHostKeyChecking=no' true
    The status should be success
  End

  It 'still rejects an empty value even when allow_dash is true' do
    When run error_on_no_arg '--ssh-opt' '' true
    The status should be failure
    The error should include "No arg passed"
  End
End

Describe 'process_args rejects flag-as-value through error_on_no_arg'
  Include proxmox-upgrade-cluster.sh

  It 'rejects --node followed by another flag' do
    verbose=1
    When run process_args '--node' '--dry-run'
    The status should be failure
    The error should include "requires a value, got flag '--dry-run'"
  End

  It 'rejects --cluster-node followed by -n' do
    verbose=1
    When run process_args '--cluster-node' '-n' 'pve1'
    The status should be failure
    The error should include "requires a value, got flag '-n'"
  End
End

Describe 'process_args missing-value rejections through error_on_no_arg'
  Include proxmox-upgrade-cluster.sh

  # Each value-taking flag should call error_on_no_arg and exit with
  # "No arg passed" when nothing follows it. Parameterise — the only
  # variation is the flag itself.
  Parameters
    --cluster-node
    --node
    --ssh-user
    --ssh-opt
    --pkg-reinstall
    --reboot-timeout
  End

  It "$1 exits with error when no value follows" do
    verbose=1
    When run process_args "$1"
    The status should be failure
    The error should include 'No arg passed'
  End
End

Describe 'process_args --cluster-node'
  Include proxmox-upgrade-cluster.sh

  It 'sets cluster_node variable' do
    When call process_args '--cluster-node' 'pve1'
    The variable cluster_node should eq 'pve1'
  End

  It 'accepts -c shorthand' do
    When call process_args '-c' 'pve1'
    The variable cluster_node should eq 'pve1'
  End
End

Describe 'process_args --node'
  Include proxmox-upgrade-cluster.sh

  It 'appends each --node value to cluster_nodes' do
    When call capture_array cluster_nodes '--node' 'pve2' '--node' 'pve3'
    The line 1 of output should eq '[pve2]'
    The line 2 of output should eq '[pve3]'
    The lines of output should eq 2
  End

  It 'accepts -n shorthand and preserves order' do
    When call capture_array cluster_nodes '-n' 'pveB' '-n' 'pveA' '-n' 'pveC'
    The line 1 of output should eq '[pveB]'
    The line 2 of output should eq '[pveA]'
    The line 3 of output should eq '[pveC]'
    The lines of output should eq 3
  End

  It 'accepts mixed long and short forms' do
    When call capture_array cluster_nodes '-n' 'pve1' '--node' 'pve2'
    The line 1 of output should eq '[pve1]'
    The line 2 of output should eq '[pve2]'
    The lines of output should eq 2
  End
End

Describe 'process_args --ssh-user'
  Include proxmox-upgrade-cluster.sh

  It 'sets ssh_user variable' do
    When call process_args '--cluster-node' 'pve1' '--ssh-user' 'admin'
    The variable ssh_user should eq 'admin'
  End

  It 'accepts -u shorthand' do
    When call process_args '--cluster-node' 'pve1' '-u' 'admin'
    The variable ssh_user should eq 'admin'
  End
End

Describe 'process_args --ssh-opt'
  Include proxmox-upgrade-cluster.sh

  It 'appends the value to ssh_options as a single token' do
    When call capture_array ssh_options '--cluster-node' 'pve1' '--ssh-opt' '-o StrictHostKeyChecking=no'
    The output should include '[-o StrictHostKeyChecking=no]'
  End

  It 'accepts -o shorthand' do
    When call capture_array ssh_options '--cluster-node' 'pve1' '-o' '-o StrictHostKeyChecking=no'
    The output should include '[-o StrictHostKeyChecking=no]'
  End
End

Describe 'process_args boolean flags'
  Include proxmox-upgrade-cluster.sh

  # (flag, variable, value-after-set). Defaults are covered by
  # variables_spec.sh — only the "flag flips variable" direction lives here.
  Parameters
    --ssh-allow-password-auth   ssh_key_auth_only        false
    --cluster-node-use-ip       cluster_node_use_ip      true
    --dry-run                   dry_run                  true
    --force-upgrade             force_upgrade            true
    --force-reboot              force_reboot             true
    --skip-reboot               skip_reboot              true
    --no-maintenance-mode       use_maintenance_mode     false
    --allow-running-guests      allow_running_guests     true
    --allow-running-tasks       allow_running_tasks      true
    --preserve-discovery-order  preserve_discovery_order true
  End

  It "$1 sets $2 to $3" do
    When call process_args '--cluster-node' 'pve1' "$1"
    The variable "$2" should eq "$3"
  End
End

Describe 'process_args --skip-reboot mutex with --force-reboot'
  Include proxmox-upgrade-cluster.sh

  It 'exits with error when --skip-reboot precedes --force-reboot' do
    verbose=1
    When run process_args '--cluster-node' 'pve1' '--skip-reboot' '--force-reboot'
    The status should be failure
    The error should include '--force-reboot and --skip-reboot cannot be used together'
  End

  It 'exits with error when --force-reboot precedes --skip-reboot' do
    verbose=1
    When run process_args '--cluster-node' 'pve1' '--force-reboot' '--skip-reboot'
    The status should be failure
    The error should include '--force-reboot and --skip-reboot cannot be used together'
  End
End

Describe 'process_args --pkg-reinstall'
  Include proxmox-upgrade-cluster.sh

  It 'appends a single package to pkgs_reinstall' do
    When call capture_array pkgs_reinstall '--cluster-node' 'pve1' '--pkg-reinstall' 'pve-firmware'
    The output should eq '[pve-firmware]'
  End

  It 'accumulates multiple --pkg-reinstall flags in order' do
    When call capture_array pkgs_reinstall '--cluster-node' 'pve1' '--pkg-reinstall' 'pve-firmware' '--pkg-reinstall' 'pve-kernel'
    The line 1 of output should eq '[pve-firmware]'
    The line 2 of output should eq '[pve-kernel]'
    The lines of output should eq 2
  End
End

Describe 'process_args --jq-bin (removed)'
  Include proxmox-upgrade-cluster.sh

  It 'rejects --jq-bin as an unknown option' do
    verbose=1
    When run process_args '--cluster-node' 'pve1' '--jq-bin' '/usr/local/bin/jq'
    The status should be failure
    The error should include "unknown option '--jq-bin'"
  End
End

Describe 'process_args --reboot-timeout'
  Include proxmox-upgrade-cluster.sh

  It 'overrides the default reboot_timeout' do
    When call process_args '--cluster-node' 'pve1' '--reboot-timeout' '120'
    The variable reboot_timeout should eq 120
  End

  It 'defaults to 900 seconds when not passed' do
    When call process_args '--cluster-node' 'pve1'
    The variable reboot_timeout should eq 900
  End

  # "exits with error when no value is provided" is covered by the
  # parameterized "missing-value rejections" block below.
End

Describe 'process_args --verbose'
  Include proxmox-upgrade-cluster.sh

  It 'increments verbose by 1 for each -v' do
    When call process_args '--cluster-node' 'pve1' '-v' '-v' '-v'
    The variable verbose should eq 3
  End

  It 'increments verbose by 1 for each --verbose' do
    When call process_args '--cluster-node' 'pve1' '--verbose' '--verbose'
    The variable verbose should eq 2
  End

  It 'handles the bare -v form' do
    When call process_args '--cluster-node' 'pve1' '-v'
    The variable verbose should eq 1
  End

  It 'handles the combined -vv form' do
    When call process_args '--cluster-node' 'pve1' '-vv'
    The variable verbose should eq 2
  End

  It 'handles the combined -vvv form' do
    When call process_args '--cluster-node' 'pve1' '-vvv'
    The variable verbose should eq 3
  End

  It 'composes separate -v flags and combined -vv forms' do
    When call process_args '--cluster-node' 'pve1' '-v' '-vv'
    The variable verbose should eq 3
  End

  It 'composes --verbose and -vv' do
    When call process_args '--cluster-node' 'pve1' '--verbose' '-vv'
    The variable verbose should eq 3
  End

  It 'rejects unknown flags with embedded v (e.g. -vc)' do
    # `-vc` shouldn't match the `-+(v)` extglob (it requires v's only);
    # falls through to the unknown-option branch.
    verbose=1
    When run process_args '-vc' 'pve1'
    The status should be failure
    The error should include "unknown option '-vc'"
  End

  It 'adds -v to ssh_options when verbose reaches 5' do
    # Note: not testing verbose>=6 (enables `set -x` globally and pollutes
    # the test process) or verbose>=7 (also reachable but inherits the
    # set -x problem). One -v added at verbose=5 is enough to verify the
    # ssh-verbosity wiring.
    When call capture_array ssh_options '--cluster-node' 'pve1' '-vvvvv'
    The output should include '[-v]'
  End
End

Describe 'process_args error cases'
  Include proxmox-upgrade-cluster.sh

  It 'exits with error when no arguments provided' do
    verbose=1
    When run process_args
    The status should be failure
    The output should include 'NAME'
    The error should include 'No arguments passed'
  End

  It 'exits with error when unknown option provided' do
    verbose=1
    When run process_args '--cluster-node' 'pve1' '--unknown-option'
    The status should be failure
    The error should include 'unknown option'
  End

  It 'exits with error when --cluster-node precedes --node' do
    verbose=1
    When run process_args '--cluster-node' 'pve1' '--node' 'pve2'
    The status should be failure
    The error should include 'Only one of'
  End

  It 'exits with error when --node precedes --cluster-node' do
    verbose=1
    When run process_args '--node' 'pve1' '--cluster-node' 'pve2'
    The status should be failure
    The error should include 'Only one of'
  End

  It 'exits with error when neither --cluster-node nor --node is passed' do
    verbose=1
    When run process_args '--dry-run'
    The status should be failure
    The error should include 'One of --cluster-node, or --nodes must be used'
  End
End

Describe 'process_args ssh_options setup'
  Include proxmox-upgrade-cluster.sh

  It 'stores -l and ssh_user as separate ssh_options tokens' do
    When call capture_array ssh_options '--cluster-node' 'pve1'
    The output should include '[-l]'
    The output should include '[root]'
  End

  It 'keeps ssh_user containing spaces as one token' do
    When call capture_array ssh_options '--cluster-node' 'pve1' '--ssh-user' 'user with space'
    The output should include '[-l]'
    The output should include '[user with space]'
  End

  It 'stores -o and PasswordAuthentication=no as separate ssh_options tokens' do
    When call capture_array ssh_options '--cluster-node' 'pve1'
    The output should include '[-o]'
    The output should include '[PasswordAuthentication=no]'
  End

  It 'does not add PasswordAuthentication=no when ssh_key_auth_only is false' do
    When call capture_array ssh_options '--cluster-node' 'pve1' '--ssh-allow-password-auth'
    The output should not include '[PasswordAuthentication=no]'
  End

  It 'accumulates multiple --ssh-opt flags as distinct tokens, each containing the literal value' do
    When call capture_array ssh_options '--cluster-node' 'pve1' '--ssh-opt' '-o StrictHostKeyChecking=no' '--ssh-opt' '-o IdentityFile=/key'
    The output should include '[-o StrictHostKeyChecking=no]'
    The output should include '[-o IdentityFile=/key]'
  End
End

Describe 'node_ssh passes ssh_options as distinct argv elements'
  Include proxmox-upgrade-cluster.sh

  It 'preserves ssh_options token boundaries when invoking local_ssh' do
    local_ssh() { printf '[%s]\n' "$@"; }
    ssh_options=(-l 'user with space' -o 'PasswordAuthentication=no')
    When call node_ssh 'pve1' 'whoami'
    The output should include '[pve1]'
    The output should include '[-l]'
    The output should include '[user with space]'
    The output should include '[-o]'
    The output should include '[PasswordAuthentication=no]'
    The output should include '[whoami]'
  End

  It 'forwards extra ssh args from caller without word-splitting' do
    local_ssh() { printf '[%s]\n' "$@"; }
    ssh_options=()
    When call node_ssh 'pve1' 'whoami' '-oConnectTimeout=5'
    The output should include '[pve1]'
    The output should include '[-oConnectTimeout=5]'
    The output should include '[whoami]'
  End
End
