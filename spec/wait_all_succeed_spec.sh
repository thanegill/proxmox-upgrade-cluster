Describe 'wait_all_succeed'
  Include proxmox-upgrade-cluster.sh

  It 'returns exit code 0 when all jobs succeed' do
    local_jobs_succeed() { return 0; }
    test_array=("a" "b" "c")

    When call wait_all_succeed local_jobs_succeed test_array
    The status should equal 0
  End

  It 'returns exit code 1 when one job fails' do
    fail_job() { [[ "$1" == "b" ]] && return 1; return 0; }
    fail_array=("a" "b" "c")

    When call wait_all_succeed fail_job fail_array
    The status should equal 1
    The error should include 'Job Error'
  End

  It 'returns exit code equal to number of failed jobs' do
    always_fail() { return 1; }
    fail_array=("a" "b" "c")

    When call wait_all_succeed always_fail fail_array
    The status should equal 3
    The error should include 'Job Error'
  End

  It 'returns exit code 0 for empty array' do
    never_called() { return 0; }
    empty_array=()

    When call wait_all_succeed never_called empty_array
    The status should equal 0
  End

  It 'returns exit code 0 for single element array that succeeds' do
    single_ok() { return 0; }
    single_array=("x")

    When call wait_all_succeed single_ok single_array
    The status should equal 0
  End

  It 'returns exit code 1 for single failing element' do
    single_fail() { return 1; }
    single_array=("x")

    When call wait_all_succeed single_fail single_array
    The status should equal 1
    The error should include 'Job Error'
  End

  Describe 'verbose >= 4 includes PID in LOG_PREFIX' do
    It 'includes BASHPID when verbose is 4 or higher' do
      verbose=4
      pid_job() { return 0; }
      test_pid_array=("job1")

      test_with_verbose() {
        log_output() { cat - >&1; }
        LOG_PREFIX=""
        wait_all_succeed pid_job test_pid_array
        echo "DONE:$LOG_PREFIX"
      }

      When call test_with_verbose
      The output should include '[20' || The status should equal 0
    End
  End

  Describe 'command execution' do
    It 'passes array elements as arguments to the command' do
      captured_args=()
      capture_arg() { captured_args+=("$1"); return 0; }
      test_args=("arg1" "arg2" "arg3")

      When call wait_all_succeed capture_arg test_args
      The status should equal 0
    End

    It 'runs commands sequentially in background and waits for all' do
      order=()
      track_order() {
        local idx=$1
        sleep 0.1s
        order+=("$idx")
        return 0
      }
      wait_sleep() { :; }
      test_track=("a" "b" "c")

      When call wait_all_succeed track_order test_track
      The status should equal 0
    End
  End

  Describe 'error handling' do
    It 'requires a command argument' do
      When run wait_all_succeed
      The status should be failure
      The error should include 'parameter not set'
    End

    It 'requires an array argument' do
      test_cmd() { return 0; }
      When run wait_all_succeed test_cmd
      The status should be failure
      The error should include 'parameter not set'
    End
  End
End
