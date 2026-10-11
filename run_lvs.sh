#!/bin/csh -f
# Run with -h for modes, options and configuration instructions.

# Parse options before sourcing configuration or looking for proprietary tools.
set VERBOSE = 0
set SHOW_HELP = 0
set PARSE_OPTIONS = 1
set POSITIONAL = ()
foreach argument ( $argv:q )
    if ( $PARSE_OPTIONS ) then
        switch ( "$argument" )
            case -v:
            case -verbose:
            case --verbose:
                set VERBOSE = 1
                continue
            case help:
            case --help:
            case -h:
                set SHOW_HELP = 1
                continue
            case --:
                set PARSE_OPTIONS = 0
                continue
            case -*:
                echo "ERROR: unknown option: $argument"
                echo "Run $0 -h for usage."
                exit 2
        endsw
    endif
    set POSITIONAL = ( $POSITIONAL:q "$argument" )
end
if ( $SHOW_HELP ) then
    echo "Usage: $0 [-v|-verbose|--verbose] [full|compare|v2cdl_compare|extraction_compare] [config.csh]"
    echo ""
    echo "  full                Convert Verilog, extract layout, then compare (default)."
    echo "  compare             Compare previously generated source and layout SPICE."
    echo "  v2cdl_compare       Regenerate source SPICE, reuse layout, then compare."
    echo "  extraction_compare  Regenerate layout SPICE, reuse source, then compare."
    echo "  -v, -verbose, --verbose  Also stream tool stdout/stderr to the terminal."
    echo "  help, --help, -h    Show this help without loading config or running tools."
    echo ""
    echo "Options can appear before or after the mode/config; -- ends option parsing."
    echo "Copy config.example.csh to config.local.csh and edit absolute paths."
    echo "The optional config argument selects another trusted C-shell config."
    echo "Full runs archive previous results as <run>.archive.YYYYMMDD_0, _1, etc. (local date)."
    echo "Inspect stage log files and the final Calibre report for the LVS verdict."
    exit 0
endif
if ( $#POSITIONAL > 2 ) then
    echo "ERROR: expected at most a mode and config path. Run $0 -h for usage."
    exit 2
endif
set CONFIG = "$cwd/config.local.csh"
if ( $#POSITIONAL == 2 ) then
    set CONFIG = "$POSITIONAL[2]"
endif
set MODE = full
if ( $#POSITIONAL > 0 ) then
    set MODE = "$POSITIONAL[1]"
endif

set RUN_V2CDL = 0
set RUN_EXTR  = 0
set RUN_COMP  = 0

switch ( "$MODE" )
    case full:
        set RUN_V2CDL = 1
        set RUN_EXTR  = 1
        set RUN_COMP  = 1
        breaksw

    case compare:
        set RUN_COMP  = 1
        breaksw

    case v2cdl_compare:
        set RUN_V2CDL = 1
        set RUN_COMP  = 1
        breaksw

    case extraction_compare:
        set RUN_EXTR  = 1
        set RUN_COMP  = 1
        breaksw

    default:
        echo "ERROR: unknown mode: $MODE. Run $0 -h for usage."
        echo "Usage: $0 [-v|-verbose|--verbose] [full|compare|v2cdl_compare|extraction_compare] [config.csh]"
        exit 2
        breaksw
endsw

set TOP = ""
set verilog = ""
setenv GDS ""
set V2LVS_SRC = ""
set EXTR_RULE = ""
set COMP_RULE = ""
set SETUP_ENV = ""
set STEP_DIR = "$cwd/runs/lvs"
set EXTRACTION_REQUIRE_ZERO_EXIT = 0
set USE_HCELL = 0
set HCELL = ""
set V2LVS_ARGS = ()
set CALIBRE_ARGS = ( -hier -hyper -turbo )
if ( ! -f "$CONFIG" ) then
    echo "ERROR: missing $CONFIG; copy and edit config.example.csh"
    exit 1
endif
source "$CONFIG"
if ( $status != 0 ) exit 1
if ( "$TOP" == "" || "$TOP" =~ */* || "$TOP" == "." || "$TOP" == ".." ) then
    echo "ERROR: TOP must be a nonempty cell name without slashes"
    exit 1
endif
if ( "$STEP_DIR" !~ /* || "$STEP_DIR" == "/" || "$STEP_DIR" =~ */ || "$STEP_DIR" =~ */../* || "$STEP_DIR" =~ */.. || "$STEP_DIR" =~ */./* || "$STEP_DIR" =~ */. ) then
    echo "ERROR: STEP_DIR must be an absolute dedicated run directory without dot components or a trailing slash"
    exit 1
endif

if ( "$EXTRACTION_REQUIRE_ZERO_EXIT" != "0" && "$EXTRACTION_REQUIRE_ZERO_EXIT" != "1" ) then
    echo "ERROR: EXTRACTION_REQUIRE_ZERO_EXIT must be 0 or 1"
    exit 1
endif

set REQUIRED = ( "$COMP_RULE" )
if ( $RUN_V2CDL ) set REQUIRED = ( $REQUIRED:q "$verilog" "$V2LVS_SRC" )
if ( $RUN_EXTR ) set REQUIRED = ( $REQUIRED:q "$GDS" "$EXTR_RULE" )
if ( "$SETUP_ENV" != "" ) set REQUIRED = ( $REQUIRED:q "$SETUP_ENV" )
if ( $USE_HCELL ) set REQUIRED = ( $REQUIRED:q "$HCELL" )
foreach input_file ( $REQUIRED:q )
    if ( "$input_file" !~ /* || ! -f "$input_file" || ! -r "$input_file" ) then
        echo "ERROR: expected readable file at an absolute path: $input_file"
        exit 1
    endif
end
if ( "$SETUP_ENV" != "" ) then
    source "$SETUP_ENV"
    if ( $status != 0 ) exit 1
endif
which calibre >& /dev/null
if ( $status != 0 ) then
    echo "ERROR: calibre is not in PATH"
    exit 1
endif
if ( $RUN_V2CDL ) then
    which v2lvs >& /dev/null
    if ( $status != 0 ) then
        echo "ERROR: v2lvs is not in PATH"
        exit 1
    endif
endif
# A small Bash helper mirrors logs without losing the tool's exit status.
set SCRIPT_DIR = "`cd "$0:h" && pwd`"
if ( $status != 0 ) exit 1
set RUN_TOOL = "$SCRIPT_DIR/scripts/run_tool.sh"
if ( ! -f "$RUN_TOOL" || ! -x "$RUN_TOOL" ) then
    echo "ERROR: missing executable logging helper: $RUN_TOOL"
    exit 1
endif
which bash >& /dev/null
if ( $status != 0 ) then
    echo "ERROR: bash is required by the logging helper"
    exit 1
endif
set TOOL_OUTPUT = --quiet
if ( $VERBOSE ) set TOOL_OUTPUT = --verbose

mkdir -p "$STEP_DIR:h"
if ( $status != 0 ) exit 1
set LOCK = "${STEP_DIR}.lock"
mkdir "$LOCK"
if ( $status != 0 ) then
    echo "ERROR: lock unavailable: $LOCK; check for an active run or stale lock"
    exit 1
endif
onintr failed
if ( "$MODE" == "full" ) then
    if ( -e "$STEP_DIR" ) then
        set ARCHIVE_DATE = `date "+%Y%m%d"`
        if ( $status != 0 ) goto failed
        set ARCHIVE_BASE = "${STEP_DIR}.archive.${ARCHIVE_DATE}"
        set ARCHIVE_INDEX = 0
        set ARCHIVE = "${ARCHIVE_BASE}_${ARCHIVE_INDEX}"
        # The run lock serializes creation; use the first available daily index.
        while ( -e "$ARCHIVE" || -l "$ARCHIVE" )
            @ ARCHIVE_INDEX ++
            set ARCHIVE = "${ARCHIVE_BASE}_${ARCHIVE_INDEX}"
        end
        mkdir "$ARCHIVE"
        if ( $status != 0 ) goto failed
        mv "$STEP_DIR" "$ARCHIVE/run"
        if ( $status != 0 ) goto failed
        echo "Previous run: $ARCHIVE/run"
    endif
else
    if ( ! -d "$STEP_DIR" ) then
        echo "ERROR: run full first"
        goto failed
    endif
endif
foreach stage ( v2cdl extraction compare GDS verilog rules ERC_report )
    mkdir -p "$STEP_DIR/$stage"
    if ( $status != 0 ) goto failed
end
setenv SOURCE_SPICE "$STEP_DIR/v2cdl/${TOP}.cdl"
setenv LAYOUT_SPICE "$STEP_DIR/extraction/${TOP}.spi"
setenv LVS_TOP "$TOP"
rm -f "$STEP_DIR/compare/done"
if ( $status != 0 ) goto failed
if ( $RUN_V2CDL ) then
    cp "$verilog" "$STEP_DIR/verilog/$verilog:t"
    if ( $status != 0 ) goto failed
    set verilog = "$STEP_DIR/verilog/$verilog:t"
endif
if ( $RUN_EXTR ) then
    cp "$GDS" "$STEP_DIR/GDS/$GDS:t"
    if ( $status != 0 ) goto failed
    setenv GDS "$STEP_DIR/GDS/$GDS:t"
endif

# =========================
# v2cdl

if ( $RUN_V2CDL ) then
    echo "=== V2CDL ==="
    cd "$STEP_DIR/v2cdl"
    if ( $status != 0 ) goto failed
    rm -f done "$SOURCE_SPICE"
    if ( $status != 0 ) goto failed

    set start_time = `date "+%Y-%m-%d %H:%M:%S"`
    echo "start=$start_time" > timing
    if ( $status != 0 ) goto failed
    "$RUN_TOOL" $TOOL_OUTPUT log v2lvs -v "$verilog" -o "$SOURCE_SPICE" -s "$V2LVS_SRC" -lsr "$V2LVS_SRC" $V2LVS_ARGS:q
    if ( $status != 0 ) goto failed
    if ( ! -s "$SOURCE_SPICE" ) goto failed

    set end_time = `date "+%Y-%m-%d %H:%M:%S"`
    echo "end=$end_time" >> timing
    if ( $status != 0 ) goto failed
    cp timing done
    if ( $status != 0 ) goto failed

    cd "$STEP_DIR"
    if ( $status != 0 ) goto failed
endif

# =========================
# extraction
if ( ! -s "$SOURCE_SPICE" || ! -f "$STEP_DIR/v2cdl/done" ) then
    echo "ERROR: missing completed source conversion; run full or v2cdl_compare"
    goto failed
endif
if ( $RUN_EXTR ) then
    echo "=== EXTRACTION ==="
    cd "$STEP_DIR/extraction"
    if ( $status != 0 ) goto failed
    rm -f done "$LAYOUT_SPICE" erc.rep erc.db ../ERC_report/erc.rep ../ERC_report/erc.db
    if ( $status != 0 ) goto failed
    cp "$EXTR_RULE" ../rules/extraction_setup.snapshot
    if ( $status != 0 ) goto failed

    set start_time = `date "+%Y-%m-%d %H:%M:%S"`
    echo "start=$start_time" > timing
    if ( $status != 0 ) goto failed

    "$RUN_TOOL" $TOOL_OUTPUT log calibre -lvs $CALIBRE_ARGS:q -spice "$LAYOUT_SPICE" "$EXTR_RULE"
    set EXTR_STATUS = $status
    echo "exit_code=$EXTR_STATUS" >> timing
    if ( $status != 0 ) goto failed
    # The previous netlist was removed before this invocation. Never accept stale output.
    if ( ! -f "$LAYOUT_SPICE" || ! -r "$LAYOUT_SPICE" || ! -s "$LAYOUT_SPICE" ) then
        echo "ERROR: extraction did not produce a new readable nonempty SPICE file"
        goto failed
    endif
    if ( $EXTR_STATUS != 0 ) then
        if ( $EXTRACTION_REQUIRE_ZERO_EXIT ) then
            echo "ERROR: extraction exited with code $EXTR_STATUS (strict mode)"
            goto failed
        endif
        echo "WARNING: extraction exited with code $EXTR_STATUS but produced $LAYOUT_SPICE"
        echo "WARNING: continuing to compare; inspect extraction/log for errors and netlist completeness"
    endif

    set end_time = `date "+%Y-%m-%d %H:%M:%S"`
    echo "end=$end_time" >> timing
    if ( $status != 0 ) goto failed
    cp timing done
    if ( $status != 0 ) goto failed

    foreach report ( erc.rep erc.db )
        if ( -f "$report" ) then
            cp "$report" "../ERC_report/"
            if ( $status != 0 ) goto failed
        endif
    end

    cd "$STEP_DIR"
    if ( $status != 0 ) goto failed
endif

# =========================
# compare
if ( ! -s "$LAYOUT_SPICE" || ! -f "$STEP_DIR/extraction/done" ) then
    echo "ERROR: missing completed extraction; run full or extraction_compare"
    goto failed
endif
if ( $RUN_COMP ) then

    echo "=== COMPARE ==="
    cd "$STEP_DIR/compare"
    if ( $status != 0 ) goto failed

    cp "$COMP_RULE" "../rules/compare_setup.snapshot"
    if ( $status != 0 ) goto failed

    set start_time = `date "+%Y-%m-%d %H:%M:%S"`
    echo "start=$start_time" > timing
    if ( $status != 0 ) goto failed

    if ( $USE_HCELL ) then
        "$RUN_TOOL" $TOOL_OUTPUT log calibre -lvs $CALIBRE_ARGS:q -hcell "$HCELL" "$COMP_RULE"
        if ( $status != 0 ) goto failed
    else
        "$RUN_TOOL" $TOOL_OUTPUT log calibre -lvs $CALIBRE_ARGS:q "$COMP_RULE"
        if ( $status != 0 ) goto failed
    endif
    set end_time = `date "+%Y-%m-%d %H:%M:%S"`
    echo "end=$end_time" >> timing
    if ( $status != 0 ) goto failed
    cp timing done
    if ( $status != 0 ) goto failed

    cd "$STEP_DIR"
    if ( $status != 0 ) goto failed
endif

rmdir "$LOCK"
if ( $status != 0 ) exit 1
echo "Compare process completed. Read the Calibre report for the LVS verdict."
exit 0

failed:
echo "ERROR: LVS run failed; inspect stage log files under $STEP_DIR"
rmdir "$LOCK"
exit 1
