// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

package spi_console_pkg;

  import dv_utils_pkg::uint;

  import uvm_pkg::*;
  import spi_agent_pkg::*;
  import csr_utils_pkg::*;

  // macro includes
`include "uvm_macros.svh"
`include "dv_macros.svh"

  // uint default_spinwait_timeout_ns = 10_000_000; // 10ms

  // Typical SPI flash opcodes.
  typedef enum bit [7:0] {
    SpiFlashReadJedec    = 8'h9F,
    SpiFlashReadSfdp     = 8'h5A,
    SpiFlashReadNormal   = 8'h03,
    SpiFlashReadFast     = 8'h0B,
    SpiFlashReadDual     = 8'h3B,
    SpiFlashReadQuad     = 8'h6B,
    SpiFlashReadSts1     = 8'h05,
    SpiFlashReadSts2     = 8'h35,
    SpiFlashReadSts3     = 8'h15,
    SpiFlashWriteDisable = 8'h04,
    SpiFlashWriteEnable  = 8'h06,
    SpiFlashWriteSts1    = 8'h01,
    SpiFlashWriteSts2    = 8'h31,
    SpiFlashWriteSts3    = 8'h11,
    SpiFlashChipErase    = 8'hC7,
    SpiFlashSectorErase  = 8'h20,
    SpiFlashPageProgram  = 8'h02,
    SpiFlashEn4B         = 8'hB7,
    SpiFlashEx4B         = 8'hE9
  } spi_flash_cmd_e;

  typedef enum int {
    rx_ready_idx = 1,
    tx_ready_idx = 0
  } flow_ctrl_idx_e;

  class spi_console extends uvm_component;
    `uvm_component_utils(spi_console)

    virtual clk_rst_if clk_rst_vif;
    virtual pins_if #(.Width(2), .PullStrength("Weak")) flow_ctrl_vif;
    uvm_sequence seq_h;
    spi_sequencer spi_host_sequencer_h;

    function new(string name = "", uvm_component parent = null);
      super.new(name, parent);
      $display("spi_console_pkg::spi_console:new()");
    endfunction : new

    function uvm_sequence_item create_item(uvm_object_wrapper type_var,
                                           uvm_sequencer_base l_sequencer,
                                           string name);
      uvm_sequence_item item;
      uvm_coreservice_t cs = uvm_coreservice_t::get();
      uvm_factory factory = cs.get_factory();
      $cast(item, factory.create_object_by_type(type_var, seq_h.get_full_name(), name));
      item.set_item_context(seq_h, l_sequencer);
      return item;
    endfunction

    function bit findStrRe(string find, string str);
      string re_find = $sformatf("*%0s*", find);
      bit    match = !uvm_re_match(re_find, str);
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

    virtual task await_ioa(int idx, bit val = 1'b1);
      string timeout_msg = $sformatf("Timed out waiting for idx:%0d to be %0d.", idx, val);

      `uvm_info(`gfn, $sformatf("Waiting for idx:%0d to be %0d now...", idx, val), UVM_LOW)
      `DV_WAIT(flow_ctrl_vif.pins[idx] == val, timeout_msg, default_spinwait_timeout_ns)
      `uvm_info(`gfn, $sformatf("Saw idx:%0d as %0d now!", idx, val), UVM_LOW)
    endtask: await_ioa

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
      uvm_object_wrapper w_ = m_spi_host_seq.get_type();
      $cast(m_spi_host_seq, create_item(
        /*type_var*/ w_, /*l_sequencer*/ spi_host_sequencer_h, /*name*/ "m_spi_host_seq"));

      `DV_CHECK_RANDOMIZE_WITH_FATAL(m_spi_host_seq,
        opcode == SpiFlashReadNormal;
        address_q.size() == byte_addr_q.size();
        foreach (byte_addr_q[i]) address_q[i] == byte_addr_q[i];
        payload_q.size() == size;
        read_size == size;
      )

      `uvm_info(`gfn, "host_spi_console_read() - Start.", UVM_LOW)
      m_spi_host_seq.start(/*sequencer*/ spi_host_sequencer_h, /*parent_sequence*/ seq_h);
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
      bit [31:0] header_data_bytes = 0;

      // First, get the header of the current frame.
      begin : get_header
        bit [31:0] magic_number = 32'ha5a5beef;
        bit [31:0] header_magic_number;
        bit [31:0] header_frame_number;
        bit [7:0]  header_q[$];
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
        // stop us dead for now if the payload is too large.
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
      await_ioa(tx_ready_idx, 1'b1);

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
      await_ioa(tx_ready_idx, 1'b0);

    endtask : host_spi_console_read_wait_for

    ///////////////////
    // CONSOLE WRITE //
    ///////////////////
    // host_spi_console_write()
    // host_spi_console_write()
    // host_spi_console_write_buf()
    // host_spi_console_issue_write_cmd()
    // host_spi_console_wait_on_busy()

    //
    //
    //
    virtual task host_spi_console_write_when_ready(input bit [7:0] bytes[][]); // HOST -> DEVICE

      `uvm_info(`gfn, "Will write to the spi_console. Awaiting the DEVICE to set 'rx_ready' (IOA6)", UVM_LOW)
      await_ioa(rx_ready_idx, 1'b1);

      `uvm_info(`gfn, "'rx_ready' is set. Writing to the spi_console now.", UVM_LOW)
      `DV_SPINWAIT(
        // WAIT_
        foreach (bytes[i]) host_spi_console_write(bytes[i]);,
        // MSG_
        "Timeout waiting for spi_console_write_when_ready() operations to complete.",
        // TIMEOUT_NS_
        500_000
      )

      `uvm_info(`gfn, "Finished writing to the spi_console. Awaiting the DEVICE to clear 'rx_ready' (IOA6)", UVM_LOW)
      await_ioa(rx_ready_idx, 1'b0);

    endtask : host_spi_console_write_when_ready

    //
    //
    //
    virtual task host_spi_console_write(input bit [7:0] bytes[]); // HOST -> DEVICE
      uint SPI_FLASH_PAYLOAD_BUFFER_SIZE = 256; // Don't overwrite the PAYLOAD BUFFER
      bit [31:0] SPI_TX_ADDRESS = '0;
      bit [31:0] SPI_TX_LAST_CHUNK_MAGIC_ADDRESS = 9'h100;
      uint written_data_len = 0;

      `uvm_info(`gfn, $sformatf("console_write()(str) :: len = %0d : %0s", $size(bytes),
        byte_array_as_str(bytes)), UVM_LOW)

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
      uvm_object_wrapper w_ = m_spi_host_seq.get_type();
      $cast(m_spi_host_seq, create_item(
        /*type_var*/ w_, /*l_sequencer*/ spi_host_sequencer_h, /*name*/ "m_spi_host_seq"));

      m_spi_host_seq.opcode = SpiFlashPageProgram;
      m_spi_host_seq.address_q = {addr[23:16], addr[15:8], addr[7:0]};
      for (int i = 0; i < bytes_q_size; i++) begin
        m_spi_host_seq.payload_q.push_back(bytes_q.pop_front());
      end

      `uvm_info(`gfn, "host_spi_console_write_buf() - Start.", UVM_LOW)
      `uvm_info(`gfn, $sformatf("Sending payload data_bytes(hex) : 0x%0s", byte_q_as_hex(m_spi_host_seq.payload_q)), UVM_LOW)
      `uvm_info(`gfn, $sformatf("Sending payload data_bytes(str) : %0s", byte_q_as_str(m_spi_host_seq.payload_q)), UVM_LOW)
      host_spi_console_issue_write_cmd(m_spi_host_seq);
      `uvm_info(`gfn, "host_spi_console_write_buf() - End.", UVM_LOW)
    endtask : host_spi_console_write_buf

    //
    //
    //
    virtual task host_spi_console_issue_write_cmd(spi_host_flash_seq write_seq);

      // First, enable writes.
      spi_host_flash_seq m_spi_host_seq;
      uvm_object_wrapper w_ = m_spi_host_seq.get_type();
      $cast(m_spi_host_seq, create_item(
        /*type_var*/ w_, /*l_sequencer*/ spi_host_sequencer_h, /*name*/ "m_spi_host_seq"));
      m_spi_host_seq.opcode = SpiFlashWriteEnable;
      m_spi_host_seq.start(/*sequencer*/ spi_host_sequencer_h,
                           /*parent_sequence*/ seq_h);

      // Next, perform the write
      write_seq.start(/*sequencer*/ spi_host_sequencer_h, /*parent_sequence*/ seq_h);

      // Finally, wait for busy to be cleared
      host_spi_console_wait_on_busy();

    endtask : host_spi_console_issue_write_cmd

    //
    //
    //
    virtual task host_spi_console_wait_on_busy(uint timeout_ns = default_spinwait_timeout_ns,
                                               uint min_interval_ns = 1000);
      spi_host_flash_seq m_spi_host_seq;
      uvm_object_wrapper w_ = m_spi_host_seq.get_type();
      $cast(m_spi_host_seq, create_item(
        /*type_var*/ w_, /*l_sequencer*/ spi_host_sequencer_h, /*name*/ "m_spi_host_seq"));

      `DV_SPINWAIT(
        // WAIT_
        do begin
          // Wait before polling.
          #(min_interval_ns);
          clk_rst_vif.wait_clks($urandom_range(1, 100));

          `DV_CHECK_RANDOMIZE_WITH_FATAL(m_spi_host_seq,
            opcode == SpiFlashReadSts1;
            address_q.size() == 0;
            payload_q.size() == 1;
            read_size == 1;
          )
          m_spi_host_seq.start(/*sequencer*/ spi_host_sequencer_h, /*parent_sequence*/ seq_h);

          // Check the busy bit (bit[0]), loop while busy (=1)
        end while (m_spi_host_seq.rsp.payload_q[0][0] === 1);,
        // MSG_
        $sformatf("Timed-out (%0d ns) before the SPI Flash reported not-busy after a write operation", timeout_ns),
        // TIMEOUT_NS_
        timeout_ns
      )
    endtask : host_spi_console_wait_on_busy

  endclass : spi_console

endpackage : spi_console_pkg
