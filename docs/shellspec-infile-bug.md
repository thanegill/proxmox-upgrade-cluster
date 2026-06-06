# Upstream bug report: shellspec `--random` drops a stray `file` in the project

This is the report behind the `/file` entry in this repo's `.gitignore`. The
`shellspec --random=specfiles` order-independence check recommended in
`CLAUDE.md` writes a stray `./file` into the project root each run. The text
below is ready to paste into <https://github.com/shellspec/shellspec/issues>.

---

**Title:** `--random` writes the spec list to a relative `file` in the working directory (leaks; clobbers an existing `./file`)

## Summary

Running with `--random` (any type other than `none`) creates a file literally
named `file` in the current working directory, overwriting any existing
`./file`, and does not remove it on exit. Every *other* per-run scratch file is
placed under the temp dir `$SHELLSPEC_TMPBASE` and cleaned up; `SHELLSPEC_INFILE`
is the lone exception — it defaults to the **relative** path `file`.

## Steps to reproduce

```sh
mkdir /tmp/ss-infile && cd /tmp/ss-infile
shellspec --init                 # creates .shellspec + spec/
echo 'IMPORTANT - do not delete' > file

shellspec --random specfiles     # or --random=specfiles, or --random examples

cat file                         # <-- your file is gone
ls -la file                      # <-- left behind after shellspec exits
```

## Expected

- No file named `file` is created in the working/project directory.
- Any pre-existing `./file` is left untouched.
- The randomized spec list is kept in a private, auto-cleaned location (like
  every other scratch file), and removed on exit.

## Actual

`./file` is created (truncating any existing `./file`) and is **not** removed
when shellspec exits. Its contents are the randomized spec-file list, e.g.:

```
spec/main_spec.sh
spec/variables_spec.sh
spec/process_args_spec.sh
...
```

Confirmed by bisection: plain runs and `--random none` create nothing; both
`--random specfiles` and `--random examples` create `./file`.

## Root cause

`SHELLSPEC_INFILE` defaults to the bare relative path `file`:

```sh
# shellspec (main script)
export SHELLSPEC_INFILE=file
```

When `--random` is set, the runner redirects the (shuffled) spec list to it:

```sh
# libexec/shellspec-runner.sh
if [ "${SHELLSPEC_RANDOM:-}" ]; then
  export SHELLSPEC_LIST=$SHELLSPEC_RANDOM
  exec="$SHELLSPEC_LIBEXEC/shellspec-list.sh"
  eval "$SHELLSPEC_SHELL" "\"$exec\"" ${1+'"$@"'} >"$SHELLSPEC_INFILE"   # -> ./file
  ...
```

Two consequences:

1. **No cleanup / leak.** `cleanup()` (trapped on `EXIT` in
   `shellspec-runner.sh`) removes `$SHELLSPEC_TMPBASE`. Because `SHELLSPEC_INFILE`
   is *not* under `$SHELLSPEC_TMPBASE` — unlike `SHELLSPEC_TIME_LOG`,
   `SHELLSPEC_PROFILER_LOG`, `SHELLSPEC_PRECHECKER_STATUS`,
   `SHELLSPEC_REPORTER_PID`, `SHELLSPEC_KCOV_IN_FILE`,
   `SHELLSPEC_DEPRECATION_LOGFILE`, which are all `"$SHELLSPEC_TMPBASE/..."`
   absolute paths — it is never removed.
2. **Data loss.** The truncating `>` redirect silently overwrites a user file
   named `file` in the project root.

## Impact

- A stray `file` is left in the project root after every `--random` run — easy
  to accidentally `git add`.
- Silent data loss for anyone who happens to have a file named `file` there.

## Suggested fix

Place it under the per-run temp dir like every sibling scratch file, so it's
both isolated and removed by the existing `cleanup`:

```sh
# shellspec (main script), after SHELLSPEC_TMPBASE is defined:
export SHELLSPEC_INFILE="$SHELLSPEC_TMPBASE/infile"
```

## Environment

- shellspec 0.28.1 (also present in `master`, 0.29.0-dev — `export SHELLSPEC_INFILE=file` is unchanged)
- bash 5.x; reproduced on macOS and Linux
