// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//
// A purely-combinational module to validate the Command Descriptor and extract fields/properties
// that are required during command execution.
//
// We are required to detect any 'illegal or invalid combination of fields' in Command Descriptors
// (TCRI 6.4.1.10).
//
// The current Command Descriptor may be from one of the following sources:
// - HCI Command Queue; descriptor was constructed by the software driver.
// - Auto-Command handling; internally-constructed descriptor for 'DISEC' after IBI.

module i3c_cmd_decode
  import i3c_consts_pkg::*;
  import i3c_controller_pkg::*;
  import i3c_hci_pkg::*;
  import i3c_pkg::*;
#(
  // Number of blocked address settings supported.
  parameter int unsigned NumBlocked = i3c_pkg::NumBlocked,
  // Number of entries in the DAT.
  parameter int unsigned NumDATEntries = i3c_pkg::NumDATEntries,

  // Derived parameters.
  localparam int unsigned DATAddrW = $clog2(NumDATEntries)
) (
  // No requirement for clock or reset.

  // Is this the first phase of the current transfer?
  input                             first_phase_i,
  // Does the current phase follow a repeated start (Sr) rather than stop (P)?
  input                             rep_start_i,

  // State information about non-initial phases.
  // - phases after this one, i.e, zero for the final phase.
  input               [CmdRepW-1:0] reps_left_i,
  // - DAT index for the current phase.
  input              [DATAddrW-1:0] dev_index_i,

  // DAT entry for device-dependent properties.
  input  i3c_dat_mem_t              dat_entry_i,

  // Decode the `Auto Command Descriptor` rather than that from the command queue?
  input                             use_auto_i,
  // Command Descriptor from the Command Queue.
  input                      [63:0] cmd_queue_i,  // 2 DWORDs.
  // Auto Command Descriptor (Auto-Command and automatic DISEC commands).
  input                      [63:0] cmd_auto_i,   // 2 DWORDs.

  // Configuration.
  input                             use_bcst_addr_i,
  input                       [6:0] addr_blocked_i[NumBlocked],
  input                       [6:0] mask_blocked_i[NumBlocked],

  // Interpretations of the Command Descriptor.
  output i3c_xfer_cmd_intern_ctrl_t cmd_intn_o,   // Internal Control commands.
  output i3c_xfer_cmd_addr_assgn_t  cmd_daa_o,    // Address Assignment commands.
  output i3c_xfer_cmd_combo_t       cmd_combo_o,  // Combo commands.
  output i3c_xfer_cmd_reg_t         cmd_reg_o,    // Regular commands.
  output i3c_xfer_cmd_imm_t         cmd_imm_o,    // Immediate commands.

  // Initial validity check of a Command Descriptor.
  output logic                      init_ok_o,

  // Properties of the Command Descriptor, derived from `cmd_raw` combinationally.
  output i3c_ctrl_cmd_attrs_t       cmd_attrs_o,

  // output i3c_ctrl_phase_attrs_t  phase_attrs_o,

  // Indicates that the Command Descriptor is invalid for one or more reasons;
  // - the TCRI permits only 'NotSupported' in response to an invalid command.
  output logic                      err_o,

  // Indicates that the Command Phase shall not proceed because the addressed Target is blocked.
  output logic                      blocked_o

  // Additional information presented in the Controller-side registers may be of diagnostic use.
  // TODO(#31307): Supply additional information?
);

  // The Command Descriptor to be decoded may come from multiple sources:
  // - Command Queue (supplied by the HCI driver software).
  // - Auto Command support (includes automatic generation of DISEC after NACKing an IBI).
  // - Scheduled Commands are presently not supported, but they too would be handled here.
  wire [63:0] cmd_raw = use_auto_i ? cmd_auto_i : cmd_queue_i;

  // Reinterpret the raw Command Descriptor as each supported type of command.
  // - `cmd_reg_o` is a useful way to access fields that are common to most/all command types.
  assign cmd_intn_o  = i3c_xfer_cmd_intern_ctrl_t'(cmd_raw);
  assign cmd_daa_o   = i3c_xfer_cmd_addr_assgn_t'(cmd_raw);
  assign cmd_combo_o = i3c_xfer_cmd_combo_t'(cmd_raw);
  assign cmd_imm_o   = i3c_xfer_cmd_imm_t'(cmd_raw);
  assign cmd_reg_o   = i3c_xfer_cmd_reg_t'(cmd_raw);

  // HDR-DDR mode?
  // - `device` field of DAT entry: 0 = I3C, 1 = I2C (HCI Table 130).
  // - may be trusted only once the `cmd_attr` field has been checked.
  wire hdr_ddr = (cmd_reg_o.mode == XferMode_HDRDDR) & !dat_entry_i.device;

  // The decision on the validity of the command must be performed before commencing command
  // dispatch, because the dispatch decision depends upon the validity of certain command fields.
  //
  // If the initial checks pass, the following fields of `cmd_imm_o`, `cmd_reg_o` and `cmd_combo_o`
  // may then be trusted:
  //   - `attr`
  //   - `data_length`
  //
  // These are important for the dispatch decision, and rejecting invalid commands that would
  // otherwise deadlock the Controller and Driver.
  always_comb begin
    // Is this a Common Command Code transfer?
    unique case (cmd_reg_o.cmd_attr)
      CmdAttr_ImmTransfer,
      CmdAttr_RegTransfer: begin
        // HCI version 1.2 supports CCC Framing in SDR only (not HDR modes), but the CMD field may
        // be valid for HDR-DDR transfers too, so CP requires qualification here.
        // - `device` field of DAT entry: 0 = I3C, 1 = I2C (HCI Table 130).
        cmd_attrs_o.is_ccc = cmd_reg_o.cp & !hdr_ddr;
      end
      // Combo Transfers do not support CCCs (TCRI Table 10).
      CmdAttr_ComboTransfer:  cmd_attrs_o.is_ccc = 1'b0;
      CmdAttr_AddrAssignment: cmd_attrs_o.is_ccc = 1'b1;
      default: cmd_attrs_o.is_ccc = 1'b0;
    endcase
    // Some CCCs are prohibited in Command Descriptors (TCRI 6.2).
    init_ok_o = !(cmd_attrs_o.is_ccc & tcri_blocked_ccc(cmd_reg_o.cmd));

    // Initial dispatch checks based on the type of Command Descriptor.
    unique case (cmd_reg_o.cmd_attr)
      CmdAttr_ImmTransfer:    init_ok_o = init_ok_o & !cmd_imm_o.rnw;  // Write Transfers only.
      // Any CCC command having just a Defining Byte and no data payload shall be sent as an
      // Immediate Data Transfer Command.
      CmdAttr_RegTransfer:    init_ok_o = init_ok_o & |cmd_reg_o.data_length;
      CmdAttr_ComboTransfer:  init_ok_o = init_ok_o & |cmd_combo_o.data_length;
      // Address Assignment Commands support SETDASA and ENTDAA, but not SETAASA (HCI 8.4.1).
      CmdAttr_AddrAssignment: init_ok_o = init_ok_o & (cmd_daa_o.cmd inside {ENTDAA, SETDASA});
      CmdAttr_InternalCtrl:
        unique case (cmd_intn_o.mipi_cmd)
          MIPICmd_NoOp,
          MIPICmd_BroadAddrEnable: init_ok_o = 1'b1;
          MIPICmd_TargRstPattern:
            init_ok_o = (cmd_intn_o.mipi_reserved[13:12] != RstOpType_Reserved);
          MIPICmd_CtrlSDARecovery,
          // TODO(#31308): We need to block the use of CtrlHandOff if not in the 'transition period'
          MIPICmd_CtrlHandoff,
          MIPICmd_AttemptDBR:  /* Nothing to do */;
          MIPICmd_EndXferHDR:
            // Only the HDR-DDR setting is supported.
            init_ok_o = (cmd_intn_o.mipi_reserved[15:12] == 4'h1);
          // These commands are for DMA mode only:
          // - MIPICmd_RingBundleLock, MIPICmd_DevCtxUpdate.
          default: init_ok_o = 1'b0;  // Includes invalid/undefined sub-commands.
        endcase
      default: init_ok_o = 1'b0;  // Invalid/undefined Command Descriptor types.
    endcase

// TODO: Here we perhaps want to instruct the FSM whether a DAT read is required?
  end

  // Is this a CCC Command Descriptor that results in two phases?
  //
  // - Direct Read/Write Command Descriptor conveys both the command phase (CCC+DEFB) and the
  //   subsequent read/write transfer phase from/to the first address.
  // - Broadcasts (implicitly write transfers) are never dual-phase.
  function automatic logic ccc_dual_phase(input i3c_ctrl_cmd_attrs_t attrs);
    return attrs.is_ccc & !broadcast_ccc(attrs.ccc);
  endfunction

  // Decoding of additional command information may depend upon the current command state and
  // any DAT entry that has just been read.
  // - this logic may assume that the basic validity checks above (`init_ok_o`) have passed.
  always_comb begin
    // This field specifies the type of the Command Descriptor, and thus determines the validity
    // of all other fields.
    cmd_attrs_o.attr = cmd_reg_o.cmd_attr;  // Same location for ALL Command Descriptors.

    // CCC/CMD for the basic command types.
    cmd_attrs_o.ccc  = cmd_reg_o.cmd;
    // Transaction ID for the basic command types.
    cmd_attrs_o.tid  = cmd_reg_o.tid;
    // WRite On Completion for the basic command types.
    cmd_attrs_o.wroc = cmd_reg_o.wroc;
    // Transfer mode, for the basic command types.
    cmd_attrs_o.mode = cmd_reg_o.mode;
    // I2C rather than I3C device, for the basic command types.
    cmd_attrs_o.i2c  = dat_entry_i.device;  // 0 = I3C, 1 = I2C (HCI Table 130).
    // Use HDR-DDR mode for this command?
    cmd_attrs_o.ddr  = hdr_ddr;

    // Determine maximum number of retries; this depends upon the device properties as well.
    unique case (cmd_reg_o.cmd_attr)
      CmdAttr_ImmTransfer,
      CmdAttr_RegTransfer,
      CmdAttr_ComboTransfer: begin
        // Direct CCCs support at least a single retry count to allow the Target more time to
        // respond; the DAT entry may indicate a larger number of retries in this case too.
        if (cmd_attrs_o.is_ccc) begin
          if (direct_get(cmd_reg_o.cmd)) begin
            cmd_attrs_o.retry_cnt =
              dat_entry_i.dev_nack_retry_cnt[30] ? dat_entry_i.dev_nack_retry_cnt : 2'b01;
          end else cmd_attrs_o.retry_cnt = 2'b00;
        end else cmd_attrs_o.retry_cnt = dat_entry_i.dev_nack_retry_cnt;
      end
      default: cmd_attrs_o.retry_cnt = 2'b00;
    endcase

    cmd_attrs_o.rnw      = cmd_reg_o.rnw;
    cmd_attrs_o.toc      = cmd_reg_o.toc;
    cmd_attrs_o.has_defb = 1'b0;
    cmd_attrs_o.defb     = 8'b0;  // Not needed by default; just avoids latch creation.
    cmd_attrs_o.data_len = 16'b0;

    // Index to DAT is at the same position for the majority of Command Descriptors.
    cmd_attrs_o.dev_index = cmd_reg_o.dev_index;
    // Default to a single phase for this Command Descriptor.
    cmd_attrs_o.reps_left = CmdRepW'('b0);

    // Default to acceptance, unless it's a CCC that's prohibited in Command Descriptors (TCRI 6.2).
    err_o = cmd_attrs_o.is_ccc & tcri_blocked_ccc(cmd_imm_o.cmd);

    // The most significant field is the command type (`cmd_attr`).
    // - the validity of fields is type-specific.
    unique case (cmd_reg_o.cmd_attr)
      // Immediate Data Transfer Command (TCRI 7.1.2.1).
      CmdAttr_ImmTransfer: begin
        cmd_attrs_o.has_defb = (cmd_imm_o.dtt > 'h4);
        cmd_attrs_o.defb     =  cmd_imm_o.data_byte_1;
        unique case (cmd_imm_o.dtt)
          // Data length does _not_ include the Defining Byte.
          3'h5, 3'h6, 3'h7: cmd_attrs_o.data_len = 16'(cmd_imm_o.dtt - 3'h5);
          default:          cmd_attrs_o.data_len = 16'(cmd_imm_o.dtt);
        endcase
        // A single CCC Command Descriptor may describe two phases.
        if (ccc_dual_phase(cmd_attrs_o)) begin
          // For a dual-phase Command Descriptor, the data transfer occurs in the second phase.
          cmd_attrs_o.reps_left = CmdRepW'('b1);
          if (first_phase_i) cmd_attrs_o.data_len = 16'b0;  // Data length _excludes_ the DEFB.
        end
        if (cmd_imm_o.rnw) err_o = 1'b1;  // Immediate transfers are Write only.
        // Not all Transfer mode values are valid/supported.
        if (!mode_supported(cmd_attrs_o.mode, cmd_attrs_o.i2c)) err_o = 1'b1;
      end

      // Regular Data Transfer Command (TCRI 7.1.2.2).
      CmdAttr_RegTransfer: begin
        cmd_attrs_o.has_defb = cmd_reg_o.dbp;
        cmd_attrs_o.defb     = cmd_reg_o.def_byte;
        cmd_attrs_o.data_len = cmd_reg_o.data_length;
        // A single CCC Command Descriptor may describe two phases.
        if (ccc_dual_phase(cmd_attrs_o)) begin
          // For a dual-phase Command Descriptor, the data transfer occurs in the second phase.
          cmd_attrs_o.reps_left = CmdRepW'('b1);
          if (first_phase_i) cmd_attrs_o.data_len = 16'b0;  // Data length _excludes_ the DEFB.
        end
        // Not all Transfer mode values are valid/supported, and zero-length transfers shall be done
        // using Immediate Data Transfer commands.
        if (!mode_supported(cmd_attrs_o.mode, cmd_attrs_o.i2c) || ~|cmd_reg_o.data_length) begin
          err_o = 1'b1;
        end
        if (cmd_attrs_o.is_ccc & tcri_blocked_ccc(cmd_reg_o.cmd)) err_o = 1'b1;
      end

      // Combo Transfer (Write + Write/Read) Command (TCRI 7.1.2.3).
      CmdAttr_ComboTransfer: begin
        // TODO(#31304). Combo Transfer Commands are declared as unsupported, and not implemented.
        cmd_attrs_o.data_len  = cmd_combo_o.data_length;
        // There are two phases to a Combo Transfer command.
        cmd_attrs_o.reps_left = CmdRepW'(first_phase_i);
        // Not all Transfer mode values are valid/supported, and zero-length transfers are invalid.
        if (!mode_supported(cmd_attrs_o.mode, cmd_attrs_o.i2c) || ~|cmd_combo_o.data_length ||
            &cmd_combo_o.dlp) begin
          // DATA_LENGTH_POSITION of 2'b3 is "Don't use."
          err_o = 1'b1;
        end
        if (cmd_attrs_o.is_ccc & tcri_blocked_ccc(cmd_combo_o.cmd)) err_o = 1'b1;
      end

      // Address Assignment Command (TCRI 7.1.2.5).
      CmdAttr_AddrAssignment: begin
        cmd_attrs_o.mode = XferMode_SDR0;
        cmd_attrs_o.i2c  = 1'b0;
        // The first phase is a write operation, sending the CCC.
        // SETDASA - Ensuing phases just carry a single byte Dynamic Address for each Target.
        // ENTDAA  - Subsequent phases are predominantly reads, collecting the Target
        //           characteristics, and then transparently changing to a write mid-phase;
        //           we treat this as (predominantly) a _read_ phase.
        cmd_attrs_o.rnw       = (cmd_attrs_o.ccc == ENTDAA) & !first_phase_i;
        // Describe the Read data length for ENTDAA. SETDASA is simple enough.
        cmd_attrs_o.data_len  = first_phase_i ? 16'h0 :
                  (cmd_attrs_o.ccc == ENTDAA) ? 16'h8 : 16'h1;
        // The index into the DAT advances for each command phase, and is incremented _before_ use.
        cmd_attrs_o.dev_index = first_phase_i ? cmd_daa_o.dev_index : dev_index_i;
        // Number of repetitions left after the current command phase.
        // Note: there's an initial command phase in which no device is accessed.
        cmd_attrs_o.reps_left = first_phase_i ? cmd_daa_o.dev_count : reps_left_i;
      end

      // Internal Control Command (TCRI 7.1.2.4).
      CmdAttr_InternalCtrl:
        unique case (cmd_intn_o.mipi_cmd)
          MIPICmd_NoOp,
          MIPICmd_BroadAddrEnable: err_o = 1'b0;
          MIPICmd_TargRstPattern:
            if (cmd_intn_o.mipi_reserved[13:12] == RstOpType_Reserved) begin
              err_o = 1'b1;
            end
          MIPICmd_CtrlSDARecovery,
          MIPICmd_CtrlHandoff,
          MIPICmd_AttemptDBR: begin end // Nothing to do.
          MIPICmd_EndXferHDR:
            // Only the HDR-DDR setting is supported.
            if (cmd_intn_o.mipi_reserved[15:12] != 4'h1) err_o = 1'b1;
          // These commands are for DMA mode only.
          // - MIPICmd_RingBundleLock, MIPICmd_DevCtxUpdate.
          default: err_o = 1'b1;
        endcase
      default: err_o = 1'b1;
    endcase

    // Derived properties.
    cmd_attrs_o.brd_ccc = cmd_attrs_o.is_ccc & broadcast_ccc(cmd_attrs_o.ccc);
  end

  // Determine the address to be used for this command phase and whether communication with that
  // address has been blocked.
  // - this logic is deriving further fields within `cmd_attrs_o`, using those fields set above.
  // - it now has the information from the DAT entry, where this is required.
  always_comb begin : gen_addr
    logic [NumBlocked:0] addr_blocked;  // One extra for the invalid I3C addresses.
    logic [6:0] addr_check;  // The address to be checked.
    logic [6:0] addr_used;   // Address used in the (non-)arbitrable address header.
    logic entdaa_read;
    logic rnw_used;

    // Is this the read phase of an ENTDAA Command Descriptor?
    // - normally ENTDAA is conducted using an Address Assignment Command Descriptor, but to provide
    //   a fallback option, don't rule that out here; use the CCC details directly.
    entdaa_read = &{cmd_attrs_o.is_ccc, cmd_attrs_o.ccc == ENTDAA, rep_start_i};

    // Using I3C Broadcast Address to commence a transfer?
    // - do NOT use the I3C Broadcast Address in non-initial phases, for either Private
    //   transfers or CCC handling, except if the latter is ENTDAA.
    cmd_attrs_o.addr_bcst = |{cmd_attrs_o.is_ccc, cmd_attrs_o.ddr, use_bcst_addr_i} &
                             (!rep_start_i | entdaa_read) & !cmd_attrs_o.i2c;
    // The I3C Broadcast Address is followed by 'W' unless it's an ENTDAA read phase (see above).
    rnw_used = cmd_attrs_o.rnw & (entdaa_read | !cmd_attrs_o.addr_bcst);

    // Address to be checked against blocked addresses.
    // - when issuing the read phase of a DAA command, there is scant reason to check the I3C
    //   Broadcast Address, but we can here gain a bit of extra robustness against driver error by
    //   preventing the assignment of an invalid dynamic address to a Target.
    // - it is also important to check the address of a Private Read/Write even though it has been
    //   prefixed by the I3C Broadcast Address.
    // - if this is a Broadcast CCC operation, we have no address to check.
    if (cmd_attrs_o.is_ccc && broadcast_ccc(cmd_attrs_o.ccc)) begin
      addr_check = Addr_Broadcast;
    end else begin
      addr_check = dat_entry_i.dynamic_address[22:16];
      if (cmd_attrs_o.ccc == SETDASA || cmd_attrs_o.i2c) begin  // HCI 6.3.1
        // SETDASA is always sent to the programmed static address, and I2C devices have only static
        // addresses.
        addr_check = dat_entry_i.static_address;
      end
    end

    // Address to be used for this command phase.
    // - Do not prefix transfers to I2C targets with the I3C Broadcast Address because they will
    //   ignore the traffic.
    // - The I3C Broadcast address is used for SDR Private Transfers only if explicitly requested.
    addr_used = (cmd_attrs_o.addr_bcst ? Addr_Broadcast : addr_check);

    // Test whether this is _always_ an invalid address for the Controller to access, prohibited
    // by the specification (Table 10).
    addr_blocked[NumBlocked] = invalid_addr(addr_check, 1'b0);

    // Address blocking prevents addressing of software-blacklisted addresses, e.g., I2C Targets
    // that may try to employ clock stretching.
    for (int unsigned b = 0; b < NumBlocked; b++) begin
      addr_blocked[b] = ((addr_check & mask_blocked_i[b]) == addr_blocked_i[b]);
    end

    // Indicate to the core FSM logic that the transfer shall not proceed?
    unique case (cmd_attrs_o.attr)
      // The standard Command Descriptors all perform transfers to/from an address.
      CmdAttr_RegTransfer,
      CmdAttr_ImmTransfer,
      CmdAttr_ComboTransfer,
      // Whilst address assignment does not target a specific address, we do check the one supplied.
      CmdAttr_AddrAssignment: blocked_o = |addr_blocked;
      // Internal Control Commands do not involve transfer(s) to a specified address.
      // TODO(#31308): We could catch invalid dynamic addresses here if we supported Controller Role
      // Handoff (HCI Table 142).
      CmdAttr_InternalCtrl:   blocked_o = 1'b0;
      // Unsupported/unrecognised command types; `err_o` takes precedence, and we don't know what
      // address, if any, is relevant anyway in this case.
      default: blocked_o = 1'b0;
    endcase

    // Address to be used, as required by CmdArb/CmdAddr, _iff not blocked_, and only by those
    // commands that actually require an address.
    cmd_attrs_o.addr_rnw = {addr_used, rnw_used};
  end

  // Signals that the logic does not use (yet).
  // - fields of the shared command state and DAT entry structs that the decoder does not need.
  logic unused_decode_inputs;
  assign unused_decode_inputs = ^{dat_entry_i.autocmd_hdr_code, dat_entry_i.autocmd_mask,
                                  dat_entry_i.autocmd_mode, dat_entry_i.autocmd_value,
                                  dat_entry_i.crr_reject, dat_entry_i.dynamic_address,
                                  dat_entry_i.ibi_payload, dat_entry_i.ibi_reject,
                                  dat_entry_i.ring_id, dat_entry_i.static_address,
                                  dat_entry_i.ts};

endmodule
