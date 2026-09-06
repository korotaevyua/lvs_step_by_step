# Copy to config.local.csh. Configs are trusted executable C-shell code.
# All file paths must be absolute. Keep your local config private.
set TOP = "example_top"
set STEP_DIR = "$cwd/runs/example_top"
set verilog = "/path/to/design.v"
setenv GDS "/path/to/design.gds"
set V2LVS_SRC = "/path/to/library/source.net"
set EXTR_RULE = "/path/to/rules/extraction_setup"
set COMP_RULE = "/path/to/rules/compare_setup"
# Optional C-shell tool environment; otherwise use the current PATH.
set SETUP_ENV = ""
set USE_HCELL = 0
set HCELL = ""
# Adjust pins/options for your library and installed tool version.
set V2LVS_ARGS = ( -addpin VDD -addpin VSS )
set CALIBRE_ARGS = ( -hier -hyper -turbo )
