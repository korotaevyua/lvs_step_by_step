#!/bin/csh -f


# Usage:
#   copy config.example.csh to config.local.csh and edit it, then run:
#
#   ./run_lvs
#   ./run_lvs compare - rerun compare stage only using old layout/source spice
#   ./run_lvs v2cdl_compare - rerun v2cdl and compare using old layout spice
#   ./run_lvs extraction_compare  rerun extraction and compare using old source spice

# Configuration is trusted executable C-shell. Paths must be absolute.
set CONFIG = "$cwd/config.local.csh"
if ( $#argv > 2 ) then
    echo "Usage: $0 [full|compare|v2cdl_compare|extraction_compare] [config.csh]"
    exit 2
endif
if ( $#argv == 2 ) set CONFIG = "$argv[2]"
set TOP = ""
set verilog = ""
setenv GDS ""
set V2LVS_SRC = ""
set EXTR_RULE = ""
set COMP_RULE = ""
set SETUP_ENV = ""
set STEP_DIR = "$cwd/runs/lvs"
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

# =========================
set MODE = full
if ( $#argv > 0 ) then
    set MODE = "$argv[1]"
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
        echo "Usage: $0 [full|compare|v2cdl_compare|extraction_compare] [config.csh]"
        exit 1
        breaksw
endsw

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
        set ARCHIVE = `mktemp -d "${STEP_DIR}.archive.XXXXXXXX"`
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
    v2lvs -v "$verilog" -o "$SOURCE_SPICE" -s "$V2LVS_SRC" -lsr "$V2LVS_SRC" $V2LVS_ARGS:q >& log
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

    calibre -lvs $CALIBRE_ARGS:q -spice "$LAYOUT_SPICE" "$EXTR_RULE" >& log
    if ( $status != 0 ) goto failed
    if ( ! -s "$LAYOUT_SPICE" ) goto failed

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
    calibre -lvs $CALIBRE_ARGS:q -hcell "$HCELL" "$COMP_RULE" >& log
    if ( $status != 0 ) goto failed
    else
    calibre -lvs $CALIBRE_ARGS:q "$COMP_RULE" >& log
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
