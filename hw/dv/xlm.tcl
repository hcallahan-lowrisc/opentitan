# simvision tcl-interpreter
############################
# input yaml/core_ibex_simvision_preferences.svcf

# console -> send to 'xmsim'
# console submit -using simulator "input xcelium_simulator.tcl"
input "${dv_root}/xcelium_simulator.tcl"

# Build the UVM heirarchy (run to the end of the build phase)
# (We cannot reference UVM objects until they have been built.)
uvm_phase -stop_at build -end
# Run to the stop.
run
