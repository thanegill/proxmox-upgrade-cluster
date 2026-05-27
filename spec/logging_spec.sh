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
      The error should include $'\033'
    End
  End

  Describe 'log_error' do
    It 'outputs the message with color codes' do
      When call log_error 'test error message'
      The error should include 'test error message'
      The error should include $'\033'
    End
  End

  Describe 'log_status' do
    It 'outputs the message with color codes' do
      When call log_status 'test status message'
      The error should include 'test status message'
      The error should include $'\033'
    End
  End

  Describe 'log_success' do
    It 'outputs the message with color codes' do
      When call log_success 'test success message'
      The error should include 'test success message'
      The error should include $'\033'
    End
  End

  Describe 'log_warning' do
    It 'outputs the message with color codes' do
      When call log_warning 'test warning message'
      The error should include 'test warning message'
      The error should include $'\033'
    End
  End

  Describe 'log_progress' do
    It 'outputs a dot when verbose is 0' do
      verbose=0
      wait_sleep() { :; }
      When call log_progress '1s'
      The error should include '.'
    End

    It 'requires a duration argument' do
      When run log_progress
      The status should be failure
      The error should include 'parameter not set'
    End
  End

  Describe 'log_progress_end' do
    It 'outputs escape sequences when verbose is 0' do
      verbose=0
      When call log_progress_end
      The error should include $'\033'
    End
  End

  Describe 'log_color' do
    It 'outputs the message with ANSI color codes (red=31)' do
      When call log_color 31 'red text'
      The error should include 'red text'
      The error should include $'\033[0;31m'
      The error should include $'\033[0m'
    End

    It 'outputs the message with ANSI color codes (green=32)' do
      When call log_color 32 'green text'
      The error should include 'green text'
      The error should include $'\033[0;32m'
    End

    It 'calls log_level 0 internally' do
      verbose=-1
      Mock log_level
        echo "log_level_called_with: $@"
      End
      When call log_color 35 'purple text'
      The output should include 'log_level_called_with:'
    End
  End

  Describe 'log_level' do
    It 'outputs message when verbose >= level' do
      verbose=2
      Mock local_ssh
        exit 0
      End
      When call log_level 1 'level one message'
      The error should include 'level one message'
    End

    It 'silences output when verbose < level' do
      verbose=0
      When call log_level 2 'hidden message'
      The output should eq ''
    End

    It 'outputs to stderr via log_pipe_level' do
      verbose=1
      Mock local_ssh
        exit 0
      End
      When call log_level 0 'level zero message'
      The error should include 'level zero message'
    End

    It 'requires a level argument' do
      When run log_level
      The status should be failure
      The error should include 'parameter not set'
    End
  End

  Describe 'log_pipe_level' do
    It 'passes through lines when verbose >= level' do
      test_lpl() { echo "input line" | log_pipe_level 0; }
      When call test_lpl
      The error should include 'input line'
    End

    It 'filters out lines when verbose < level' do
      test_filter() { verbose=0; echo "filtered" | log_pipe_level 1; }
      When call test_filter
      The output should eq ''
      The error should not include 'filtered'
    End

    It 'adds level name prefix when verbose >= level' do
      test_level() { verbose=2; echo "test" | log_pipe_level 2; }
      When call test_level
      The error should include '[DEBUG'
    End

    It 'logs with timestamp for verbose >= 3 level 3' do
      test_ts() { verbose=3; echo "test" | log_pipe_level 3; }
      When call test_ts
      The error should include '[20'
      The error should include '[DEBUG'
    End

    It 'skips empty lines' do
      test_empty() { verbose=1; printf "line1\n\nline2\n" | log_pipe_level 0; }
      When call test_empty
      The error should include 'line1'
      The error should include 'line2'
    End
  End

  Describe 'log_debug2' do
    It 'outputs message when verbose >= 3' do
      verbose=3
      When call log_debug2 'debug2 message'
      The error should include 'debug2 message'
      The error should include '[DEBUG2'
    End

    It 'silences output when verbose < 3' do
      verbose=2
      When call log_debug2 'hidden debug2'
      The output should eq ''
    End
  End

  Describe 'log_debug3' do
    It 'outputs message when verbose >= 4' do
      verbose=4
      When call log_debug3 'debug3 message'
      The error should include 'debug3 message'
      The error should include '[DEBUG3'
    End

    It 'silences output when verbose < 4' do
      verbose=3
      When call log_debug3 'hidden debug3'
      The output should eq ''
    End
  End

  Describe 'log_pipe_level with prefix_arg' do
    It 'uses custom prefix when provided' do
      test_prefix() { echo "test data" | log_pipe_level 0 "myprefix"; }
      When call test_prefix
      The error should include 'myprefix'
      The error should include 'test data'
    End

    It 'uses fallback level number when verbose level not in map' do
      test_fallback() { verbose=9; echo "fallback" | log_pipe_level 9; }
      When call test_fallback
      The error should include '[9]'
      The error should include 'fallback'
    End
  End

  Describe 'log_prefix with no chained function' do
    It 'still appends to LOG_PREFIX when called without additional args' do
      test_no_chain() {
        LOG_PREFIX=""
        log_prefix "solo"
        echo "$LOG_PREFIX"
      }
      When call test_no_chain
      The output should include '[solo]'
    End
  End

  Describe 'log_prefix' do
    It 'appends prefix to LOG_PREFIX and chains to next function' do
      local captured=""
      capture_log() { captured="$LOG_PREFIX"; }
      test_chain() { LOG_PREFIX=""; log_prefix "node1" capture_log; echo "$captured"; }
      When call test_chain
      The output should include '[node1]'
    End

    It 'accumulates multiple chained prefixes' do
      local captured=""
      capture_log() { captured="$LOG_PREFIX"; }
      test_accumulate() { LOG_PREFIX=""; log_prefix "first" log_prefix "second" capture_log; echo "$captured"; }
      When call test_accumulate
      The output should include '[first]'
      The output should include '[second]'
    End

    It 'preserves existing LOG_PREFIX content' do
      local captured=""
      capture_log() { captured="$LOG_PREFIX"; }
      test_preserve() { LOG_PREFIX="[old]"; log_prefix "new" capture_log; echo "$captured"; }
      When call test_preserve
      The output should include '[old]'
    End

    It 'requires a prefix argument' do
      When run log_prefix
      The status should be failure
      The error should include 'parameter not set'
    End
  End
End
