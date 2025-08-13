// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_rom_e2e_ft_perso_vseq extends chip_sw_rom_e2e_base_vseq;
  `uvm_object_utils(chip_sw_rom_e2e_ft_perso_vseq)
  `uvm_object_new

  string dumped_bank0_init;

  virtual task body();
    super.body();

    `uvm_info(`gfn, "chip_sw_rom_e2e_ft_perso_vseq::body()", UVM_LOW)

    `uvm_info(`gfn, "Backdoor-loading 'init' Flash0 test image now.", UVM_LOW)
    void'($value$plusargs("dumped_bank0_init=%0s", dumped_bank0_init));
    cfg.mem_bkdr_util_h[FlashBank0Data].load_mem_from_file(dumped_bank0_init);

    // Wait until we reach the start of the Test ROM
    `DV_WAIT(cfg.sw_test_status_vif.sw_test_status == SwTestStatusInBootRom)

    // Wait for IOA4 (TestStart)
    await_ioa("IOA4");

    // Wait for IOA5 (SPI console TX ready), where the device would send the following string:
    // "Bootstrap requested.\n"
    await_ioa("IOA5");

    // At this point, the test binary has already written to the CreatorSwCfg flash data region default
    // Hence, we need to reset the chip and re-bootstrap a new binary that is loaded into flash
    // with the new scrambling key
    // (aka. the final transport image)

    `uvm_info(`gfn, "Resetting chip.", UVM_LOW)
    assert_por_reset();

    // Drive SW straps for bootstrap.
    `uvm_info(`gfn, "Driving SW straps high for bootstrap.", UVM_LOW)
    cfg.chip_vif.sw_straps_if.drive(3'h7);
    `uvm_info(`gfn, "Initializing SPI flash bootstrap.", UVM_LOW)
    spi_device_load_bootstrap({cfg.sw_images[SwTypeTestSlotA], ".64.vmem"}); // Un-scrambled image
    `uvm_info(`gfn, "SPI flash bootstrap done.", UVM_LOW)
    cfg.use_spi_load_bootstrap = 1'b0;

    // Wait for IOA4 (TestStart)
    await_ioa("IOA4");

    `uvm_info(`gfn, "Dumping OTP to disk.", UVM_LOW)
    cfg.mem_bkdr_util_h[Otp].write_mem_to_file("dump_OTP_transportinit.24.vmem");

    // Now, the final transport image has been loaded into flash, and we can dump it again to
    // get images suitable for backdoor-loading
    `uvm_info(`gfn, "Dumping Flash to disk.", UVM_LOW)
    cfg.mem_bkdr_util_h[FlashBank0Data].write_mem_to_file("dump_FlashBank0Data_transport.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank1Data].write_mem_to_file("dump_FlashBank1Data_transport.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank0Info].write_mem_to_file("dump_FlashBank0Info_transport.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank1Info].write_mem_to_file("dump_FlashBank1Info_transport.64.scr.vmem");

    // Wait for IOA5 (SPI console TX ready), where the device would send the following string:
    // "Waiting For RMA Unlock Token Hash ...\n"
    await_ioa("IOA5");

    // Set test passed.
    override_test_status_and_finish(.passed(1'b1));
  endtask

endclass : chip_sw_rom_e2e_ft_perso_vseq
