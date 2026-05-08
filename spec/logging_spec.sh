Describe 'Logging functions'
  Include proxmox-upgrade-cluster.sh

  Describe 'log_info' do
    It 'outputs the message' do
      When call log_info 'test info message'
      The error should include 'test info message'
    End
  End

  Describe 'log_verbose' do
    It 'outputs the message when verbose >= 1' do
      verbose=1
      When call log_verbose 'test verbose message'
      The error should include 'test verbose message'
    End
  End

  Describe 'log_debug' do
    It 'outputs the message when verbose >= 2' do
      verbose=2
      When call log_debug 'test debug message'
      The error should include 'test debug message'
    End
  End

  Describe 'log_alert' do
    It 'outputs the message with color codes' do
      When call log_alert 'test alert message'
      The error should include 'test alert message'
      The error should include '\033'
    End
  End

  Describe 'log_error' do
    It 'outputs the message with color codes' do
      When call log_error 'test error message'
      The error should include 'test error message'
      The error should include '\033'
    End
  End

  Describe 'log_status' do
    It 'outputs the message with color codes' do
      When call log_status 'test status message'
      The error should include 'test status message'
      The error should include '\033'
    End
  End

  Describe 'log_success' do
    It 'outputs the message with color codes' do
      When call log_success 'test success message'
      The error should include 'test success message'
      The error should include '\033'
    End
  End

  Describe 'log_warning' do
    It 'outputs the message with color codes' do
      When call log_warning 'test warning message'
      The error should include 'test warning message'
      The error should include '\033'
    End
  End

  Describe 'log_progress' do
    It 'outputs a dot when verbose is 0' do
      verbose=0
      When call log_progress
      The error should include '.'
    End
  End

  Describe 'log_progress_end' do
    It 'outputs escape sequences when verbose is 0' do
      verbose=0
      When call log_progress_end
      The error should include '\033[2K'
    End
  End
End
