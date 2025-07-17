// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_rom_e2e_ft_perso2_vseq extends chip_sw_rom_e2e_base_vseq;
  `uvm_object_utils(chip_sw_rom_e2e_ft_perso2_vseq)
  `uvm_object_new

  virtual task body();
    super.body();

    `uvm_info(`gfn, "chip_sw_rom_e2e_ft_perso2_vseq::body()", UVM_LOW)

    `uvm_info(`gfn, "SPI-Bootstrapping FLASH SlotA...", UVM_MEDIUM)
    spi_device_load_bootstrap({cfg.sw_images[SwTypeTestSlotA], ".64.vmem"});
    cfg.use_spi_load_bootstrap = 1'b0;
    `uvm_info(`gfn, "SPI-Bootstrapping FLASH SlotA complete.", UVM_MEDIUM)

    // `uvm_info(`gfn, "Initializing SPI flash bootstrap.", UVM_LOW)
    // spi_device_load_bootstrap({cfg.sw_images[SwTypeTestSlotA], ".64.vmem"});
    // `uvm_info(`gfn, "SPI flash bootstrap done.", UVM_LOW)
    // cfg.use_spi_load_bootstrap = 1'b0;

    // Wait for SRAM initialization to complete a second time (after bootstrap).
    // `uvm_info(`gfn, "Waiting for SRAM initialization to complete (after bootstrap).", UVM_LOW)
    // `DV_WAIT(cfg.chip_vif.sram_ret_init_done == 1,
    //          $sformatf({"Timeout occurred when waiting for SRAM initialization; ",
    //                     "Current sram_ret_init_done = 1'%0b, Timeout value = %0dns"},
    //                     cfg.chip_vif.sram_ret_init_done,
    //                     cfg.sw_test_timeout_ns),
    //          cfg.sw_test_timeout_ns)
    // `uvm_info(`gfn, "ROM SRAM initialization done.", UVM_LOW)

    // typedef enum {
    //   FlashBank0Data,
    //   FlashBank1Data,
    //   FlashBank0Info,
    //   FlashBank1Info,
    //   ICacheWay0Tag,
    //   ICacheWay1Tag,
    //   ICacheWay0Data,
    //   ICacheWay1Data,
    //   UsbdevBuf,
    //   OtbnDmem[16],
    //   OtbnImem,
    //   Otp,
    //   RamMain[16],
    //   RamRet[16],
    //   Rom
    // } chip_mem_e;
    //
    // typedef enum {
    //   SwTypeRom       = 0, // Ibex SW - first stage boot ROM.
    //   SwTypeTestSlotA = 1, // Ibex SW - test SW in (flash) slot A.
    //   SwTypeTestSlotB = 2, // Ibex SW - test SW in (flash) slot B.
    //   SwTypeOtbn      = 3, // Otbn SW
    //   SwTypeOtp       = 4, // Customized OTP image
    //   SwTypeDebug     = 5  // Debug SW - injected into SRAM.
    // } sw_type_e;

    cfg.mem_bkdr_util_h[FlashBank0Data].write_mem_to_file("dump_FlashBank0Data.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank1Data].write_mem_to_file("dump_FlashBank1Data.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank0Info].write_mem_to_file("dump_FlashBank0Info.64.scr.vmem");
    cfg.mem_bkdr_util_h[FlashBank1Info].write_mem_to_file("dump_FlashBank1Info.64.scr.vmem");

    // Wait for IOA4
    `DV_WAIT(cfg.chip_vif.mios[top_earlgrey_pkg::MioPadIoa4] == '1,
             $sformatf("Timed out waiting for IOA4 to go high."),
             cfg.sw_test_timeout_ns)

    // Wait for IOA1 (perso done GPIO indicator) to toggle on.
    // `DV_WAIT(cfg.chip_vif.mios[top_earlgrey_pkg::MioPadIoa1] == '1,
    //          $sformatf("Timed out waiting for IOA1 to go high."),
    //          cfg.sw_test_timeout_ns)

    // Set test passed.
    override_test_status_and_finish(.passed(1'b1));
  endtask

endclass : chip_sw_rom_e2e_ft_perso2_vseq
