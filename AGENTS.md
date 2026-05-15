# Testing with ShellSpec

## Running Tests

```bash
nix develop -c shellspec                    # All tests
nix develop -c shellspec spec/file_name.sh  # Specific test file
nix develop -c shellspec --dry-run          # List examples without running
```

## Test Structure

Tests use the ShellSpec DSL with these keywords (case-sensitive):
- `Describe` / `It` / `When` / `The` / `End` — always capitalized
- `do` and `End` must be on separate lines from `Describe`/`It`

```bash
Describe 'function_name' do
  Include proxmox-upgrade-cluster.sh

  It 'describes what the test checks' do
    When call function_name 'arg1' 'arg2'
    The output should include 'expected output'
    The status should be success
  End
End
```

### When call vs When run

|              | `call`          | `run`           | `run command`   |
|-------------|-----------------|-----------------|-----------------|
| Subshell    | No              | Yes             | Yes             |
| Target      | function        | function/cmd    | external cmd    |
| Exit codes  | Not caught      | Caught          | N/A             |
| Coverage    | Yes             | Yes (func only) | No              |

- `When call` — runs in a subprocess, captures stdout/stderr but variable changes are lost. Recommended for unit tests of shell functions.
- `When run` — runs the full command including exit codes, use for functions that exit or when you need to trap errors with `set -e`.
- `When run command` — explicitly runs an external command (not a shell function). The command does not have to be a shell script.

### Subjects and Modifiers

Subjects define what is being tested; modifiers refine the subject:

| Subject/Modifier | Syntax                                    | Description                    |
|------------------|-------------------------------------------|--------------------------------|
| `stdout`         | `The output should eq 'foo'`              | stdout of evaluation           |
| `stderr`         | `The error should include 'bar'`          | stderr of evaluation           |
| `status`         | `The status should be success`            | exit code (0 = success)        |
| `variable`       | `The variable dry_run should eq 'true'`   | value of a shell variable      |
| `line N`         | `The line 1 should eq 'first line'`       | specific line of stdout        |
| `lines`          | `The lines of output should eq 5`         | number of lines                |
| `word N`         | `The word 2 of output should eq 'bar'`    | specific word (space-delimited)|
| `length`         | `The length of variable arr should eq 3`  | length of string/array         |
| `contents`       | `The contents of file '/tmp/x.txt' should eq 'data'` | file contents as subject |

### Matchers

String matchers:

```bash
The output should equal 'exact match'        # or: should eq
The output should start with 'prefix'
The output should end with 'suffix'
The output should include 'substring'
The output should match pattern '[0-9]+'     # glob-style patterns (foo*, [a-z], foo|bar)
```

Variable matchers:

```bash
The variable VAR should be defined           # set (even if empty)
The variable VAR should be undefined         # unset
The variable VAR should be present           # non-zero length string
The variable VAR should be blank             # unset or zero-length
The variable VAR should be exported          # exported to child processes
The variable VAR should be readonly          # read-only variable
```

File stat matchers:

```bash
Path mypath=/tmp/data.txt                    # define path alias
The path mypath should exist
The path /tmp/file.sh should be executable
The path /tmp/dir should be directory
The path /tmp/empty.txt should be empty file
```

Custom matcher with `satisfy`:

```bash
is_positive() { test "$value" -gt 0; }      # $value holds the subject

When call echo '42'
The output should satisfy is_positive
```

### Skip, Pending, and Todo

```bash
Skip 'reason for skipping this block'        # skip entire Describe/It block

Skip if condition function arg1 arg2         # conditional skip

Pending 'feature not yet implemented'        # marks as pending (not a failure)

Todo                                           # marks example as todo
```

### Hooks

Hooks run automatically around examples:

```bash
Describe 'my tests' do
  Before do
    # Runs before each It block
    verbose=1
  End

  After do
    # Runs after each It block (cleanup)
    unset my_temp_var
  End

  BeforeCall do
    # Runs before each When call evaluation
  End

  AfterRun do
    # Runs after each When run evaluation
  End

  It 'example' do
    ...
  End
End
```

### Intercept (alternative to Mock)

`Intercept` can intercept external commands at any point during `When run source`:

```bash
Describe 'external command test' do
  Intercept node_pvesh                     # intercept this function

  It 'uses intercepted command' do
    When run source proxmox-upgrade-cluster.sh --cluster-node pve1
    The status should be success
  End
End
```

### %const Directive

Define constants at the top of a spec file:

```bash
% SSH_USER: 'root'
% LOG_LEVEL: 2

Describe 'tests using constants' do
  It 'uses constant value' do
    The variable ssh_user should eq "$SSH_USER"
  End
End
```

### Set Directive

Set shell options before each example:

```bash
Describe 'strict mode tests' do
  Set errexit:on nounset:on                # set -e -u before each example

  It 'example under strict mode' do
    ...
  End
End
```

## Testing Arrays and Variables

Arrays modified inside functions don't persist across subprocesses. Use inline overrides:

```bash
# WRONG - variable mutations don't survive When call subprocess
It 'adds node to cluster_nodes array' do
  When call process_args '--node' 'pve1'
  The length of variable cluster_nodes should eq 1  # FAILS: <unset>
End

# RIGHT - override the function and capture output
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

  When call process_args '--node' 'pve1'
  The output should include 'pve1'
End
```

## Mocking Functions

### Inline function overrides (preferred)

Override functions directly in the test body. This is more reliable than Mock directives:

```bash
It 'uses mocked node_pvesh' do
  node_pvesh() { echo '[{"type":"node","name":"pve1"}]'; }

  When call get_cluster_nodes 'pve1'
  The output should eq 'pve1'
End
```

### Mock blocks (for functions that write to stdout/stderr)

Use `Mock` with `exit` not `return` — Mock runs in a subshell:

```bash
It 'calls node_ssh_no_op with dist-upgrade command' do
  Mock node_ssh
    echo 'upgraded'
    exit 0
  End

  When call node_upgrade 'pve1'
  The error should include 'upgraded'
End
```

## Testing Log Output

Log functions write to stderr. Always add expectations for log messages:

```bash
It 'logs debug message when verbose is set' do
  verbose=2
  Mock local_ssh
    echo 'command executed'
    exit 0
  End

  When call node_ssh 'pve1' 'uptime'
  The output should include 'command executed'
  The error should include '[pve1]'                    # prefix in log output
  The error should include "Running command 'uptime'"   # specific message
End
```

### ANSI color codes

Use `$'\033'` syntax, not `'\\033'`:

```bash
The error should include $'\033'    # correct — escape character
# NOT: The error should include '\\033'  # wrong — literal backslash
```

## Testing CLI Arguments (process_args)

### Boolean flags

```bash
It 'sets dry_run to true' do
  When call process_args '--cluster-node' 'pve1' '--dry-run'
  The variable dry_run should eq 'true'
End
```

### Error cases — set verbose before running

```bash
It 'exits with error when no arguments provided' do
  verbose=1
  When run process_args
  The status should be failure
  The output should include 'NAME'
  The error should include 'No arguments passed'
End
```

### Help flag exits 0

```bash
It 'exits 0 with --help and shows usage' do
  When run process_args '--cluster-node' 'pve1' '--help'
  The status should be success
  The output should include 'Proxmox cluster'
End
```

## Testing Background Jobs (wait_all_succeed)

### Override sleep to avoid test slowness

The script uses `wait_sleep()` — override it in the test:

```bash
wait_sleep() { :; }  # instant return, no actual sleep

It 'returns success when all jobs complete' do
  MyJob() { echo "done"; exit 0; }

  When call wait_all_succeed MyJob my_array
  The status should be success
End
```

### Background tests with real processes are slow

Each `sleep` in a mock blocks a real background thread. Always override sleep functions to return instantly:

```bash
wait_sleep() { :; }
node_wait_until_service_running() { echo "service up"; }  # skip real polling
```

## Testing Functions That Chain Calls (log_prefix)

`log_prefix` appends to `LOG_PREFIX` and chains remaining args as a function call. Test by capturing the variable in a wrapper:

```bash
It 'appends prefix to LOG_PREFIX' do
  local captured=""
  capture_log() { captured="$LOG_PREFIX"; }
  test_chain() { LOG_PREFIX=""; log_prefix "node1" capture_log; echo "$captured"; }
  When call test_chain
  The output should include '[node1]'
End
```

## Common Pitfalls

| Problem | Solution |
|---------|----------|
| `When return` error | Use `exit`, not `return` in Mock blocks (subshell) |
| Array length is `<unset>` | Arrays don't persist from subprocess; use inline overrides |
| ANSI tests fail with `'\\033'` | Use `$'\033'` for escape character |
| Test hangs on sleep calls | Override `wait_sleep()` or polling functions to return instantly |
| "parameter not set" errors in tests | Set required variables before the test (e.g., `verbose=1`) |
| stderr warnings | Always add `The error should include 'message'` expectations |
| DSL keywords lowercase | ShellSpec is case-sensitive: `Describe`, `It`, `When`, `The`, `End` |
| `log_pipe_level` writes to `$log_output` not stdout | Override `log_output=/dev/stdout` in wrapper function for capture |
| `Mock` with `return` instead of `exit` | Mock runs in a subshell; use `exit 0` or `exit 1` |

## Test File Organization

Split tests by feature area into separate spec files:

```
spec/
  variables_spec.sh        # Defaults and configuration
  logging_spec.sh          # All log_* functions
  process_args_spec.sh     # CLI argument parsing
  node_functions_spec.sh   # Node SSH, pvesh, maintenance, reboot
  upgrade_sequence_spec.sh # Upgrade flow functions
  wait_all_succeed_spec.sh # Background job management
```

## Adding a New Test

1. Find the appropriate spec file (or create one)
2. Add a `Describe` block matching the function name
3. Use `Include proxmox-upgrade-cluster.sh` at the top level
4. Mock any functions that call ssh or have side effects
5. Always add stderr expectations for log output to avoid warnings
6. Run with `nix develop -c shellspec spec/your_file.sh`
