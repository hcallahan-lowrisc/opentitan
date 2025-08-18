// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq extends chip_sw_rom_e2e_base_vseq;
  `uvm_object_utils(chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq)
  `uvm_object_new

  string dumped_otp_transport;
  string dumped_otp_perso_secrets;
  string dumped_bank0_transport;
  string bank0_gen;

  string RMA_UNLOCK_TOKEN_HASH_FILE;
  string RMA_UNLOCK_TOKEN_HASH_CRC_FILE;
  string PERSO_CERTGEN_INPUTS_FILE;
  string MANUF_PERSO_DATA_BACK_FILE;

  string TBS_CERTS_FILE = "tbs_certs.bin";
  string FINAL_HASH_FILE = "final_hash.bin";

  string TEST_BLOB_FILE = "test_blob.bin";

  localparam uint kLcTokenHashSerializedMaxSize = 52;
  localparam uint kManufCertgenInputsSerializedMaxSize = 210;
  localparam uint kPersoBlobSerializedMaxSize = 20535;
  localparam uint kSerdesSha256HashSerializedMaxSize = 98;

  bit [7:0] RMA_UNLOCK_TOKEN_HASH[kLcTokenHashSerializedMaxSize];
  bit [7:0] RMA_UNLOCK_TOKEN_HASH_CRC[18];
  bit [7:0] PERSO_CERTGEN_INPUTS[kManufCertgenInputsSerializedMaxSize];
  bit [7:0] MANUF_PERSO_DATA_BACK[kPersoBlobSerializedMaxSize];
  int       len1, len2, len3, len4;

  // Data received from the DEVICE
  bit [7:0] tbs_certs[];
  bit [7:0] final_hash[];

  bit [7:0] test_blob[];

  uint spinwait_timeout_ns = 30_000_000; // 30ms

  virtual task pre_start();
    super.pre_start();

    void'($value$plusargs("dumped_otp_transport=%0s", dumped_otp_transport));
    void'($value$plusargs("dumped_otp_perso_secrets=%0s", dumped_otp_perso_secrets));

    void'($value$plusargs("dumped_bank0_transport=%0s", dumped_bank0_transport));
    void'($value$plusargs("bank0_gen=%0s", bank0_gen));

    // Get the HOST->DEVICE spi_console inputs
    begin
      int fd;

      void'($value$plusargs("RMA_UNLOCK_TOKEN_HASH_FILE=%0s", RMA_UNLOCK_TOKEN_HASH_FILE));
      fd = $fopen(RMA_UNLOCK_TOKEN_HASH_FILE, "rb");
      len1 = $fread(RMA_UNLOCK_TOKEN_HASH, fd);
      $fclose(fd);

      void'($value$plusargs("RMA_UNLOCK_TOKEN_HASH_CRC_FILE=%0s", RMA_UNLOCK_TOKEN_HASH_CRC_FILE));
      fd = $fopen(RMA_UNLOCK_TOKEN_HASH_CRC_FILE, "rb");
      len2 = $fread(RMA_UNLOCK_TOKEN_HASH_CRC, fd);
      $fclose(fd);

      void'($value$plusargs("PERSO_CERTGEN_INPUTS_FILE=%0s", PERSO_CERTGEN_INPUTS_FILE));
      fd = $fopen(PERSO_CERTGEN_INPUTS_FILE, "rb");
      len3 = $fread(PERSO_CERTGEN_INPUTS, fd);
      $fclose(fd);

      void'($value$plusargs("MANUF_PERSO_DATA_BACK_FILE=%0s", MANUF_PERSO_DATA_BACK_FILE));
      fd = $fopen(MANUF_PERSO_DATA_BACK_FILE, "rb");
      len4 = $fread(MANUF_PERSO_DATA_BACK, fd);
      $fclose(fd);

      `uvm_info(`gfn, $sformatf("RMA_UNLOCK_TOKEN_HASH_FILE     :: len=%0d", len1), UVM_LOW)
      `uvm_info(`gfn, $sformatf("RMA_UNLOCK_TOKEN_HASH_CRC_FILE :: len=%0d", len2), UVM_LOW)
      `uvm_info(`gfn, $sformatf("PERSO_CERTGEN_INPUTS_FILE      :: len=%0d", len3), UVM_LOW)
      `uvm_info(`gfn, $sformatf("MANUF_PERSO_DATA_BACK_FILE     :: len=%0d", len4), UVM_LOW)
    end

    // Enable the 'chip_reg_block' tl_agent to end the simulation if the 'ok_to_end' watchdog
    // resets too many times. This ends the simulation swiftly if something has gone wrong.
    cfg.m_tl_agent_cfg.watchdog_restart_count_limit_enabled = 1'b1;

    // Set CSB inactive times to reasonable values. sys_clk is at 24 MHz, and
    // it needs to capture CSB pulses.
    cfg.m_spi_host_agent_cfg.min_idle_ns_after_csb_drop = 50;
    cfg.m_spi_host_agent_cfg.max_idle_ns_after_csb_drop = 200;

    // Configure and enable the spi-host agent.
    spi_agent_configure_flash_cmds(cfg.m_spi_host_agent_cfg);
    cfg.chip_vif.enable_spi_host = 1;
  endtask

  virtual task body();

    // SYNCHRONIZATION STRINGS

    // N.B. these strings are sent with trailing newlines, but are dropped here just for clarity
    // and since we match via a loose regex, it makes no difference to drop a trailing character.
    string SYNC_STR_READ_BOOTSTRAP_REQ         = "Bootstrap requested.";
    string SYNC_STR_READ_RMA_TOKEN             = "Waiting For RMA Unlock Token Hash ...";
    string SYNC_STR_READ_PERSO_DICE_CERTS      = "Waiting for certificate inputs ...";
    string SYNC_STR_WRITE_TBS_CERTS            = "Exporting TBS certificates ...";
    string SYNC_STR_READ_ENDORSED_CERTS        = "Importing endorsed certificates ...";
    string SYNC_STR_READ_FINISHED_CERT_IMPORTS = "Finished importing certificates.";
    string SYNC_STR_READ_PERSO_DONE            = "Personalization done.";

    string SYNC_STR_WRITE_TEST_BLOB            = "Exporting test blob now...";

    // Some other prints for logging are :
    // write_cert_to_dice_page()
    // - base_printf("Importing %s cert to %s ...\n", block->name, layout->group_name);
    // write_digest_to_dice_page()
    // - base_printf("Digesting %s page ...\n", layout->group_name);

    super.body();
    `uvm_info(`gfn, "chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq::body()", UVM_LOW)

    // `uvm_info(`gfn, "Backdoor-loading 'transport' OTP image now.", UVM_LOW)
    // cfg.mem_bkdr_util_h[Otp].load_mem_from_file(dumped_otp_transport);
    // `uvm_info(`gfn, "Backdoor-loading 'transport' Flash0 test image now.", UVM_LOW)
    // cfg.mem_bkdr_util_h[FlashBank0Data].load_mem_from_file(dumped_bank0_transport);

    `uvm_info(`gfn, "Backdoor-loading 'perso_secrets' OTP image now.", UVM_LOW)
    cfg.mem_bkdr_util_h[Otp].load_mem_from_file(dumped_otp_perso_secrets);
    `uvm_info(`gfn, "Backdoor-loading 'gen' Flash0 test image now.", UVM_LOW)
    cfg.mem_bkdr_util_h[FlashBank0Data].load_mem_from_file(bank0_gen);

    // Wait until we reach the start of the Test ROM
    `DV_WAIT(
      /*WAIT_COND_*/ cfg.sw_test_status_vif.sw_test_status == SwTestStatusInBootRom,
      /*MSG_*/ "wait timeout occurred!",
      /*TIMEOUT_NS_*/ spinwait_timeout_ns)

    // Wait for IOA4 (TestStart)
    await_ioa("IOA4");

    // TEMP: Transfer a perso_blob_test_msg...

    `uvm_info(`gfn, "Awaiting sync-str to start read of perso_blob_test_msg...", UVM_LOW)
    cfg.spi_console_h.host_spi_console_read_wait_for(SYNC_STR_WRITE_TEST_BLOB); // MAGIC STRING
    cfg.spi_console_h.host_spi_console_read_payload(test_blob, kPersoBlobSerializedMaxSize);
    begin
      integer fd = $fopen(TEST_BLOB_FILE, "w");
      $fwrite(fd, "%0s", byte_array_as_str(test_blob));
      $fclose(fd);
    end

    // The test ends at this point, and returns the endings string.
    `uvm_info(`gfn, "Awaiting sync-str for completion of personalization...", UVM_LOW)
    cfg.spi_console_h.host_spi_console_read_wait_for(SYNC_STR_READ_PERSO_DONE); // MAGIC STRING

    // The test also should have raised the error line...
    await_ioa("IOA0", 1);

    //
    ///////////////////////////////////////////////
    // Set test passed.
    override_test_status_and_finish(.passed(1'b1));
    return;
    ///////////////////////////////////////////////
    //

    // // Since we are starting with a .vmem image dumped after provisioning the flash scrambling key
    // // seeds (SECRET1) and enabling scrambling (FLASH_DATA_DEFAULT_CFG), the first spi_console
    // // activity will be waiting for the DEVICE to request the RMA Unlock Token
    // // (in personalize_otp_and_flash_secrets()).
    // cfg.spi_console_h.host_spi_console_read_wait_for(SYNC_STR_READ_RMA_TOKEN); // MAGIC STRING
    // // The device has now requested the Unlock Token. Write it over the spi console.
    // cfg.spi_console_h.host_spi_console_write_when_ready('{RMA_UNLOCK_TOKEN_HASH,
    //                                                       RMA_UNLOCK_TOKEN_HASH_CRC});

    // // After the OTP SECRET2 partition is programmed, the chip performs a SW reset.
    // // (so we need to reset the SPI console frame counter).
    // `uvm_info(`gfn, "Waiting for sw_reset() after personalize_device_secrets completion...", UVM_LOW)
    // `DV_SPINWAIT(
    //   /*WAIT_*/ cfg.chip_vif.cpu_clk_rst_if.wait_for_reset();,
    //   /*MSG_*/ "Timeout waiting for sw_reset() to occur and complete.",
    //   /*TIMEOUT_NS_*/ spinwait_timeout_ns)

    // // Wait for IOA4 (TestStart) the next time we boot the test binary after reset
    // `uvm_info(`gfn, "Device out of reset, awaiting re-boot and the assertion of TestStart.", UVM_LOW)
    // await_ioa("IOA4");

    // // At this point, personalize_otp_and_flash_secrets() has completed. Dump the state of the OTP
    // // so we can re-load from this point in the future.
    // `uvm_info(`gfn, "Dumping OTP (personalized_secrets) to disk.", UVM_LOW)
    // cfg.mem_bkdr_util_h[Otp].write_mem_to_file("dump_OTP_perso_secrets.24.vmem");

    // Next, we provision all device certificates.
    `uvm_info(`gfn, "Awaiting sync-str to start write of certificate provisioning data...", UVM_LOW)
    cfg.spi_console_h.host_spi_console_read_wait_for(SYNC_STR_READ_PERSO_DICE_CERTS); // MAGIC STRING
    cfg.spi_console_h.host_spi_console_write_when_ready('{PERSO_CERTGEN_INPUTS});

    // Wait until the device exports the TBS certificates.
    `uvm_info(`gfn, "Awaiting sync-str to start read of exported certificate payload...", UVM_LOW)
    cfg.spi_console_h.host_spi_console_read_wait_for(SYNC_STR_WRITE_TBS_CERTS); // MAGIC STRING
    //
    ///////////////////////////////////////////////
    // Set test passed.
    override_test_status_and_finish(.passed(1'b1));
    return;
    ///////////////////////////////////////////////
    //
    // Read the TBS certificate payload from the console.
    cfg.spi_console_h.host_spi_console_read_payload(tbs_certs, kPersoBlobSerializedMaxSize);
    begin
      integer fd = $fopen(TBS_CERTS_FILE, "w");
      $fwrite(fd, "%0s", byte_array_as_str(tbs_certs));
      $fclose(fd);
    end

    // Process the certificate payload...
    // Nothing to do, we already have the answer in a file.

    // Wait until the device indicates it can import the endorsed certificate files.
    `uvm_info(`gfn, "Awaiting sync-str to start write of endorsed certificates...", UVM_LOW)
    cfg.spi_console_h.host_spi_console_read_wait_for(SYNC_STR_READ_ENDORSED_CERTS); // MAGIC STRING
    cfg.spi_console_h.host_spi_console_write_when_ready('{MANUF_PERSO_DATA_BACK});

    // Wait until the device indicates it has successfully imported the endorsed certificate files.
    `uvm_info(`gfn, "Awaiting sync-str for completion of endorsed certificate import...", UVM_LOW)
    cfg.spi_console_h.host_spi_console_read_wait_for(SYNC_STR_READ_FINISHED_CERT_IMPORTS); // MAGIC STRING

    // The device checks the imported certificate package...

    // Read out the final hash sent from the device
    cfg.spi_console_h.host_spi_console_read_payload(final_hash, kSerdesSha256HashSerializedMaxSize);
    begin
      integer fd = $fopen(FINAL_HASH_FILE, "w");
      $fwrite(fd, "%0s", byte_array_as_str(final_hash));
      $fclose(fd);
    end

    // Wait until the device indicates it has successfully completed perso!
    `uvm_info(`gfn, "Awaiting sync-str for completion of personalization...", UVM_LOW)
    cfg.spi_console_h.host_spi_console_read_wait_for(SYNC_STR_READ_PERSO_DONE); // MAGIC STRING

    // Set test passed.
    override_test_status_and_finish(.passed(1'b1));

  endtask : body

  function string byte_array_as_str(bit [7:0] q[]);
    string str = "";
    foreach (q[i]) $sformat(str, "%s%0s", str, q[i]);
    return str;
  endfunction

  function string byte_q_as_str(bit [7:0] q[$]);
    string str = "";
    foreach (q[i]) $sformat(str, "%s%0s", str, q[i]);
    return str;
  endfunction

  function string byte_q_as_hex(bit [7:0] q[$]);
    string str = "";
    foreach (q[i]) $sformat(str, "%s%02x", str, q[i]);
    return str;
  endfunction

  function void print_byte_q(bit [7:0] q[$]);
    $display("Printing byte_q now...");
    foreach(q[idx]) begin
      $display("q[%0d]: 0x%02x / %0d / %0s", idx, q[idx], q[idx], q[idx]);
    end
  endfunction

endclass : chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq
