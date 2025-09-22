# tools/tcl

This directory contains 

## default_waves_dump.tcl

This is sourced by all supported simulators.
The driver scripts (dvsim.py) need to make sure that we don't ask for an unsupported
dumping format (SHM with VCS, for example).

To explicitly list the hierarchies to dump, use the wavedumpScope proc instead.

## Dumping waves in specific hierarchies.

By default, if wave dumping is enabled, all hierarchies of the top level testbench are dumped.
For large designs, this may slow down the simulation considerably.

```tcl
# Dumping waves in specific hierarchies (example):
wavedumpScope $waves $simulator tb.dut.foo.bar 12
wavedumpScope $waves $simulator tb.dut.baz 0
```

# Example custom waveform dump script



```tcl
# my_dump_script.tcl

# BOILERPLATE
# ↓
if {[info exists ::env(dv_root)]} {set dv_root "$::env(dv_root)";} \
else {puts "ERROR: Script run without dv_root environment variable."; exit;}
# Helper procedure libraries
source "${dv_root}/tools/tcl/procs.tcl"
source "${dv_root}/tools/tcl/procs_waves.tcl"
source "${dv_root}/tools/tcl/procs_run.tcl"
# ↑
# BOILERPLATE

# Set the global variables used by the default procedures (could also use EnvVar values)
set simulator "vcs"
set waves "fsdb"
set gui 0

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
```

Then to use the script with the `dvsim` tool:

```
util/dvsim/dvsim.py <sim_cfg.hjson> -i <test> --fixed-seed=1 --dump-script=my_dump_script.tcl
```
