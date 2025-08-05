// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_rom_e2e_ft_perso3_vseq extends chip_sw_rom_e2e_base_vseq;
  `uvm_object_utils(chip_sw_rom_e2e_ft_perso3_vseq)
  `uvm_object_new

  string dumped_bank0_init = "/home/harry/projects/opentitan/binaries/dump_FlashBank0Data.64.scr.vmem";

  string dumped_otp_transport = "/home/harry/projects/opentitan/binaries/dump_OTP_transportinit.24.vmem";
  string dumped_bank0_transport = "/home/harry/projects/opentitan/binaries/dump_FlashBank0Data_transport.64.scr.vmem";

  virtual task pre_start();
    super.pre_start();

    // Enable the 'chip_reg_block' tl_agent to end the simulation if the 'ok_to_end' watchdog
    // resets too many times. This ends the simulation swiftly if something has gone wrong.
    cfg.m_tl_agent_cfg.watchdog_restart_count_limit_enabled = 1'b1;
  endtask

  virtual task body();
    super.body();
    `uvm_info(`gfn, "chip_sw_rom_e2e_ft_perso3_vseq::body()", UVM_LOW)

    `uvm_info(`gfn, "Backdoor-loading 'transport' OTP image now.", UVM_LOW)
    cfg.mem_bkdr_util_h[Otp].load_mem_from_file(dumped_otp_transport);

    // `uvm_info(`gfn, "Backdoor-loading 'transport' Flash0 test image now.", UVM_LOW)
    // cfg.mem_bkdr_util_h[FlashBank0Data].load_mem_from_file(dumped_bank0_transport);

    // Wait for IOA4 (TestStart)
    await_ioa("IOA4");

    fork
      // Wait for IOA5 (SPI console TX ready), for the first point the software is awaiting HOST input
      await_ioa("IOA5");
      // Wait for IOA0 (ErrorReporting)
      // (temporarily added to the block we should now be reaching which awaits SPI console input)
      await_ioa("IOA0");
      // Wait for IOA1 (TestDoneReporting)
      // (temporarily added to the block we should now be reaching which awaits SPI console input)
      await_ioa("IOA1");
    join

    // Set test passed.
    override_test_status_and_finish(.passed(1'b1));
  endtask

endclass : chip_sw_rom_e2e_ft_perso3_vseq
