# LVS step by step

Configurable C-shell runner for a Siemens Calibre LVS flow: Verilog-to-CDL conversion with `v2lvs`, layout extraction, and comparison. Project paths, top cell, supply pins and tool options live in a separate local configuration.

This is a Calibre runner, not a technology-independent LVS rule deck or a multi-tool framework. Calibre, licenses, PDK rules, library models and design inputs must be provided separately. No proprietary rule decks or design data are included.

## Quick start

Requirements: Linux/Unix, C-shell, standard utilities including `mktemp`, and an installed Calibre environment providing `calibre` and `v2lvs`.

```sh
cp config.example.csh config.local.csh
# Edit config.local.csh to match your project and environment.
./run_lvs full
```

Use absolute paths in the configuration. `STEP_DIR` must be a dedicated output directory: a full run moves an existing directory into a unique sibling archive. Never set it to a source, project or PDK directory. The example places results under the ignored `runs/` directory.

The optional second argument selects another trusted C-shell configuration:

```sh
./run_lvs full /absolute/path/to/project.local.csh
./run_lvs compare /absolute/path/to/project.local.csh
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

Each stage writes `log`, `timing`, and a `done` marker after successful process completion (conversion/extraction also require a nonempty netlist). Logs are redirected directly to files so a logging pipeline cannot hide tool failures; use `tail -f` to watch them. A nonzero tool exit stops subsequent stages.

**A zero exit code or `compare/done` means the process completed, not that LVS matched. Read the Calibre comparison report for the actual verdict.** Reports left by earlier comparisons may remain; use the current log and marker to identify the latest completed invocation.

Design inputs are copied only for stages that run, and those copies are used by the runner. Top-level rule files are saved under `rules/` for reference; included rules and library models are not bundled, so this is not a fully self-contained reproducibility archive. Optional `erc.rep` and `erc.db` files are collected under `ERC_report/`.

An atomic sibling lock prevents overlapping invocations targeting the same output path. After a crash or forced termination, remove the stale `.lock` directory only after confirming no job still uses it. Use one consistent absolute output path; symlink aliases are not resolved.

## Development

```sh
python3 -m unittest discover -s tests -v
```

Tests use fake tools and synthetic files; they verify orchestration, not Calibre compatibility or physical correctness. Validate the flow against your installed Calibre version and private decks before production use.

Possible next steps: input/config fingerprints, structured status output, tool-version recording, configurable report validation, and adapters for additional LVS engines.

## Publishing

Keep private configs, inputs, PDKs, logs and results outside tracked files. `.gitignore` covers common patterns, but review the staged file list before publishing. The original project-specific script is retained locally under ignored `.local-backup/` and must not be added to Git.
