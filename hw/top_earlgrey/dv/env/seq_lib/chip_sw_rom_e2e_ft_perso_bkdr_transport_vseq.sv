// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq extends chip_sw_rom_e2e_base_vseq;
  `uvm_object_utils(chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq)
  `uvm_object_new

  string dumped_otp_transport;
  string dumped_bank0_transport;

  string RMA_UNLOCK_TOKEN_HASH_FILE;
  string RMA_UNLOCK_TOKEN_HASH_CRC_FILE;
  string MANUF_PERSO_DATA_BACK_FILE;
  string PERSO_CERTGEN_INPUTS_FILE;

  bit [7:0] RMA_UNLOCK_TOKEN_HASH[];
  bit [7:0] RMA_UNLOCK_TOKEN_HASH_CRC[];
  bit [7:0] MANUF_PERSO_DATA_BACK[];
  bit [7:0] PERSO_CERTGEN_INPUTS[];

  virtual task pre_start();
    int fd;
    super.pre_start();

    void'($value$plusargs("dumped_otp_transport=%0s", dumped_otp_transport));
    void'($value$plusargs("dumped_bank0_transport=%0s", dumped_bank0_transport));

    // Get the HOST->DEVICE spi_console inputs
    void'($value$plusargs("RMA_UNLOCK_TOKEN_HASH_FILE=%0s", RMA_UNLOCK_TOKEN_HASH_FILE));
    fd = $fopen(RMA_UNLOCK_TOKEN_HASH_FILE, "rb");
    $fread(RMA_UNLOCK_TOKEN_HASH, fd);
    $fclose(fd);

    void'($value$plusargs("RMA_UNLOCK_TOKEN_HASH_CRC_FILE=%0s", RMA_UNLOCK_TOKEN_HASH_CRC_FILE));
    fd = $fopen(RMA_UNLOCK_TOKEN_HASH_CRC_FILE, "rb");
    $fread(RMA_UNLOCK_TOKEN_HASH_CRC, fd);
    $fclose(fd);

    void'($value$plusargs("MANUF_PERSO_DATA_BACK_FILE=%0s", MANUF_PERSO_DATA_BACK_FILE));
    fd = $fopen(MANUF_PERSO_DATA_BACK_FILE, "rb");
    $fread(MANUF_PERSO_DATA_BACK, fd);
    $fclose(fd);

    void'($value$plusargs("PERSO_CERTGEN_INPUTS_FILE=%0s", PERSO_CERTGEN_INPUTS_FILE));
    fd = $fopen(PERSO_CERTGEN_INPUTS_FILE, "rb");
    $fread(PERSO_CERTGEN_INPUTS, fd);
    $fclose(fd);

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
    super.body();
    `uvm_info(`gfn, "chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq::body()", UVM_LOW)

    `uvm_info(`gfn, "Backdoor-loading 'transport' OTP image now.", UVM_LOW)
    cfg.mem_bkdr_util_h[Otp].load_mem_from_file(dumped_otp_transport);
    `uvm_info(`gfn, "Backdoor-loading 'transport' Flash0 test image now.", UVM_LOW)
    cfg.mem_bkdr_util_h[FlashBank0Data].load_mem_from_file(dumped_bank0_transport);

    // Wait for the DEVICE to execute the ROM and then boot the Flash0 transport image.

    // Wait for IOA4 (TestStart)
    await_ioa("IOA4");

    // Since we are starting with a .vmem image dumped after provisioning the flash scrambling key
    // seeds (SECRET1) and enabling scrambling (FLASH_DATA_DEFAULT_CFG), the first spi_console
    // activity will be waiting for the DEVICE to request the RMA Unlock Token
    // (in personalize_otp_and_flash_secrets()).
    host_spi_console_read_wait_for("Waiting For RMA Unlock Token Hash"); // MAGIC STRING

    // The device has now requested the Unlock Token.
    // Write it over the spi console.

    `DV_SPINWAIT(
      // WAIT_
      begin
        host_spi_console_write(RMA_UNLOCK_TOKEN_HASH);
        host_spi_console_write(RMA_UNLOCK_TOKEN_HASH_CRC);
      end,
      // MSG_
      "Timeout waiting for the RMA_UNLOCK_TOKEN spi_console_write() to complete." ,
      // TIMEOUT_NS_
      5_000)

    // Set test passed.
    override_test_status_and_finish(.passed(1'b1));
  endtask

  function bit findStrRe(string re, string str);
    bit match = uvm_re_match(re, str);
    // if match begin
    //   $display("findStrRe() MATCH=%0d, string: \"%s\", regex: \"%s\"", match, str, re);
    // end
    $display("findStrRe() MATCH=%0d, string: \"%s\", regex: \"%s\"", match, str, re);
    return match;
  endfunction

  function string byte_queue_as_str(logic[7:0] q[$]);
    string str = "";
    foreach (q[i]) $sformat(str, "%s%0s", str, q[i]);
    return str;
  endfunction

  // spi_console impl
  //
  // CONSTANTS
  // const SPI_FRAME_HEADER_SIZE           : usize =   12;
  // const SPI_FLASH_READ_BUFFER_SIZE      : u32   = 2048;
  // const SPI_FLASH_PAYLOAD_BUFFER_SIZE   : usize =  256;
  // const SPI_MAX_DATA_LENGTH             : usize = 2036;
  // const SPI_FRAME_MAGIC_NUMBER          : u32   = 0xa5a5beef;
  // const SPI_TX_LAST_CHUNK_MAGIC_ADDRESS : u32   =      0x100;
  // const SPI_BOOT_MAGIC_PATTERN          : u32   = 0xcafeb002;
  //
  // - tx_ready_gpio (IOA5 here...)
  //   - Flow-control mechanism for DEVICE->HOST transfers
  //   - ENABLED for ft_personalize.c (`console_tx_indicator.enable = true`)
  //   - The DEVICE sets the 'tx_ready' gpio when the SPI console buffer has data, and clears
  //     the gpio when there is no longer data available.
  //   - When using the TX-indicator pin feature, we always write each SPI frame at the
  //     beginning of the flash buffer, and wait for the host to read it out before writing
  //     another frame.
  //
  // HOST->DEVICE transfers
  // - DEVICE signals ready by asserting RX-indicator (RxReady)
  // - Message is chunked in payloads, each of which are written (via upload command) to address zero.
  //   - After each upload, HOST polls busy to await the DEVICE to read back the buffer.
  // - For final chunk, HOST uploads it to a special address (SPI_TX_LAST_CHUNK_MAGIC_ADDRESS)
  // - After DEVICE reads the final chunk, it de-asserts the RX-indicator (RxReady)
  //
  virtual task host_spi_console_read(ref bit [7:0] chunk_q[$]); // DEVICE -> HOST
    bit [7:0] byte_addr_q[$] = {};
    bit [31:0] flash_read_addr = '0; // Address 0.

    bit [7:0] payload_q[$];
    uint payload_size = 64;

    spi_host_flash_seq m_spi_host_seq;
    `uvm_create_on(m_spi_host_seq, p_sequencer.spi_host_sequencer_h);

    `uvm_info(`gfn, "host_spi_console_read() - Start.", UVM_LOW)

    // Set the flash address
    byte_addr_q = {byte_addr_q, flash_read_addr[23:16], flash_read_addr[15:8], flash_read_addr[7:0]};

    `DV_CHECK_RANDOMIZE_WITH_FATAL(m_spi_host_seq,
                                   opcode == SpiFlashReadNormal;
                                   address_q.size() == byte_addr_q.size();
                                   foreach (byte_addr_q[i]) address_q[i] == byte_addr_q[i];
                                   payload_q.size() == payload_size;
                                   read_size == payload_size;)
    `uvm_send(m_spi_host_seq)
    // Get data out of the sequence once completed.
    chunk_q = m_spi_host_seq.rsp.payload_q;

    // `uvm_info(`gfn, "Printing payload_q from host_spi_console_read().", UVM_LOW)
    // foreach(payload_q[idx]) begin
    //   $display("payload_q[%0d]: 0x%02x / %0d / %0s", idx, payload_q[idx], payload_q[idx], payload_q[idx]);
    // end
  endtask

  virtual task host_spi_console_read_wait_for(string wait_for); // DEVICE -> HOST
    bit [7:0] chunk_q[$];
    string    chunk_q_as_str;
    string    re_wait_for = $sformatf(".*%0s.*", wait_for);

    `uvm_info(`gfn, $sformatf("Waiting for following string in the spi_console : %0s", wait_for), UVM_LOW)

    `uvm_info(`gfn, "Waiting for the DEVICE to set 'tx_ready' (IOA5)", UVM_LOW)
    await_ioa("IOA5", 1'b1);

    do begin
      bit [7:0] q[$];
      host_spi_console_read(q);
      chunk_q = {chunk_q, q};
      `uvm_info(`gfn, "Finished host_spi_console_read(), current chunk_q_as_str...", UVM_LOW)
      `uvm_info(`gfn, $sformatf("Printing queue now :\n %0s", byte_queue_as_str(q)), UVM_LOW)
    end while (!findStrRe(re_wait_for, byte_queue_as_str(chunk_q)));

    `uvm_info(`gfn, "Got the expected string in the spi_console.", UVM_LOW)

    // (If not already de-asserted) wait for the SPI console TX ready to be cleared by the DEVICE.
    `uvm_info(`gfn, "Waiting for the DEVICE to clear 'tx_ready' (IOA5)", UVM_LOW)
    await_ioa("IOA5", 1'b0);
  endtask

  virtual task host_spi_console_write(ref bit [7:0] bytes[]); // HOST -> DEVICE
    uint SPI_FLASH_PAYLOAD_BUFFER_SIZE = 256; // Don't overwrite the PAYLOAD BUFFER
    bit [31:0] SPI_TX_ADDRESS = '0;
    bit [31:0] SPI_TX_LAST_CHUNK_MAGIC_ADDRESS = 9'h100;
    uint bytes_remaining = $size(bytes);

    `uvm_info(`gfn, "Will write to the spi_console. Awaiting the DEVICE to set 'rx_ready' (IOA6)", UVM_LOW)
    await_ioa("IOA6", 1'b1);

    `uvm_info(`gfn, "'rx_ready' is set. Writing to the spi_console now.", UVM_LOW)
    host_spi_console_write_buf(bytes, SPI_TX_ADDRESS);

    // do begin
    //   host_spi_console_write_buf(bytes[63:0]);
    // end while ();

    `uvm_info(`gfn, "Finished writing to the spi_console. Awaiting the DEVICE to clear 'rx_ready' (IOA6)", UVM_LOW)
    await_ioa("IOA6", 1'b0);

  endtask

  virtual task host_spi_console_write_buf(ref bit [7:0] bytes[], bit[31:0] addr); // HOST -> DEVICE
    bit [7:0] byte_addr_q[$] = {};
    uint payload_size = 64;

    spi_host_flash_seq m_spi_host_seq;
    `uvm_create_on(m_spi_host_seq, p_sequencer.spi_host_sequencer_h);

    `uvm_info(`gfn, "host_spi_console_write_buf() - Start.", UVM_LOW)

    m_spi_host_seq.opcode = SpiFlashPageProgram;
    m_spi_host_seq.address_q = {addr[23:16], addr[15:8], addr[7:0]};
    for (int i = 0; i < payload_size; i++) begin
      m_spi_host_seq.payload_q.push_back(bytes[i]);
    end
    spi_host_flash_issue_write_cmd(m_spi_host_seq);
  endtask

endclass : chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq
