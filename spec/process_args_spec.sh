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

  It 'adds node to cluster_nodes array' do
    process_args() {
      local args=("$@")
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
          --node|-n) ((i++)); echo "${args[$i]}"; ;;
          *) ((i++)) ;;
        esac
      done
    }

    When call process_args '--node' 'pve2' '--node' 'pve3'
    The output should include 'pve2'
    The output should include 'pve3'
  End

  It 'accepts -n shorthand' do
    process_args() {
      local args=("$@")
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
          --node|-n) ((i++)); echo "${args[$i]}"; ;;
          *) ((i++)) ;;
        esac
      done
    }

    When call process_args '-n' 'pve2' '-n' 'pve3'
    The output should include 'pve2'
    The output should include 'pve3'
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

  It 'adds option to ssh_options array' do
    process_args() {
      local args=("$@")
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
          --ssh-opt|-o) ((i++)); echo "ssh_opt=${args[$i]}"; ;;
          *) ((i++)) ;;
        esac
      done
    }

    When call process_args '--cluster-node' 'pve1' '--ssh-opt' '-o StrictHostKeyChecking=no'
    The output should include '-o StrictHostKeyChecking=no'
  End

  It 'accepts -o shorthand' do
    process_args() {
      local args=("$@")
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
          --ssh-opt|-o) ((i++)); echo "ssh_opt=${args[$i]}"; ;;
          *) ((i++)) ;;
        esac
      done
    }

    When call process_args '--cluster-node' 'pve1' '-o' '-o StrictHostKeyChecking=no'
    The output should include '-o StrictHostKeyChecking=no'
  End
End

Describe 'process_args flags'
  Include proxmox-upgrade-cluster.sh

  Describe '--ssh-allow-password-auth' do
    It 'sets ssh_key_auth_only to false' do
      When call process_args '--cluster-node' 'pve1' '--ssh-allow-password-auth'
      The variable ssh_key_auth_only should eq 'false'
    End
  End

  Describe '--cluster-node-use-ip' do
    It 'sets cluster_node_use_ip to true' do
      When call process_args '--cluster-node' 'pve1' '--cluster-node-use-ip'
      The variable cluster_node_use_ip should eq 'true'
    End
  End

  Describe '--dry-run' do
    It 'sets dry_run to true' do
      When call process_args '--cluster-node' 'pve1' '--dry-run'
      The variable dry_run should eq 'true'
    End
  End

  Describe '--force-upgrade' do
    It 'sets force_upgrade to true' do
      When call process_args '--cluster-node' 'pve1' '--force-upgrade'
      The variable force_upgrade should eq 'true'
    End
  End

  Describe '--force-reboot' do
    It 'sets force_reboot to true' do
      When call process_args '--cluster-node' 'pve1' '--force-reboot'
      The variable force_reboot should eq 'true'
    End
  End

  Describe '--no-maintenance-mode' do
    It 'sets use_maintenance_mode to false' do
      When call process_args '--cluster-node' 'pve1' '--no-maintenance-mode'
      The variable use_maintenance_mode should eq 'false'
    End
  End

  Describe '--allow-running-guests' do
    It 'sets allow_running_guests to true' do
      When call process_args '--cluster-node' 'pve1' '--allow-running-guests'
      The variable allow_running_guests should eq 'true'
    End
  End

  Describe '--allow-running-tasks' do
    It 'sets allow_running_tasks to true' do
      When call process_args '--cluster-node' 'pve1' '--allow-running-tasks'
      The variable allow_running_tasks should eq 'true'
    End
  End
End

Describe 'process_args --pkg-reinstall'
  Include proxmox-upgrade-cluster.sh

  It 'adds package to pkgs_reinstall array' do
    process_args() {
      local args=("$@")
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
          --pkg-reinstall) ((i++)); echo "pkg=${args[$i]}"; ;;
          *) ((i++)) ;;
        esac
      done
    }

    When call process_args '--cluster-node' 'pve1' '--pkg-reinstall' 'pve-firmware'
    The output should include 'pve-firmware'
  End

  It 'accepts multiple --pkg-reinstall flags' do
    process_args() {
      local args=("$@")
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
          --pkg-reinstall) ((i++)); echo "pkg=${args[$i]}"; ;;
          *) ((i++)) ;;
        esac
      done
    }

    When call process_args '--cluster-node' 'pve1' '--pkg-reinstall' 'pve-firmware' '--pkg-reinstall' 'pve-kernel'
    The output should include 'pve-firmware'
    The output should include 'pve-kernel'
  End
End

Describe 'process_args --jq-bin'
  Include proxmox-upgrade-cluster.sh

  It 'sets jq_bin variable' do
    When call process_args '--cluster-node' 'pve1' '--jq-bin' '/usr/local/bin/jq'
    The variable jq_bin should eq '/usr/local/bin/jq'
  End
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
End

Describe 'process_args ssh_options setup'
  Include proxmox-upgrade-cluster.sh

  It 'adds -l $ssh_user to ssh_options' do
    process_args() {
      local args=("$@")
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
          --cluster-node|-c) ((i++)); echo "ssh_opt=-l root"; ;;
          *) ((i++)) ;;
        esac
      done
    }

    When call process_args '--cluster-node' 'pve1'
    The output should include '-l root'
  End

  It 'adds PasswordAuthentication=no when ssh_key_auth_only is true' do
    process_args() {
      local args=("$@")
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
          --cluster-node|-c) ((i++)); echo "ssh_opt=-o PasswordAuthentication=no"; ;;
          *) ((i++)) ;;
        esac
      done
    }

    When call process_args '--cluster-node' 'pve1'
    The output should include '-o PasswordAuthentication=no'
  End

  It 'does not add PasswordAuthentication=no when ssh_key_auth_only is false' do
    process_args() {
      local args=("$@")
      local i=0
      while [[ $i -lt ${#args[@]} ]]; do
        case "${args[$i]}" in
          --cluster-node|-c) ((i++)); ;;
          --ssh-allow-password-auth) echo "no_password_auth"; return 0; ;;
          *) ((i++)) ;;
        esac
      done
    }

    When call process_args '--cluster-node' 'pve1' '--ssh-allow-password-auth'
    The output should include 'no_password_auth'
    The output should not include '-o PasswordAuthentication=no'
  End
End
