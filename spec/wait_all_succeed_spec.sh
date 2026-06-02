Describe 'wait_all_succeed'
  Include proxmox-upgrade-cluster.sh

  It 'returns exit code 0 when all jobs succeed' do
    local_jobs_succeed() { return 0; }
    test_array=("a" "b" "c")

    When call wait_all_succeed local_jobs_succeed test_array
    The status should equal 0
  End

  It 'returns exit code 1 when one job fails' do
    verbose=1
    fail_job() { [[ "$1" == "b" ]] && return 1; return 0; }
    fail_array=("a" "b" "c")

    When call wait_all_succeed fail_job fail_array
    The status should equal 1
    The error should include 'Job Error'
  End

  It 'returns exit code equal to number of failed jobs' do
    verbose=1
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
    verbose=1
    single_fail() { return 1; }
    single_array=("x")

    When call wait_all_succeed single_fail single_array
    The status should equal 1
    The error should include 'Job Error'
  End

  Describe 'verbose >= 4 includes PID in LOG_PREFIX' do
    # The child writes its $LOG_PREFIX to a temp file. The test driver then
    # echoes those contents as its stdout and applies normal stdout matchers.
    drive() {
      local verbose_level=${1?}
      local outer_prefix=${2?}
      _pid_file=$(mktemp)
      report_pid() { echo "$LOG_PREFIX" > "$_pid_file"; }
      job_array=("solo")
      verbose=$verbose_level
      LOG_PREFIX="$outer_prefix"
      wait_all_succeed report_pid job_array
      printf 'CHILD_PREFIX:%s\n' "$(cat "$_pid_file")"
      rm -f "$_pid_file"
    }

    It "tags the child's LOG_PREFIX with the child's own BASHPID" do
      When call drive 4 ''
      The status should be success
      The error should include 'Started Job'
      The line 1 of output should start with 'CHILD_PREFIX:['
    End

    It "uses BASHPID equal to the parent's \$! (matching pids[] key)" do
      # The driver compares the parent's view of $! (from the Finished Job
      # stderr line) against the child's own BASHPID (written to a temp
      # file). They must match — that's the whole point of the subshell
      # wrap.
      drive_compare() {
        _pid_file=$(mktemp)
        _err_file=$(mktemp)
        report_pid() { echo "$LOG_PREFIX" > "$_pid_file"; }
        job_array=("solo")
        verbose=4
        LOG_PREFIX=""
        wait_all_succeed report_pid job_array 2> "$_err_file"

        child_prefix="$(cat "$_pid_file")"
        child_pid="${child_prefix#[}"
        child_pid="${child_pid%%]*}"

        # The parent logs "[<pid>][wait_all_succeed] Finished Job: …".
        if grep -q "\[$child_pid\]\[wait_all_succeed\] Finished Job" "$_err_file"; then
          echo 'MATCH'
        else
          echo "NO MATCH: child_pid=$child_pid"
          echo '--- stderr ---'
          cat "$_err_file"
        fi
        rm -f "$_pid_file" "$_err_file"
      }

      When call drive_compare
      The output should eq 'MATCH'
    End

    It "omits BASHPID from LOG_PREFIX when verbose < 4" do
      When call drive 3 ''
      The status should be success
      The line 1 of output should eq 'CHILD_PREFIX:'
    End

    It "preserves an outer LOG_PREFIX alongside the BASHPID tag" do
      When call drive 4 '[outer]'
      The status should be success
      The error should include '[outer]'
      The line 1 of output should start with 'CHILD_PREFIX:['
      The line 1 of output should end with '][outer]'
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
