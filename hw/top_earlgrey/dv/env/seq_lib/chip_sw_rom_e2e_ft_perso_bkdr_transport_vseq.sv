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
  string PERSO_CERTGEN_INPUTS_FILE;
  string MANUF_PERSO_DATA_BACK_FILE;

  bit [7:0] RMA_UNLOCK_TOKEN_HASH[52];
  bit [7:0] RMA_UNLOCK_TOKEN_HASH_CRC[18];
  bit [7:0] PERSO_CERTGEN_INPUTS[210];
  bit [7:0] MANUF_PERSO_DATA_BACK[20535];
  int       len1, len2, len3, len4;

  function void log_l(string str);
    `uvm_info(`gfn, str, UVM_LOW)
  endfunction

  function bit findStrRe(string find, string str);
    string re_find = $sformatf("*%0s*", find);
    bit match = !uvm_re_match(re_find, str);
    // match = 0, nomatch = 1
    if (match) begin
      `uvm_info(`gfn,
                $sformatf("findStrRe() MATCH=%0d, string: \"%s\", regex: \"%s\"",
                          match, str, re_find),
                UVM_LOW)
    end
    return match;
  endfunction

  function bit [31:0] reverse_endianess(bit [31:0] inp);
    return {>>{ {<<8{inp}} }};
  endfunction

  function void test_re();
    string wait_for = "Waiting For RMA Unlock Token Hash";
    string re_wait_for = $sformatf("*%0s*", wait_for);
    bit [7:0] q[$] = {<<{wait_for}};
    bit [7:0] q2[$] = {>>{wait_for}};

    // log_l(re_wait_for);
    // log_l($sformatf("bin = 'b%b", wait_for));
    // log_l($sformatf("hex = 'h%x", wait_for));
    // log_l($sformatf("dec = 'd%d", wait_for));
    // log_l($sformatf("p         = %p", wait_for));
    // log_l($sformatf("p ( q[$]) = %p", q));
    // log_l($sformatf("p (q2[$]) = %p", q2));

    // begin
    //   bit match;
    //   match = findStrRe(re_wait_for, wait_for); // TRUE
    //   log_l($sformatf("match = %0d", match));
    //   match = findStrRe(re_wait_for, "Waiting For RMA Token Hash"); // FALSE
    //   log_l($sformatf("match = %0d", match));
    //   match = findStrRe(re_wait_for, "aaaa Waiting For RMA Unlock Token Hash bbbbbb");
    //   log_l($sformatf("match = %0d", match));
    // end

    // begin
    //   bit [7:0] header_q[$] = '{'hef, 'hbe, 'ha5, 'ha5, 'h0, 'h0, 'h0, 'h0, 'h26, 'h0, 'h0, 'h0};
    //   bit [31:0] magic_num = 32'ha5a5beef;

    //   bit [31:0] header_magic_number = {>>{header_q[ 0: 3]}}; // 32'hefbea5a5
    //   bit [31:0] header_frame_number = {>>{header_q[ 4: 7]}}; // 32'h00000000
    //   bit [31:0] header_data_bytes =   {>>{header_q[ 8:11]}}; // 32'h26000000

    //   `uvm_info(`gfn, $sformatf("Got header : %0p", header_q), UVM_LOW)
    //   `uvm_info(`gfn, $sformatf("Got header : 0x%0s", byte_q_as_hex(header_q)), UVM_LOW)
    //   `uvm_info(`gfn, $sformatf("Expected Magic Number : 32h%02x", magic_num), UVM_LOW)
    //   `uvm_info(`gfn,
    //             $sformatf("Got result      :: Magic Number : 32'h%02x Frame Number : 32'h%02x, Num_Data_Bytes : 32'h%02x",
    //                       header_magic_number, header_frame_number, header_data_bytes),
    //             UVM_LOW)

    //   header_magic_number = stream_word(header_magic_number);
    //   header_frame_number = stream_word(header_frame_number);
    //   header_data_bytes   = stream_word(header_data_bytes);
    //   `uvm_info(`gfn,
    //             $sformatf("Streamed result :: Magic Number : 32'h%02x Frame Number : 32'h%02x, Num_Data_Bytes : 32'h%02x",
    //                       header_magic_number, header_frame_number, header_data_bytes),
    //             UVM_LOW)
    // end

    // `uvm_fatal(`gfn, "Early exit.")
  endfunction

  virtual task pre_start();
    super.pre_start();

    void'($value$plusargs("dumped_otp_transport=%0s", dumped_otp_transport));
    void'($value$plusargs("dumped_bank0_transport=%0s", dumped_bank0_transport));

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

    // TEST
    test_re();
  endtask

  virtual task body();

    // SYNCHRONIZATION STRINGS

    string SYNC_STR_READ_BOOTSTRAP_REQ = "Bootstrap requested.\n";
    string SYNC_STR_READ_RMA_TOKEN = "Waiting For RMA Unlock Token Hash ...\n";
    string SYNC_STR_READ_PERSO_DICE_CERTS = "Waiting for certificate inputs ...\n";
    string SYNC_STR_WRITE_TBS_CERTS = "Exporting TBS certificates ...\n";
    string SYNC_STR_READ_ENDORSED_CERTS = "Importing endorsed certificates ...\n";
    string SYNC_STR_READ_FINISHED_CERT_IMPORTS = "Finished importing certificates.\n";
    string SYNC_STR_READ_PERSO_DONE = "Personalization done.\n";

    // Some other prints for logging are :
    // write_cert_to_dice_page()
    // - base_printf("Importing %s cert to %s ...\n", block->name, layout->group_name);
    // write_digest_to_dice_page()
    // - base_printf("Digesting %s page ...\n", layout->group_name);

    super.body();
    `uvm_info(`gfn, "chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq::body()", UVM_LOW)

    `uvm_info(`gfn, "Backdoor-loading 'transport' OTP image now.", UVM_LOW)
    cfg.mem_bkdr_util_h[Otp].load_mem_from_file(dumped_otp_transport);
    `uvm_info(`gfn, "Backdoor-loading 'transport' Flash0 test image now.", UVM_LOW)
    cfg.mem_bkdr_util_h[FlashBank0Data].load_mem_from_file(dumped_bank0_transport);

    // Wait until we reach the start of the Test ROM
    `DV_WAIT(cfg.sw_test_status_vif.sw_test_status == SwTestStatusInBootRom)

    // Wait for IOA4 (TestStart)
    await_ioa("IOA4");

    // Since we are starting with a .vmem image dumped after provisioning the flash scrambling key
    // seeds (SECRET1) and enabling scrambling (FLASH_DATA_DEFAULT_CFG), the first spi_console
    // activity will be waiting for the DEVICE to request the RMA Unlock Token
    // (in personalize_otp_and_flash_secrets()).
    host_spi_console_read_wait_for(SYNC_STR_READ_RMA_TOKEN); // MAGIC STRING

    // The device has now requested the Unlock Token.
    // Write it over the spi console.

    `DV_SPINWAIT(
      // WAIT_
      begin
        `uvm_info(`gfn, "Will write to the spi_console. Awaiting the DEVICE to set 'rx_ready' (IOA6)", UVM_LOW)
        await_ioa("IOA6", 1'b1);

        `uvm_info(`gfn, "'rx_ready' is set. Writing to the spi_console now.", UVM_LOW)
        host_spi_console_write(RMA_UNLOCK_TOKEN_HASH);
        host_spi_console_write(RMA_UNLOCK_TOKEN_HASH_CRC);

        `uvm_info(`gfn, "Finished writing to the spi_console. Awaiting the DEVICE to clear 'rx_ready' (IOA6)", UVM_LOW)
        await_ioa("IOA6", 1'b0);
      end,
      // MSG_
      "Timeout waiting for the RMA_UNLOCK_TOKEN spi_console_write() operations to complete." ,
      // TIMEOUT_NS_
      500_000)

    // After the OTP SECRET2 partition is programmed, the chip performs a SW reset.
    // (so we need to reset the SPI console frame counter).
    // #TODO wait and observe a reset cycle

    // Wait for IOA4 (TestStart) the next time we boot the test binary after reset
    await_ioa("IOA4", 1'b0);
    await_ioa("IOA4", 1'b1);

    // At this point, personalize_otp_and_flash_secrets() has completed. Dump the state of the OTP
    // so we can re-load from this point in the future.
    `uvm_info(`gfn, "Dumping OTP (personalized_secrets) to disk.", UVM_LOW)
    cfg.mem_bkdr_util_h[Otp].write_mem_to_file("dump_OTP_perso_secrets.24.vmem");

    // Next, we provision all device certificates.
    host_spi_console_read_wait_for(SYNC_STR_READ_PERSO_DICE_CERTS); // MAGIC STRING

    `DV_SPINWAIT(
      // WAIT_
      begin
        `uvm_info(`gfn, "Will write to the spi_console. Awaiting the DEVICE to set 'rx_ready' (IOA6)", UVM_LOW)
        await_ioa("IOA6", 1'b1);

        `uvm_info(`gfn, "'rx_ready' is set. Writing to the spi_console now.", UVM_LOW)
        host_spi_console_write(PERSO_CERTGEN_INPUTS);

        `uvm_info(`gfn, "Finished writing to the spi_console. Awaiting the DEVICE to clear 'rx_ready' (IOA6)", UVM_LOW)
        await_ioa("IOA6", 1'b0);
      end,
      // MSG_
      "Timeout waiting for the PERSO_CERTGEN_INPUTS spi_console_write() operations to complete.",
      // TIMEOUT_NS_
      500_000)

    // Wait until the device exports the TBS certificates.
    host_spi_console_read_wait_for(SYNC_STR_WRITE_TBS_CERTS); // MAGIC STRING

    ///////////////////////////////////////////////
    // Set test passed.
    override_test_status_and_finish(.passed(1'b1));
    return;
    ///////////////////////////////////////////////

    //
    // #TODO Read the spi console, but for the TBS certificate payload this time.

    // Process the certificate payload...
    // Nothing to do, we already have the answer in a file.

    // Wait until the device indicates it can import the endorsed certificate files.
    host_spi_console_read_wait_for(SYNC_STR_READ_ENDORSED_CERTS); // MAGIC STRING

    `DV_SPINWAIT(
      // WAIT_
      begin
        `uvm_info(`gfn, "Will write to the spi_console. Awaiting the DEVICE to set 'rx_ready' (IOA6)", UVM_LOW)
        await_ioa("IOA6", 1'b1);

        `uvm_info(`gfn, "'rx_ready' is set. Writing to the spi_console now.", UVM_LOW)
        host_spi_console_write(MANUF_PERSO_DATA_BACK);

        `uvm_info(`gfn, "Finished writing to the spi_console. Awaiting the DEVICE to clear 'rx_ready' (IOA6)", UVM_LOW)
        await_ioa("IOA6", 1'b0);
      end,
      // MSG_
      "Timeout waiting for the MANUF_PERSO_DATA_BACK spi_console_write() operations to complete.",
      // TIMEOUT_NS_
      500_000)

    // Wait until the device indicates it has successfully imported the endorsed certificate files.
    host_spi_console_read_wait_for(SYNC_STR_READ_FINISHED_CERT_IMPORTS); // MAGIC STRING

    // The device checks the imported certificate package...

    // Wait until the device indicates it has successfully completed perso!
    host_spi_console_read_wait_for(SYNC_STR_READ_PERSO_DONE); // MAGIC STRING

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
  //
  // DEVICE->HOST transfers
  // (READS from our perspective)
  //
  //     FRAME STRUCTURE
  //
  //      -----------------------------------------------
  //      |      Magic Number     | 4-bytes  |          |
  //      -----------------------------------|          |
  //      |      Frame Number     | 4-bytes  |  Header  |
  //      -----------------------------------|          |
  //      |   Data Length (bytes) | 4-bytes  |          |
  //      -----------------------------------|----------|
  //      |      Data (word aligned)         |          |
  //      -----------------------------------|   Data   |
  //      |     0xFF Pad Bytes    | <4-bytes |          |
  //      -----------------------------------|----------|
  //
  //     - tx_ready_gpio (IOA5 here...)
  //       - Flow-control mechanism for DEVICE->HOST transfers
  //       - ENABLED for ft_personalize.c (`console_tx_indicator.enable = true`)
  //       - The DEVICE sets the 'tx_ready' gpio when the SPI console buffer has data, and clears
  //         the gpio when there is no longer data available.
  //       - When using the TX-indicator pin feature, we always write each SPI frame at the
  //         beginning of the flash buffer, and wait for the host to read it out before writing
  //         another frame.
  //
  //
  // HOST->DEVICE transfers
  // (WRITES from our perspective)
  //
  //     - DEVICE signals ready by asserting RX-indicator (RxReady)
  //     - Message is chunked in payloads, each of which are written (via upload command) to address zero.
  //       - After each upload, HOST polls busy to await the DEVICE to read back the buffer.
  //     - For final chunk, HOST uploads it to a special address (SPI_TX_LAST_CHUNK_MAGIC_ADDRESS)
  //     - After DEVICE reads the final chunk, it de-asserts the RX-indicator (RxReady)
  //


  //////////////////
  // CONSOLE READ //
  //////////////////
  // host_spi_console_read()
  // host_spi_console_read_frame()
  // host_spi_console_read_wait_for()

  // Drive a single ReadNormal operation from the DEVICE spi console.
  //
  //
  virtual task host_spi_console_read(input int        size,
                                     input bit [31:0] addr,
                                     ref bit [7:0]    chunk_q[$]); // DEVICE -> HOST
    // Set the flash read address
    bit [7:0] byte_addr_q[$] = {addr[23:16], addr[15:8], addr[7:0]};

    spi_host_flash_seq m_spi_host_seq;
    `uvm_create_on(m_spi_host_seq, p_sequencer.spi_host_sequencer_h);

    `DV_CHECK_RANDOMIZE_WITH_FATAL(m_spi_host_seq,
      opcode == SpiFlashReadNormal;
      address_q.size() == byte_addr_q.size();
      foreach (byte_addr_q[i]) address_q[i] == byte_addr_q[i];
      payload_q.size() == size;
      read_size == size;
    )

    `uvm_info(`gfn, "host_spi_console_read() - Start.", UVM_LOW)
    `uvm_send(m_spi_host_seq)
    `uvm_info(`gfn, "host_spi_console_read() - End.", UVM_LOW)

    // Get data out of the sequence once completed.
    foreach (m_spi_host_seq.rsp.payload_q[i]) chunk_q.push_back(m_spi_host_seq.rsp.payload_q[i]);

  endtask : host_spi_console_read

  // Read a single frame from the DEVICE spi console.
  //
  //
  virtual task host_spi_console_read_frame(ref bit [7:0] chunk_q[$]); // DEVICE -> HOST
    uint SPI_FLASH_READ_BUFFER_SIZE = 2048; // Don't overwrite our PAYLOAD BUFFER
    uint SPI_MAX_DATA_LENGTH = 2036;
    uint SPI_FRAME_HEADER_SIZE = 12;
    bit [31:0] header_data_bytes;

    // First, get the header of the current frame.
    begin : get_header
      bit [31:0] magic_number = 32'ha5a5beef;
      bit [31:0] header_magic_number;
      bit [31:0] header_frame_number;
      bit [7:0] header_q[$];
      host_spi_console_read(.size(SPI_FRAME_HEADER_SIZE), .addr(0), .chunk_q(header_q));
      header_magic_number = reverse_endianess({>>{header_q[0:3]}});
      header_frame_number = reverse_endianess({>>{header_q[4:7]}});
      header_data_bytes =   reverse_endianess({>>{header_q[8:11]}});
      `uvm_info(`gfn, $sformatf("Got header : 0x%0s", byte_q_as_hex(header_q)), UVM_LOW)
      `uvm_info(`gfn, $sformatf("Got header : %0p", header_q), UVM_LOW)
      `uvm_info(`gfn,
                $sformatf("Magic Number : 0x%02x Frame Number : 0x%02x, Num_Data_Bytes : 0x%02x",
                          header_magic_number, header_frame_number, header_data_bytes),
                UVM_LOW)
      `DV_CHECK_EQ(header_magic_number, magic_number, "Incorrect SPI Console Header MAGIC_NUM")
      `DV_CHECK_LT(header_data_bytes, SPI_MAX_DATA_LENGTH, "Cannot handle this many data bytes!")
    end

    // Next, get all the data_bytes from the frame.
    while (header_data_bytes > 0) begin
      bit [7:0] data_q[$];
      host_spi_console_read(.size(header_data_bytes), .addr(SPI_FRAME_HEADER_SIZE), .chunk_q(data_q));
      `uvm_info(`gfn, $sformatf("Got data_bytes : %0s", byte_q_as_str(data_q)), UVM_LOW)
      // #TODO Assume we read all bytes in one go, for now. The DV_CHECK_EQ in the header block will
      // stop us for now if the payload is too large.
      header_data_bytes = 0;

      // Append the bytes from this read transfer to the overall queue.
      chunk_q = {chunk_q, data_q};
    end

  endtask : host_spi_console_read_frame

  //
  //
  //
  virtual task host_spi_console_read_wait_for(input string wait_for); // DEVICE -> HOST
    bit [7:0] chunk_q[$];
    string    chunk_q_as_str;

    `uvm_info(`gfn, $sformatf("Waiting for following string in the spi_console : %0s", wait_for), UVM_LOW)

    `uvm_info(`gfn, "Waiting for the DEVICE to set 'tx_ready' (IOA5)", UVM_LOW)
    await_ioa("IOA5", 1'b1);

    // Next, get all the data_bytes from the frame until we see the expected message in the buffer.
    do begin
      bit [7:0] data_q[$];
      host_spi_console_read_frame(.chunk_q(data_q));
      `uvm_info(`gfn, $sformatf("Got data_bytes : %0s", byte_q_as_str(data_q)), UVM_LOW)
      // Append the bytes from this read transfer to the overall queue.
      chunk_q = {chunk_q, data_q};
    end while (!findStrRe(wait_for, byte_q_as_str(chunk_q)));

    `uvm_info(`gfn, "Got the expected string in the spi_console.", UVM_LOW)

    // (If not already de-asserted) wait for the SPI console TX ready to be cleared by the DEVICE.
    `uvm_info(`gfn, "Waiting for the DEVICE to clear 'tx_ready' (IOA5)", UVM_LOW)
    await_ioa("IOA5", 1'b0);

  endtask : host_spi_console_read_wait_for

  ///////////////////
  // CONSOLE WRITE //
  ///////////////////
  // host_spi_console_write()
  // host_spi_console_write_buf()

  //
  //
  //
  virtual task host_spi_console_write(input bit [7:0] bytes[]); // HOST -> DEVICE
    uint SPI_FLASH_PAYLOAD_BUFFER_SIZE = 256; // Don't overwrite the PAYLOAD BUFFER
    bit [31:0] SPI_TX_ADDRESS = '0;
    bit [31:0] SPI_TX_LAST_CHUNK_MAGIC_ADDRESS = 9'h100;
    uint written_data_len = 0;

    `uvm_info(`gfn,
              $sformatf("console_write()(str) :: len = %0d : %0s",
                        $size(bytes), byte_array_as_str(bytes)),
              UVM_LOW)

    do begin
      // - chunk_len holds the size of the current chunk we are about to write
      // - write_address is the address the current chunk will be written to
      uint chunk_len;
      bit [31:0] write_address;

      uint remaining_len = $size(bytes) - written_data_len;

      if (remaining_len > SPI_FLASH_PAYLOAD_BUFFER_SIZE) begin
        // If the remaining data cannot fit inside a single write operation
        // (limited by the size of the DEVICE payload buffer size), then
        // just send a max-size chunk this time around.
        chunk_len = SPI_FLASH_PAYLOAD_BUFFER_SIZE;
        write_address = SPI_TX_ADDRESS;
      end else begin
        // The remaining data fits in a single chunk. Send this chunk to the
        // MAGIC_ADDRESS to signal to the DEVICE it is the final chunk.
        chunk_len = remaining_len;
        write_address = SPI_TX_LAST_CHUNK_MAGIC_ADDRESS;
      end
      `uvm_info(`gfn,
                $sformatf("console_write() :: bytes=%0d, chunk_len=%0d, remaining=%0d, addr=32'h%8x",
                          $size(bytes), chunk_len, remaining_len, write_address),
                UVM_LOW)
      begin
        bit [7:0] bytes_q[$];
        for (int i = 0; i < chunk_len; i++) begin
          bytes_q.push_back(bytes[i + written_data_len]);
        end
        `uvm_info(`gfn,
                  $sformatf("bytes_q.size() = %0d", bytes_q.size()),
                  UVM_LOW)
        host_spi_console_write_buf(bytes_q, write_address);
      end
      written_data_len += chunk_len;
    end while ($size(bytes) - written_data_len > 0);

  endtask : host_spi_console_write

  //
  //
  //
  virtual task host_spi_console_write_buf(input bit [7:0] bytes_q[$], input bit[31:0] addr); // HOST -> DEVICE
    uint bytes_q_size = bytes_q.size();
    spi_host_flash_seq m_spi_host_seq;
    `uvm_create_on(m_spi_host_seq, p_sequencer.spi_host_sequencer_h);
    m_spi_host_seq.opcode = SpiFlashPageProgram;
    m_spi_host_seq.address_q = {addr[23:16], addr[15:8], addr[7:0]};
    for (int i = 0; i < bytes_q_size; i++) begin
      m_spi_host_seq.payload_q.push_back(bytes_q.pop_front());
    end

    `uvm_info(`gfn, "host_spi_console_write_buf() - Start.", UVM_LOW)
    `uvm_info(`gfn, $sformatf("Sending payload data_bytes(hex) : 0x%0s", byte_q_as_hex(m_spi_host_seq.payload_q)), UVM_LOW)
    `uvm_info(`gfn, $sformatf("Sending payload data_bytes(str) : %0s", byte_q_as_str(m_spi_host_seq.payload_q)), UVM_LOW)
    spi_host_flash_issue_write_cmd(m_spi_host_seq);
    `uvm_info(`gfn, "host_spi_console_write_buf() - End.", UVM_LOW)
  endtask : host_spi_console_write_buf

endclass : chip_sw_rom_e2e_ft_perso_bkdr_transport_vseq
