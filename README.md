[![Tests](https://github.com/korotaevyua/lvs_step_by_step/actions/workflows/tests.yml/badge.svg)](https://github.com/korotaevyua/lvs_step_by_step/actions/workflows/tests.yml)

# LVS step by step

Configurable C-shell runner for a Siemens Calibre LVS flow: Verilog-to-CDL conversion with `v2lvs`, layout extraction, and comparison. Project paths, top cell, supply pins and tool options live in a separate local configuration.

This is a Calibre runner, not a technology-independent LVS rule deck or a multi-tool framework. Calibre, licenses, PDK rules, library models and design inputs must be provided separately. No proprietary rule decks or design data are included.

## Quick start

Requirements: Linux/Unix, C-shell, standard Unix utilities, and an installed Calibre environment providing `calibre` and `v2lvs`.

```sh
cp config.example.csh config.local.csh
# Edit config.local.csh to match your project and environment.
./run_lvs.sh full
```

Run `./run_lvs.sh help` (also `--help` or `-h`) to see modes without a configuration or installed Calibre. The `run_lvs` symlink keeps the original command, including `./run_lvs help`, working.

Use absolute paths in the configuration. `STEP_DIR` must be a dedicated output directory: a full run moves an existing directory into a unique sibling archive. Never set it to a source, project or PDK directory. The example places results under the ignored `runs/` directory. Archives have UTC timestamps, for example `example_top.archive.20260930T120000Z/run`. A repeat within the same second adds `.1`, `.2`, etc. before `/run`, preserving existing archives.

The optional second argument selects another trusted C-shell configuration:

```sh
./run_lvs.sh full /absolute/path/to/project.local.csh
./run_lvs.sh compare /absolute/path/to/project.local.csh
```

| Mode | Conversion | Extraction | Comparison |
| --- | --- | --- | --- |
| `full` (default) | Run | Run | Run |
| `compare` | Reuse | Reuse | Run |
| `v2cdl_compare` | Run | Reuse | Run |
| `extraction_compare` | Reuse | Run | Run |

Reuse requires nonempty intermediate netlists and successful stage markers from this runner. Rerun the corresponding stage when its inputs, technology, top cell or options change; there is no automatic dependency fingerprinting. Existing output from the original script should be regenerated with `full`.

## Rule deck contract

Provide your own extraction and comparison setup files. Rules are executed from the `extraction/` and `compare/` output directories respectively. Resolve rule includes accordingly. The runner exports these environment variables for decks configured to consume them:

- `GDS`: the copied layout input during extraction.
- `LVS_TOP`: configured top cell.
- `SOURCE_SPICE`: absolute `v2cdl/<TOP>.cdl` path.
- `LAYOUT_SPICE`: absolute `extraction/<TOP>.spi` path.

Decks must actually reference the intended inputs; the runner cannot rewrite or validate proprietary rules. The extraction command also supplies the output netlist through `-spice`. Comparison inputs and report names are controlled by your comparison deck. Input compression support depends on the installed tools.

## Results and failures

Each stage writes `log`, `timing`, and a `done` marker when its acceptance conditions are met. Logs are redirected directly to files so a logging pipeline cannot hide tool failures; use `tail -f` to watch them. Conversion requires a zero exit code and a nonempty CDL file. Comparison requires a zero exit code.

Extraction has a separate policy: Calibre may produce the extracted SPICE and then fail because the extraction deck does not specify a source for comparison. By default, the runner continues to the separate compare stage if extraction produces a **fresh, readable, nonempty regular SPICE file**, even if Calibre exits nonzero. It removes the previous netlist before starting, prints a warning, and records `exit_code` in `extraction/timing` and `extraction/done`. Missing or empty output always fails, even with exit code zero.

This is an output-based policy, not recognition of one particular Calibre error: a nonempty file alone cannot prove extraction completeness. Inspect the warning and extraction log. To require both valid output and a zero extraction exit code, set `EXTRACTION_REQUIRE_ZERO_EXIT = 1` in the C-shell config (default: `0`). This exception never applies to conversion or comparison.

**A zero exit code or `compare/done` means the process completed, not that LVS matched. Read the Calibre comparison report for the actual verdict.** Reports left by earlier comparisons may remain; use the current log and marker to identify the latest completed invocation.

Design inputs are copied only for stages that run, and those copies are used by the runner. Top-level rule files are saved under `rules/` for reference; included rules and library models are not bundled, so this is not a fully self-contained reproducibility archive. Optional `erc.rep` and `erc.db` files are collected under `ERC_report/`.

An atomic sibling lock prevents overlapping invocations targeting the same output path. After a crash or forced termination, remove the stale `.lock` directory only after confirming no job still uses it. Use one consistent absolute output path; symlink aliases are not resolved.

## Development and code checks

Use the same entry point locally and in GitHub Actions:

```sh
./scripts/check.sh
```

It runs C-shell syntax checks, ShellCheck, shfmt, actionlint, and the Python regression tests. It checks Git-tracked and new unignored files, preserves filenames with spaces, and skips symlinks and ignored private inputs. Shell dialect is selected from the shebang, not the `.sh` suffix: `run_lvs.sh` is C-shell. Files ending in `.csh`, including the example configuration, also receive a syntax check. New Bash helpers should have `#!/usr/bin/env bash`.

| Tool | Purpose here | Limit |
| --- | --- | --- |
| `tcsh -fn` | Parse the C-shell runner and config without executing them or startup files | Syntax check only; not semantic analysis or a formatter |
| [ShellCheck](https://github.com/koalaman/shellcheck) | Find quoting, expansion and other Bash/POSIX shell mistakes | Does not support C-shell; runs on the Bash check helper and future supported scripts |
| [shfmt](https://github.com/mvdan/sh) | Check Bash/POSIX shell formatting; `-w` applies formatting | Does not format C-shell; reads indentation from `.editorconfig` |
| [actionlint](https://github.com/rhysd/actionlint) | Check workflow structure, expressions, and embedded shell commands | Does not run GitHub Actions |
| Python `unittest` | Exercise modes, failures, fresh-output policy, help and archives with fake tools | Does not validate actual Calibre extraction or physical correctness |

The recommended setup is to keep the tested C-shell flow, use its parser plus behavioral tests, and use ShellCheck + shfmt for Bash helpers. Maintaining a second LVS implementation solely to use a linter would duplicate behavior and could break existing C-shell environment setup files. A future Bash migration should be a deliberate compatibility change with tests, rather than renaming the script or forcing ShellCheck to parse C-shell as Bash.

Install development dependencies (not needed on the machine running LVS itself):

```sh
# macOS with Homebrew
brew install tcsh shellcheck shfmt actionlint

# Ubuntu: shell tools, plus Go installed separately
sudo apt-get update
sudo apt-get install -y tcsh shellcheck
go install mvdan.cc/sh/v3/cmd/shfmt@v3.11.0
go install github.com/rhysd/actionlint/cmd/actionlint@v1.7.7
export PATH="$(go env GOPATH)/bin:$PATH"
```

GitHub Actions uses Ubuntu 24.04, Go 1.24.2, its distribution ShellCheck package, shfmt 3.11.0 and actionlint 1.7.7. Local package-manager versions may differ; align versions with CI when investigating differences. Python 3 and Git must also be available. The runner tests need the `csh` command (provided by the `tcsh` package on Ubuntu).

Useful individual commands:

```sh
tcsh -fn run_lvs.sh
shellcheck scripts/check.sh
shfmt -d scripts/check.sh   # display formatting differences
shfmt -w scripts/check.sh   # apply formatting
actionlint
python3 -m unittest discover -s tests -v
```

`.shellcheckrc` accepts `key=value` settings, not commands such as `shellcheck --enable=all`. The configuration keeps all default diagnostic severities, including style suggestions, without enabling every optional opinionated rule or restricting output to errors. `.editorconfig` supplies consistent indentation, line endings and final newlines for supporting editors; it is not a C-shell style checker.

To experiment, write a small Bash file with an unquoted expansion, run `shellcheck` on it, read the diagnostic and its linked explanation, then quote the variable and run it again. Use `shfmt -d` to see style changes separately from correctness warnings. The check helper itself is a small real Bash script you can use for this exercise.

Validate the flow against your installed Calibre version and private decks before production use. Possible next steps: input/config fingerprints, structured status output, tool-version recording, configurable report validation, and adapters for additional LVS engines.

## Publishing

Keep private configs, inputs, PDKs, logs and results outside tracked files. `.gitignore` covers common patterns, but review the staged file list before publishing. The original project-specific script is retained locally under ignored `.local-backup/` and must not be added to Git.
