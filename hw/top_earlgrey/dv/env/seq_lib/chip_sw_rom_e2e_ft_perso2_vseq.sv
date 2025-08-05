// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_rom_e2e_ft_perso_dump_vseq extends chip_sw_rom_e2e_base_vseq;
  `uvm_object_utils(chip_sw_rom_e2e_ft_perso_dump_vseq)
  `uvm_object_new

  virtual task body();
    super.body();

    `uvm_info(`gfn, "chip_sw_rom_e2e_ft_perso_dump_vseq::body()", UVM_LOW)

    // IOA6 (GPIO4) is for SPI console RX ready signal.
    // IOA5 (GPIO3) is for SPI console TX ready signal.
    // IOA4 (GPIO0) is for test start reporting.
    // IOA1 (GPIO1) is for test done reporting.
    // IOA0 (GPIO2) is for error reporting.

    `uvm_info(`gfn, "SPI-Bootstrapping FLASH SlotA...", UVM_MEDIUM)
    cfg.chip_vif.sw_straps_if.drive(3'h7);
    cfg.use_spi_load_bootstrap = 1'b1;
    spi_device_load_bootstrap({cfg.sw_images[SwTypeTestSlotA], ".64.vmem"});
    cfg.use_spi_load_bootstrap = 1'b0;
    `uvm_info(`gfn, "SPI-Bootstrapping FLASH SlotA complete.", UVM_MEDIUM)

    // POR is asserted at the end of the bootstrap process.
    // Wait for the chip to restart, and the boot-rom to complete
    // and load the bootstrapped Flash image.

    // Wait for IOA4 (TestStart)
    await_ioa("IOA4");

    `uvm_info(`gfn, "Dumping Flash (init-image) to disk.", UVM_LOW)
    cfg.mem_bkdr_util_h[FlashBank0Data].write_mem_to_file("dump_FlashBank0Data_init.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank1Data].write_mem_to_file("dump_FlashBank1Data_init.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank0Info].write_mem_to_file("dump_FlashBank0Info_init.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank1Info].write_mem_to_file("dump_FlashBank1Info_init.64.scr.vmem");

    // Wait for IOA5 (SPI console TX ready), for the first point the software is awaiting HOST input
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
    cfg.use_spi_load_bootstrap = 1'b1;
    `uvm_info(`gfn, "SPI-Bootstrapping FLASH SlotA...", UVM_MEDIUM)
    spi_device_load_bootstrap({cfg.sw_images[SwTypeTestSlotA], ".64.vmem"}); // Un-scrambled image
    cfg.use_spi_load_bootstrap = 1'b0;
    `uvm_info(`gfn, "SPI-Bootstrapping FLASH SlotA complete.", UVM_MEDIUM)

    // Again, POR is asserted at the end of the bootstrap process.
    // Wait for the chip to reboot and load the transport-image to Flash.

    // Wait for IOA4 (TestStart)
    await_ioa("IOA4");

    // Now, the final transport image has been loaded into flash, and we can dump it again to
    // get images suitable for backdoor-loading
    // Also, dump the OTP state right now, which should contain the new scrambling keys deployed
    // by the init-image.
    `uvm_info(`gfn, "Dumping OTP to disk.", UVM_LOW)
    cfg.mem_bkdr_util_h[Otp].write_mem_to_file("dump_OTP_transportinit.24.vmem");
    `uvm_info(`gfn, "Dumping Flash (transport-image) to disk.", UVM_LOW)
    cfg.mem_bkdr_util_h[FlashBank0Data].write_mem_to_file("dump_FlashBank0Data_transport.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank1Data].write_mem_to_file("dump_FlashBank1Data_transport.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank0Info].write_mem_to_file("dump_FlashBank0Info_transport.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank1Info].write_mem_to_file("dump_FlashBank1Info_transport.64.scr.vmem");

    // Wait for IOA5 (SPI console TX ready)
    // > This should now be the point where the device is waiting for SPI Console input, marked by
    // > the following message to the console:
    // > > "Waiting For RMA Unlock Token Hash ..."
    await_ioa("IOA5");

    // Set test passed.
    override_test_status_and_finish(.passed(1'b1));
  endtask

endclass : chip_sw_rom_e2e_ft_perso_dump_vseq
