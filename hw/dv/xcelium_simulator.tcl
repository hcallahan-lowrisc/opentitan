# xmsim tcl-interpreter
##########################

database -open $wavedump_db -shm -default

probe -create tb -depth all
probe -create $uvm:{uvm_test_top} -depth all -transaction

# Enable 'transaction_recording' within UVM
uvm_set -config "*" "recording_detail" UVM_FULL
