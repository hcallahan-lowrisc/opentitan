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

  uint spinwait_timeout_ns = 30_000_000; // 30ms
  uint write_timeout_ns = 20_000_000; // 20ms
  uint min_interval_ns = 50_000;

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
    `uvm_component_new

    virtual clk_rst_if clk_rst_vif;
    virtual pins_if #(.Width(2), .PullStrength("Weak")) flow_ctrl_vif;
    uvm_sequence seq_h;
    spi_sequencer spi_host_sequencer_h;

    // Define a custom local macro which functions like `uvm_create_on except using
    // the parent sequence 'seq_h' and sequencer 'spi_host_sequencer_h'.
    `ifndef spi_console_create_on
      `define spi_console_create_on(SEQ_) \
        begin \
          uvm_object_wrapper type_var = SEQ_.get_type(); \
          // Create item, returned attached to a uvm_sequence_item handle, so \
          // cast to the original subclass sequence type handle \
          $cast(SEQ_, create_on_seq_h(type_var, `"SEQ_`")); \
        end
    `endif

    // This local macro behaves like `uvm_send, but again uses the the parent sequence
    // 'seq_h' and sequencer 'spi_host_sequencer_h'
    `ifndef spi_console_send
      `define spi_console_send(SEQ_) \
        begin \
          SEQ_.start(/*sequencer*/ spi_host_sequencer_h, /*parent_sequence*/ seq_h); \
        end
    `endif

    // This function replaces the 'create_item()' method in the uvm base classes,
    // except 'seq_h' is always used as the parent_seq, and 'spi_host_sequencer_h' is always
    // used as the sequencer.
    function uvm_sequence_item create_on_seq_h(uvm_object_wrapper type_var, string name = "");

      // Get factory
      uvm_coreservice_t cs = uvm_coreservice_t::get();
      uvm_factory factory = cs.get_factory();
      // Use factory to construct the object
      uvm_object obj = factory.create_object_by_type(type_var, seq_h.get_full_name(), name);
      // Cast object to assign to the uvm_sequence_item handle
      uvm_sequence_item item;
      $cast(item, obj);
      // Attach new sequence object to parent sequence / sequencer registered with the class.
      item.set_item_context(seq_h, spi_host_sequencer_h);

      return item;
    endfunction

    function bit findStrRe(string find, string str);
      string re_find = $sformatf("*%0s*", find);
      bit    match = !uvm_re_match(re_find, str);
      // After negation, match = 1 / nomatch = 0
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

    virtual task await_ioa(int idx, bit val = 1'b1);
      string timeout_msg = $sformatf("Timed out waiting for idx:%0d to be %0d.", idx, val);

      `uvm_info(`gfn, $sformatf("Waiting for idx:%0d to be %0d now...", idx, val), UVM_HIGH)
      `DV_WAIT(flow_ctrl_vif.pins[idx] == val, timeout_msg, spinwait_timeout_ns)
      `uvm_info(`gfn, $sformatf("Saw idx:%0d as %0d now!", idx, val), UVM_HIGH)
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
    // host_spi_console_read_payload()

    // Drive a single ReadNormal operation from the DEVICE spi console.
    //
    //
    virtual task host_spi_console_read(input int        size,
                                       input bit [31:0] addr,
                                       ref bit [7:0]    chunk_q[$]); // DEVICE -> HOST
      // Set the flash read address
      bit [7:0] byte_addr_q[$] = {addr[23:16], addr[15:8], addr[7:0]};

      spi_host_flash_seq m_spi_host_seq;
      `spi_console_create_on(m_spi_host_seq);

      `DV_CHECK_RANDOMIZE_WITH_FATAL(m_spi_host_seq,
        opcode == SpiFlashReadNormal;
        address_q.size() == byte_addr_q.size();
        foreach (byte_addr_q[i]) address_q[i] == byte_addr_q[i];
        payload_q.size() == size;
        read_size == size;
      )

      `uvm_info(`gfn, "host_spi_console_read() - Start.", UVM_HIGH)
      `spi_console_send(m_spi_host_seq)
      `uvm_info(`gfn, "host_spi_console_read() - End.", UVM_HIGH)

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

      // Add an arbitrary delay here to slow things down.
      // The ottf_console_spi.c code in spi_device_send_frame() relies on manually querying the
      // value of CSB (via reading the HW status register) and observing it change state 4 times
      // to know that two full SPI transfers have taken place.
      // If there is not adequate space between the two transfers, the software will miss its
      // measurement here of the chip select returning high/inactive.
      #(min_interval_ns);
      clk_rst_vif.wait_clks($urandom_range(100, 1000));

      // Next, get all the data_bytes from the frame.
      while (header_data_bytes > 0) begin
        bit [7:0] data_q[$] = {};
        host_spi_console_read(.size(header_data_bytes), .addr(SPI_FRAME_HEADER_SIZE), .chunk_q(data_q));
        `uvm_info(`gfn, $sformatf("Got data_bytes in chunk : %0s", byte_q_as_str(data_q)), UVM_HIGH)
        // #TODO Assume we read all bytes in one go, for now. The DV_CHECK_EQ in the header block will
        // stop us dead for now if the payload is too large.
        header_data_bytes = 0;

        // Append the bytes from this read transfer to the overall queue.
        chunk_q = {chunk_q, data_q};
      end

      // Again, add the arbitrary delay to allow the DEVICE sw time to ready CSB low to detect the
      // end of the frame.
      #(min_interval_ns);
      clk_rst_vif.wait_clks($urandom_range(100, 1000));

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
      `uvm_info(`gfn, "DEVICE set 'tx_ready' now.", UVM_LOW)

      // Next, get all the data_bytes from the frame until we see the expected message in the buffer.
      do begin
        bit [7:0] data_q[$] = {};
        host_spi_console_read_frame(.chunk_q(data_q));
        `uvm_info(`gfn, $sformatf("Got data_bytes : %0s", byte_q_as_str(data_q)), UVM_LOW)
        // Append the bytes from this read transfer to the overall queue.
        chunk_q = {chunk_q, data_q};
      end while (!findStrRe(wait_for, byte_q_as_str(chunk_q)));
      `uvm_info(`gfn, "Got the expected string in the spi_console.", UVM_LOW)

      // (If not already de-asserted) wait for the SPI console TX ready to be cleared by the DEVICE.
      `uvm_info(`gfn, "Waiting for the DEVICE to clear 'tx_ready' (IOA5)", UVM_LOW)
      await_ioa(tx_ready_idx, 1'b0);
      `uvm_info(`gfn, "DEVICE cleared 'tx_ready' now.", UVM_LOW)

    endtask : host_spi_console_read_wait_for

    //
    //
    // For this method, we know the expected payload length. If the 
    //
    virtual task host_spi_console_read_payload(ref bit [7:0] outbuf[], input int len); // DEVICE -> HOST
      bit [7:0] payload_byte_q[$] = {};
      int       len_ctr = 0;
      `uvm_info(`gfn, $sformatf("Awaiting read_payload of %0d bytes", len), UVM_LOW)

      `uvm_info(`gfn, "Waiting for the DEVICE to set 'tx_ready' (IOA5)", UVM_LOW)
      await_ioa(tx_ready_idx, 1'b1);
      `uvm_info(`gfn, "DEVICE set 'tx_ready' now.", UVM_LOW)

      // Next, get all the data_bytes from the frame until we've got the expected number of bytes.
      while (len_ctr < len) begin
        bit [7:0] frame_byte_q[$] = {};
        host_spi_console_read_frame(.chunk_q(frame_byte_q));
        `uvm_info(`gfn, $sformatf("Got %0d data bytes in frame : %0s", frame_byte_q.size(), byte_q_as_str(frame_byte_q)), UVM_LOW)
        payload_byte_q = {payload_byte_q, frame_byte_q};
        len_ctr += frame_byte_q.size();
        `uvm_info(`gfn, $sformatf("Got %0d / %0d data bytes in expected payload.", len_ctr, len), UVM_LOW)

        // If the payload isn't complete, wait for the device to indicate the next frame is ready...
        if (len_ctr < len) begin
          await_ioa(tx_ready_idx, 1'b0);
          await_ioa(tx_ready_idx, 1'b1);
        end

      end

      // (If not already de-asserted) wait for the SPI console TX ready to be cleared by the DEVICE.
      `uvm_info(`gfn, "Waiting for the DEVICE to clear 'tx_ready' (IOA5)", UVM_LOW)
      await_ioa(tx_ready_idx, 1'b0);
      `uvm_info(`gfn, "DEVICE cleared 'tx_ready' now.", UVM_LOW)

      outbuf = {>>{payload_byte_q}};
    endtask : host_spi_console_read_payload

    ///////////////////
    // CONSOLE WRITE //
    ///////////////////
    // host_spi_console_wait_on_busy()
    // host_spi_console_write_op()
    // host_spi_console_write_buf()
    // host_spi_console_write_when_ready()
    // host_spi_console_write()

    //
    //
    //
    virtual task host_spi_console_wait_on_busy(uint timeout_ns = spinwait_timeout_ns,
                                               uint min_interval_ns = 1000);
      spi_host_flash_seq m_spi_host_seq;
      `spi_console_create_on(m_spi_host_seq);

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
          `spi_console_send(m_spi_host_seq)

          // Check the busy bit (bit[0]), loop while busy (=1)
        end while (m_spi_host_seq.rsp.payload_q[0][0] === 1);,
        // MSG_
        $sformatf("Timed-out (%0d ns) before the SPI Flash reported not-busy after a write operation", timeout_ns),
        // TIMEOUT_NS_
        timeout_ns
      )
    endtask : host_spi_console_wait_on_busy

    //
    //
    //
    virtual task host_spi_console_write_op(spi_host_flash_seq write_seq);

      // First, enable writes.
      spi_host_flash_seq m_spi_host_seq;
      `spi_console_create_on(m_spi_host_seq);
      m_spi_host_seq.opcode = SpiFlashWriteEnable;
      `spi_console_send(m_spi_host_seq)

      // Next, perform the write
      `spi_console_send(write_seq)

      // Finally, wait for busy to be cleared
      host_spi_console_wait_on_busy();

    endtask : host_spi_console_write_op


    //
    //
    //
    virtual task host_spi_console_write_buf(input bit [7:0] bytes_q[$], input bit[31:0] addr); // HOST -> DEVICE
      uint bytes_q_size = bytes_q.size();

      spi_host_flash_seq m_spi_host_seq;
      `spi_console_create_on(m_spi_host_seq);

      m_spi_host_seq.opcode = SpiFlashPageProgram;
      m_spi_host_seq.address_q = {addr[23:16], addr[15:8], addr[7:0]};
      for (int i = 0; i < bytes_q_size; i++) begin
        m_spi_host_seq.payload_q.push_back(bytes_q.pop_front());
      end

      `uvm_info(`gfn, "host_spi_console_write_buf() - Start.", UVM_HIGH)
      `uvm_info(`gfn, $sformatf("Sending payload data_bytes(hex) : 0x%0s", byte_q_as_hex(m_spi_host_seq.payload_q)), UVM_HIGH)
      `uvm_info(`gfn, $sformatf("Sending payload data_bytes(str) : %0s", byte_q_as_str(m_spi_host_seq.payload_q)), UVM_HIGH)
      host_spi_console_write_op(m_spi_host_seq);
      `uvm_info(`gfn, "host_spi_console_write_buf() - End.", UVM_HIGH)
    endtask : host_spi_console_write_buf


    //
    //
    //
    virtual task host_spi_console_write(input bit [7:0] bytes[]); // HOST -> DEVICE
      uint SPI_FLASH_PAYLOAD_BUFFER_SIZE = 256; // Don't overwrite the PAYLOAD BUFFER
      bit [31:0] SPI_TX_ADDRESS = '0;
      bit [31:0] SPI_TX_LAST_CHUNK_MAGIC_ADDRESS = 9'h100;
      uint written_data_len = 0;

      `uvm_info(`gfn, $sformatf("console_write() :: len=%0d : %0s", $size(bytes),
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
                  $sformatf("console_write() :: remaining=%0d, chunk_len=%0d, addr=32'h%8x",
                            remaining_len, chunk_len, write_address),
                  UVM_MEDIUM)
        begin
          bit [7:0] bytes_q[$];
          for (int i = 0; i < chunk_len; i++) begin
            bytes_q.push_back(bytes[i + written_data_len]);
          end
          host_spi_console_write_buf(bytes_q, write_address);
        end
        written_data_len += chunk_len;
      end while ($size(bytes) - written_data_len > 0);

    endtask : host_spi_console_write


    //
    //
    //
    virtual task host_spi_console_write_when_ready(input bit [7:0] bytes[][]); // HOST -> DEVICE

      `uvm_info(`gfn, "Will write to the spi_console. Awaiting the DEVICE to set 'rx_ready' (IOA6)", UVM_LOW)
      await_ioa(rx_ready_idx, 1'b1);
      `uvm_info(`gfn, "DEVICE set 'rx_ready' now.", UVM_LOW)

      `DV_SPINWAIT(
        // WAIT_
        foreach (bytes[i]) host_spi_console_write(bytes[i]);,
        // MSG_
        "Timeout waiting for spi_console_write_when_ready() operations to complete.",
        // TIMEOUT_NS_
        write_timeout_ns
      )

      `uvm_info(`gfn, "Finished writing to the spi_console. Awaiting the DEVICE to clear 'rx_ready' (IOA6)", UVM_LOW)
      await_ioa(rx_ready_idx, 1'b0);
      `uvm_info(`gfn, "DEVICE cleared 'rx_ready' now.", UVM_LOW)

    endtask : host_spi_console_write_when_ready

    `undef spi_console_create_on
    `undef spi_console_send

  endclass : spi_console

endpackage : spi_console_pkg
