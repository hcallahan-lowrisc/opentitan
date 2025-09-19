set dv_root ""
if {[info exists ::env(dv_root)]} {
  set dv_root "$::env(dv_root)"
} else {
  puts "ERROR: Script run without dv_root environment variable."
  quit
}

set simulator "vcs"
set waves "fsdb"
set gui 0
set tb_top "tb"

proc wavedumpScope {scope {depth 0} {fsdb_flags "+all"} {probe_flags "-all"} {dump_flags "-aggregates"}} {
    fsdbDumpvars $depth $scope $fsdb_flags
}

set wavedump_db "waves.$waves"
puts "INFO: Dumping waves in [string toupper $waves] format to $wavedump_db."

run 120000us

# fsdbDumpfile $wavedump_db
# wavedumpScope "/tb/dut/top_earlgrey/u_flash_ctrl"
# wavedumpScope "/tb/dut/top_earlgrey/u_uart0"
# wavedumpScope "/tb/dut/top_earlgrey/u_spi_device"
# wavedumpScope "/tb/dut/chip_if/gpios_if"

wavedumpScope $tb_top

run

quit
