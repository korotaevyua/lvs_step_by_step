# LVS step by step

[![Checks](https://github.com/korotaevyua/lvs_step_by_step/actions/workflows/tests.yml/badge.svg)](https://github.com/korotaevyua/lvs_step_by_step/actions/workflows/tests.yml)

A small C-shell script for running Siemens Calibre LVS in three steps: Verilog-to-CDL conversion, layout extraction, and comparison. Project paths, top cell, supply pins and tool options live in a local configuration.

## Quick start

You need C-shell, Bash 3.2+, and a licensed Calibre installation with `calibre` and `v2lvs`. Provide your own design files, library models and PDK rule decks.

```sh
cp config.example.csh config.local.csh
# Edit paths, top cell and tool options in config.local.csh.
./run_lvs full
```

Use absolute paths and a dedicated output directory (`STEP_DIR`, under `runs/` by default). Configs are executable C-shell code; use trusted files. Keep local configs, design data and PDK files out of Git.

## Usage

```sh
./run_lvs -h                           # help; no config or Calibre required
./run_lvs -v full                      # show tool logs while running
./run_lvs compare /path/to/config.csh   # use another configuration
```

`run_lvs` is a shortcut to `run_lvs.sh`; either name works. `-v`, `-verbose` and `--verbose` stream stdout/stderr to the terminal while saving stage logs. Options can appear before or after the mode/config; `--` ends option parsing.

| Mode | Conversion | Extraction | Comparison |
| --- | --- | --- | --- |
| `full` (default) | Run | Run | Run |
| `compare` | Reuse | Reuse | Run |
| `v2cdl_compare` | Run | Reuse | Run |
| `extraction_compare` | Reuse | Run | Run |

Reuse requires nonempty netlists and completed stage markers. Rerun the relevant stage when inputs or settings change; dependencies are not tracked automatically.

## Rule setup

Extraction and comparison decks run from their respective output directories. Configure their inputs and includes accordingly. The runner exports:

| Variable | Value |
| --- | --- |
| `GDS` | Copied layout input during extraction |
| `LVS_TOP` | Configured top cell |
| `SOURCE_SPICE` | Absolute path to `v2cdl/<TOP>.cdl` |
| `LAYOUT_SPICE` | Absolute path to `extraction/<TOP>.spi` |

The extraction command supplies the output path through `-spice`. Your comparison deck must reference the source/layout netlists and define its reports.

## Results

Each stage saves `log`, `timing` and a `done` marker when accepted. **A completed compare means the process finished; check the Calibre report for the LVS verdict.**

Conversion requires a zero exit code and a nonempty CDL; comparison requires a zero exit code. Extraction can continue after a nonzero exit if it produced a fresh, readable, nonempty SPICE file. The runner warns and records the exit code. Check the extraction log: a nonempty file does not guarantee completeness. Set `EXTRACTION_REQUIRE_ZERO_EXIT = 1` to require a zero exit code as well.

A full run archives previous results as `<STEP_DIR>.archive.YYYYMMDD_0/run`, then `_1`, etc., using the local date without overwriting existing archives. Rule snapshots go to `rules/`, and optional ERC reports to `ERC_report/`; included rules and library models are not copied.

A lock prevents simultaneous runs in the same output directory. After a crash, remove a stale `<STEP_DIR>.lock` only after confirming no job is still running.

## Development

```sh
./scripts/check.sh
```

Requires Git, Python 3, tcsh, ShellCheck, shfmt and actionlint. Runs C-shell syntax checks, Bash lint/format checks, workflow validation and tests with fake tools. The same checks run in GitHub Actions; real Calibre validation requires your own environment.
