if {[info exists ::env(dv_root)]} {set dv_root "$::env(dv_root)";} \
else {puts "ERROR: Script run without dv_root environment variable."; exit;}

set simulator "vcs"
set waves "fsdb"
set gui 0
set tb_top "tb"

# Helper procedure libraries
source "${dv_root}/tools/tcl/procs.tcl"
source "${dv_root}/tools/tcl/procs_waves.tcl"
source "${dv_root}/tools/tcl/procs_run.tcl"

# Open a default database
set wavedump_db "waves.$waves"
puts "INFO: Dumping waves to $wavedump_db."
waveOpenDB $wavedump_db $waves $simulator

# Selectively choose the scopes you wish to dump
wavedumpScope $waves $simulator "/tb/dut/top_earlgrey/u_uart0" 1
wavedumpScope $waves $simulator "/tb/dut/top_earlgrey/u_spi_device" 2
wavedumpScope $waves $simulator "/tb/dut/chip_if/gpios_if"
wavedumpScope $waves $simulator "/tb/dut/top_earlgrey/u_rv_core_ibex" 2

run

quit
