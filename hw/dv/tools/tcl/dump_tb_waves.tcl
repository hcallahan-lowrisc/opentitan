# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
#
################################################################################
#
# TCL script to setup a default waves dump of the entire testbench scope in simulation
#
################################################################################

# First, check the wave-file format / simulator combination are compatible
checkWaveformFileCompat $simulator $waves

# A global variable representing the file id (fid) of the waves dumped in VPD format.
setDefault vpd_fid 0

set wavedump_db "waves.$waves"
puts "INFO: Dumping waves to $wavedump_db."

# Open a default database to capture the probed waveforms into
waveOpenDB $wavedump_db $waves $simulator

# Add a waveform probe starting at the scope of $tb_top, with infinite depth
wavedumpScope $waves $simulator $tb_top 0
