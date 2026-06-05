# Testing with ShellSpec

## Running Tests

```bash
nix develop -c shellspec                    # All tests
nix develop -c shellspec spec/file_name.sh  # Specific test file
nix develop -c shellspec --dry-run          # List examples without running
nix develop -c shellspec --random=specfiles # Verify order-independence
nix develop -c shellcheck proxmox-upgrade-cluster.sh  # Static analysis
nix develop -c shfmt -d proxmox-upgrade-cluster.sh  # Format check
nix develop -c shfmt -w proxmox-upgrade-cluster.sh  # Apply formatting
nix build .#default                         # Build the script via flake
```

`shfmt` reads its options from `.editorconfig`: `indent_size = 2` (2-space
indent), `switch_case_indent` (indent case patterns under their `case`), and
`binary_next_line` (a wrapped pipe/`&&`/`||` starts the continuation line, e.g.
`cmd \` then `| jq …`). **Do not pass `-i`/`-ci`/`-bn` (or any other
parser/printer flag)** — shfmt ignores `.editorconfig` entirely when any such
flag is given, so the flagged form would silently use different rules. The same
flag-free `shfmt -d` is wired into `nix build`'s `checkPhase` so a PR that
diverges from the format won't build. `spec/**` is marked `ignore = true` in
`.editorconfig` and never passed to shfmt — those files use the ShellSpec DSL
(`Describe`/`It`/`When`/`The`/`End`) which shfmt doesn't recognise and would
mangle.

### Coverage (Linux only)

```bash
nix develop -c shellspec --kcov             # Coverage report → ./coverage/
```

`kcov` is in the dev shell only on Linux (the upstream package isn't
available on darwin). Coverage reporting is `index.html` under
`./coverage/`. Run via CI or a Linux container if you're on macOS.

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

### Parameters Directive

ShellSpec 0.28.1 `Parameters` works cleanly for **tabular tests with scalar
inputs and scalar expected values**:

```bash
Describe 'boolean flag defaults' do
  Parameters
    ssh_key_auth_only        true
    ssh_multiplexing         true
    dry_run                  false
    use_maintenance_mode     true
    preserve_discovery_order false
  End

  It "$1 defaults to $2" do
    The variable "$1" should eq "$2"
  End
End
```

Also fine for `(flag, var, value)` triples driving multiple boolean CLI
flags through one `It` block, and for any test where the variation is
just plain strings.

#### Parameters Directive Limitations

`Parameters` does NOT handle:

- **Function name substitution does not work** — `<func_name>` in a command position is treated literally, not substituted
- **Space-containing values break parsing** — parameters with spaces (e.g., `'test alert message'`) cause "command not found" errors
- **Variable capture from mocks doesn't persist** — mocked functions run in subprocesses; variable assignments are lost

For these cases, use separate `It` blocks instead of Parameters:

```bash
# WRONG - Parameters with function names and spaces
Describe 'color-coded logs' do
  Parameters
    func_name   | message
    log_warning | test warning message
  End
  It 'works' do
    When call "<func_name>" '<message>'   # FAILS: executes literal <func_name>
  End
End

# RIGHT - separate It blocks for each variant
Describe 'log_warning' do
  It 'outputs the message with color codes' do
    When call log_warning 'test warning message'
    The error should include 'test warning message'
  End
End

Describe 'log_error' do
  It 'outputs the message with color codes' do
    When call log_error 'test error message'
    The error should include 'test error message'
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

### Auditing mocks when the real function's emission shape changes

When changing how a function emits data (e.g. one-per-line vs space-joined),
audit every mock that simulates it. An `echo ''` mock that was benign under
word-splitting becomes a one-element-with-empty-string array under
`mapfile -t`, which can drive callers into loops they never reached before.

## Fixtures and Shared Helpers

When multiple `It` blocks share boilerplate (JSON-shaped mocks, baseline
stubs, common setup), extract a file-scope helper function. Several
patterns are established in the suite — match them so the codebase stays
consistent.

### The global-closure pattern (for parameterised mocks)

Bash function definitions don't close over caller-local variables. When a
fixture helper installs a mock that needs to return a value the helper
was passed, the value must live in the **global** scope so the inner
function reads it at call time, not at definition time:

```bash
make_manager_status_pvesh() {
  local pairs=()
  while (( $# )); do
    pairs+=("\"$1\":\"$2\"")
    shift 2
  done
  # _mgr_status_json is a GLOBAL — node_pvesh reads it at call time,
  # well after make_manager_status_pvesh has returned.
  _mgr_status_json="{\"manager_status\":{\"node_status\":{$(IFS=,; echo "${pairs[*]}")}}}"
  node_pvesh() { echo "$_mgr_status_json"; }
}
```

Convention: prefix the globals with `_` to signal "fixture-internal,
don't read from tests directly." Examples in the suite:
`_pbt_uname`, `_pbt_kernel_list`, `_grub_uname`, `_mgr_status_json`,
`_status_array_json`, `_hostname_value`.

### `Before do/End` does NOT install function definitions

`Before do/End` runs in its own subshell. Function definitions made
inside it are scoped to that subshell and **don't survive into the
It-block body**. Symptom: `When run main` exits 127 (command not
found) because the mock isn't visible.

```bash
# WRONG — mocks are lost.
Before do
  is_node_up() { return 0; }
End

It 'test' do
  When run main '--cluster-node' 'pve1'  # fails: is_node_up not defined
End

# RIGHT — file-scope helper installs the mocks; each It calls it.
install_main_happy_path_stubs() {
  is_node_up() { return 0; }
  # ... other stubs
}

It 'test' do
  install_main_happy_path_stubs
  When run main '--cluster-node' 'pve1'
End
```

Bash globally scopes nested function definitions (a function defined
*inside* another function lives at the script's global scope), which is
why the helper-function approach works where the `Before` hook doesn't.

### Existing helpers in the suite

These live at file scope, near the tests that use them, and follow the
global-closure convention where relevant. Reuse them rather than rolling
new inline mocks:

| Helper | File | Purpose |
|---|---|---|
| `capture_array <var> <args...>` | `process_args_spec.sh` | Run real `process_args`, then print the named array element-by-element so a `When call` test can assert against array shape (which doesn't normally survive subshells). |
| `install_main_happy_path_stubs` | `main_spec.sh` | All-success stubs for `main()`'s health-check + apt-update + upgrade flow. Each test overrides one stub to drive the branch under test. |
| `install_reboot_stubs` | `upgrade_sequence_spec.sh` | All-success stubs + default scalars for `node_reboot` tests. |
| `install_update_sequence_happy_stubs` | `upgrade_sequence_spec.sh` | No-op stubs for the four upgrade stages (`node_pre_upgrade`, `node_upgrade`, `node_reboot`, `node_post_upgrade`). |
| `record_invocations <fn>` | `upgrade_sequence_spec.sh` | Install a stub that appends `$1` to a tempfile (`$invocations`); use to verify per-node calls under `wait_all` where subshell-internal array mutations would otherwise be lost. |
| `make_pbt_node_ssh <uname> <kernel-list-lines...>` | `node_functions_spec.sh` | `node_ssh` mock for `node_needs_reboot`'s proxmox-boot-tool branch. |
| `make_grub_node_ssh <uname> <grub-lines...>` | `node_functions_spec.sh` | `node_ssh` mock for `node_needs_reboot`'s grub.cfg fallback branch. |
| `make_manager_status_pvesh <node> <status> ...` | `node_functions_spec.sh` | `node_pvesh` mock returning HA manager_status JSON from `(node, status)` pairs. |
| `make_status_array_pvesh <status...>` | `node_functions_spec.sh` | `node_pvesh` mock returning a JSON status-array for `node_get_running_count`. |
| `make_hostname_node_ssh <hostname>` | `node_functions_spec.sh` | `node_ssh` mock that answers `hostname` queries. Use with `make_manager_status_pvesh` for `node_get_mode` tests. |

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

## Testing Background Jobs (wait_all)

### Override sleep to avoid test slowness

The script uses `wait_sleep()` — override it in the test:

```bash
wait_sleep() { :; }  # instant return, no actual sleep

It 'returns success when all jobs complete' do
  MyJob() { echo "done"; exit 0; }

  When call wait_all MyJob my_array
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
| `Mock` block can't keep state across calls | Mock runs in a subshell; for stateful counters use an inline function override |
| `satisfy` matcher errors with `value: unbound` | Read the subject as `${value:-}` — the matcher runs under `nounset` |
| Need a value mid-`When call` for a later matcher | `$output` isn't exposed between assertions; do the comparison inside the driver function and assert on its stdout |
| `When run` test exits 127 ("command not found") | A mock the test expected isn't visible inside the subshell. `Before do/End` doesn't install functions — use a file-scope helper instead. |
| Multi-line `Before` raises "Unexpected End" | `Before` requires `do` for multi-line bodies (`Before do ... End`). `Before 'one-liner'` is the single-statement form. |
| Test times out / hangs at `verbose>=6` | `process_args` enables `set -x` globally at `verbose>=6` to aid live debugging. Don't drive that ladder from tests — verbose=5 is enough for the ssh-verbosity branch; skip 6+. |
| ERR trap test doesn't fire on intermediate failures | The trap fires via errexit, but `When call` doesn't enable `set -e`. Add `Set errexit:on` at the Describe scope. |
| Subshell mock writes (e.g. `wait_all`) lose `+=` updates | Use the `record_invocations <fn>` helper — the tempfile survives the subshell boundary. |
| shellcheck SC2178 on `local -n` followed by array write | Known false-positive: shellcheck can't model namerefs. Rename the nameref to something distinct from other read-only namerefs in the file (e.g. `nodes_inout`) to avoid cross-function aliasing, plus a `# shellcheck disable=SC2178` if needed. |

## Test File Organization

Split tests by feature area into separate spec files:

```
spec/
  variables_spec.sh        # Default values for script-level variables
  logging_spec.sh          # All log_* functions
  process_args_spec.sh     # CLI argument parsing
  main_spec.sh             # main() flow control + jq prerequisite + sort wiring
  node_functions_spec.sh   # Node SSH, pvesh, maintenance, reboot, kernel detection
  upgrade_sequence_spec.sh # Upgrade flow (enter/exit maintenance, reboot, run_update_sequence)
  wait_all_spec.sh         # Background job management (wait_all + succeed/failed)
```

## Adding a New Test

1. Find the appropriate spec file (or create one)
2. Add a `Describe` block matching the function name
3. Use `Include proxmox-upgrade-cluster.sh` at the top level
4. **Reuse existing fixtures** before rolling your own — the helpers listed
   under "Fixtures and Shared Helpers" cover most JSON-mock and baseline-stub
   needs. If your test's setup repeats a pattern that's already in another
   It-block, lift it to a file-scope helper instead of pasting the boilerplate.
5. Mock any functions that call ssh or have side effects
6. Always add stderr expectations for log output to avoid the "There was
   output to stderr but not found expectation" warning
7. Run with `nix develop -c shellspec spec/your_file.sh`

## Help text (usage() and README)

`usage()` and the README OPTIONS section document the same flags and must stay
in sync. Keep each entry terse and uniform with the surrounding options:

- One short sentence of what the flag does — no parenthetical examples or extra
  prose.
- For repeatable flags, `Can be passed multiple times.` as its own sentence.
- State the default as `Default of '<value>'.` (or `Defaults to none.`).

The one deliberate difference between the two renderings:

- **`usage()`** is an expanding `cat <<EOF` heredoc, so reference the backing
  **variable** for a default — e.g. `Default of '${ignored_task_types[*]}'.` —
  so the help reflects the live value.
- **README** is static Markdown and can't interpolate, so mirror the same
  wording with the **literal** default — e.g. `Default of 'vncproxy'.`
