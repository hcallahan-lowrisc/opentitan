// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

class spi_host_base_vseq extends cip_base_vseq #(
    .RAL_T               (spi_host_reg_block),
    .CFG_T               (spi_host_env_cfg),
    .COV_T               (spi_host_env_cov),
    .VIRTUAL_SEQUENCER_T (spi_host_virtual_sequencer)
  );
  `uvm_object_utils(spi_host_base_vseq)
  `uvm_object_new


  // spi registers
  rand spi_host_command_t    spi_host_command_reg;
  rand spi_host_ctrl_t       spi_host_ctrl_reg;
  rand spi_host_configopts_t spi_config_regs;
  rand spi_host_event_enable_t event_enable;
  rand spi_host_intr_enable_t intr_enable;
  rand spi_host_error_enable_t error_enable;
  // random variables
  rand uint                  num_runs;
  rand uint                  tx_fifo_access_dly;
  rand uint                  rx_fifo_access_dly;
  rand uint                  clear_intr_dly;
  // transaction item contains a full spi transaction
  spi_transaction_item       transaction;

  // reactive sequences to run on spi_agent (configured as a Device)
  spi_device_cmd_rsp_seq m_spi_device_seq[SPI_HOST_NUM_CS];

  // Used to control when csr_spinwaits are spinning
  uvm_event start_stop_spinwait_ev = uvm_event_pool::get_global("start_stop_spinwait_ev");

  // constraints for simulation loops
  constraint num_trans_c {
    num_trans inside {[cfg.seq_cfg.host_spi_min_trans : cfg.seq_cfg.host_spi_max_trans]};
  }
  constraint num_runs_c {
    num_runs inside {[cfg.seq_cfg.host_spi_min_runs : cfg.seq_cfg.host_spi_max_runs]};
  }


  constraint intr_dly_c {
    clear_intr_dly inside {[cfg.seq_cfg.host_spi_min_dly : cfg.seq_cfg.host_spi_max_dly]};
  }
  constraint fifo_dly_c {
    rx_fifo_access_dly inside {[cfg.seq_cfg.host_spi_min_dly : cfg.seq_cfg.host_spi_max_dly]};
    tx_fifo_access_dly inside {[cfg.seq_cfg.host_spi_min_dly : cfg.seq_cfg.host_spi_max_dly]};
  }

  constraint spi_config_regs_c {
      // configopts regs
      spi_config_regs.cpol dist {
        1'b0 :/ 1,
        1'b1 :/ 1
      };
      spi_config_regs.cpha dist {
        1'b0 :/ 1,
        1'b1 :/ 1
      };
      spi_config_regs.csnlead inside {[cfg.seq_cfg.host_spi_min_csn_latency :
                                       cfg.seq_cfg.host_spi_max_csn_latency]};
      spi_config_regs.csntrail inside {[cfg.seq_cfg.host_spi_min_csn_latency :
                                        cfg.seq_cfg.host_spi_max_csn_latency]};
      spi_config_regs.csnidle inside {[cfg.seq_cfg.host_spi_min_csn_latency :
                                       cfg.seq_cfg.host_spi_max_csn_latency]};
  }

  // Separate constraint to allow easy override in child sequences
  constraint spi_config_regs_clkdiv_c {
    spi_config_regs.clkdiv dist {
      [cfg.seq_cfg.host_spi_min_clkdiv : cfg.seq_cfg.host_spi_lower_middle_clkdiv]      :/90,
      [cfg.seq_cfg.host_spi_lower_middle_clkdiv+1 : cfg.seq_cfg.host_spi_middle_clkdiv] :/7,
      [cfg.seq_cfg.host_spi_middle_clkdiv+1 : cfg.seq_cfg.host_spi_upper_middle_clkdiv] :/3
    };
  }

  constraint spi_ctrl_regs_c {
    // csid reg
    spi_host_ctrl_reg.csid inside {[0 : SPI_HOST_NUM_CS-1]};
    // control reg
    spi_host_ctrl_reg.tx_watermark dist {
      [1:7]   :/ 1,
      [8:15]  :/ 1,
      [16:31] :/ 1,
      [32:cfg.seq_cfg.host_spi_max_txwm] :/ 1
      };
    spi_host_ctrl_reg.rx_watermark dist {
      [1:7]   :/ 1,
      [8:15]  :/ 1,
      [16:31] :/ 1,
      [32:cfg.seq_cfg.host_spi_max_rxwm] :/ 1
      };
  }

  function void post_randomize();
    super.post_randomize();
    // We currently support 1 chip-select line only

    // We set the timeout to it's default value every time upon entry here.
    // This is because the sim may go through multiple resets and if we don't
    // re-set it's value it may not be useful as a timeout value
    cfg.set_default_csr_timeout();
    case(spi_config_regs.clkdiv) inside
      // After randomization we set a different timeout based on the clock divider
      [cfg.seq_cfg.host_spi_min_clkdiv : cfg.seq_cfg.host_spi_lower_middle_clkdiv]: ;
      [cfg.seq_cfg.host_spi_lower_middle_clkdiv+1 : cfg.seq_cfg.host_spi_middle_clkdiv]: begin
        cfg.csr_spinwait_timeout_ns *= 1.5;
      end
      [cfg.seq_cfg.host_spi_middle_clkdiv+1 : cfg.seq_cfg.host_spi_upper_middle_clkdiv]: begin
        cfg.csr_spinwait_timeout_ns *= 3;
      end
      [cfg.seq_cfg.host_spi_middle_clkdiv+1 : 16'hFFF] : begin
        cfg.csr_spinwait_timeout_ns *= 5;
      end
      [16'hFFF+1 : cfg.seq_cfg.host_spi_max_clkdiv] : begin
        cfg.csr_spinwait_timeout_ns *= 10;
      end
      default : begin
        `uvm_fatal(`gfn, $sformatf("spi_config_regs.clkdiv[0]=0x%0x is out of range",
                                   spi_config_regs.clkdiv))
      end
    endcase
    `uvm_info(`gfn, $sformatf("%m: CSR_SPINWAIT Timeout set to %0dns", cfg.csr_spinwait_timeout_ns),
              UVM_DEBUG)
  endfunction


  virtual task pre_start();
    // sync monitor and scoreboard setting
    cfg.m_spi_agent_cfg.en_monitor_checks = cfg.en_scb;
    `uvm_info(`gfn, $sformatf("\n  base_vseq, %s monitor and scoreboard",
                              cfg.en_scb ? "enable" : "disable"), UVM_DEBUG)
    num_runs.rand_mode(0);
    num_trans_c.constraint_mode(0);
    transaction = spi_transaction_item::type_id::create("transaction");
    super.pre_start();
  endtask : pre_start

  // Like csr_spinwait, only the timeout can be stop by using an event.
  // In addition, one needs to pass the clock cycle period.
  // This can be used instead of csr_spinwait for moments in which the timeout needs to be
  // controlled due to RTL conditions such as SW_rest or the module being disabled.
  task automatic csr_spinwait_stoppable(
    input   uvm_object ptr,
    input   uvm_reg_data_t exp_data,
    input   uvm_check_e check = default_csr_check,
    input   uvm_path_e path = UVM_DEFAULT_PATH,
    input   uvm_reg_map map = null,
    input   uvm_reg_frontdoor user_ftdr = default_user_frontdoor,
    input   uint spinwait_delay_ns = 0,
    input   uint timeout_ns = default_spinwait_timeout_ns,
    input   compare_op_e compare_op = CompareOpEq,
    input   bit backdoor = 0,
    input   uvm_verbosity verbosity = UVM_HIGH,
    input   uint clk_cycle_period_ns,
    input   string start_stop_ev_name = "start_stop_spinwait_ev"
    );
    static int     count;
    count++;
    `uvm_info($sformatf("%m()"),
              $sformatf("- (call_count=%0d, backdoor=%0d, exp_data=%0d, ptr=%s)",
                        count,backdoor,exp_data, ptr.get_name()), verbosity)
    fork
      begin : isolation_fork
        fork
          begin
            csr_utils_pkg::csr_spinwait(.ptr(ptr),
                                        .exp_data(exp_data),
                                        .check(check),
                                        .path(path),
                                        .map(map),
                                        .user_ftdr(user_ftdr),
                                        .spinwait_delay_ns(spinwait_delay_ns),
                                        // Timeout is 1000 longer than actual timeout so
                                        // the stoppable timeout part of the fork below can
                                        // block the count
                                        .timeout_ns(timeout_ns*10000),
                                        .compare_op(compare_op),
                                        .backdoor(backdoor),
                                        .verbosity(verbosity)
                                        );
          end
          begin: timeout_block
            stoppable_timeout(clk_cycle_period_ns, timeout_ns, start_stop_ev_name, exp_data,
                              compare_op, ptr, count);
          end : timeout_block
        join_any
        disable fork;
      end : isolation_fork
    join
  endtask

  // This task applies a timeout that can be stopped. It's used in situations where spi_host is
  // disabled or when there is a SW reset
  task stoppable_timeout(input uint clk_cycle_period_ns,
                         input        uint timeout_ns,
                         input string start_stop_ev_name,
                         input        uvm_reg_data_t exp_data,
                         input        compare_op_e compare_op,
                         input        uvm_object ptr,
                         input int    call_count
                         );
    int unsigned clk_cycles = 0;
    csr_spinwait_ctrl_object obj;
    uvm_event start_stop_spinwait_ev = uvm_event_pool::get_global(start_stop_ev_name);
    csr_field_t csr_or_fld;

    while ( (clk_cycles * clk_cycle_period_ns) <= timeout_ns) begin
      clk_cycles++;
      #(clk_cycle_period_ns * 1ns);
      if (start_stop_spinwait_ev.is_on()) begin
        uvm_object ev_obj;
        // Event triggerred
        ev_obj = start_stop_spinwait_ev.get_trigger_data();
        if (!$cast(obj, ev_obj))
          `uvm_fatal($sformatf("%m()"), "CAST FAILED")

        if (obj.stop) begin
          start_stop_spinwait_ev.wait_ptrigger_data(ev_obj);
          `uvm_info($sformatf("%m"), "Event triggered to halt the timeout", UVM_DEBUG)
          if (!$cast(obj, ev_obj))
            `uvm_fatal($sformatf("%m()"), "CAST FAILED")
          if(obj.stop)
            `uvm_fatal($sformatf("%m"), "Event has already been triggered with stop=1")
        end
      end
    end

    csr_or_fld = decode_csr_or_field(ptr);
    `uvm_fatal($sformatf("%m()"),
               $sformatf({"timeout = %0dns %0s (addr=0x%0h,",
                          " Comparison=%s, exp_data=0x%0h, call_count=%0d"} ,timeout_ns,
                         ptr.get_full_name(), csr_or_fld.csr.get_address(),
                         compare_op.name, exp_data, call_count))
  endtask

  // wrapping csr_spinwait over csr_spinwait_stoppable so we can stop the timeout
  // count in circumstances like the RTL being disable due to spien or sw_rst.
  virtual task automatic csr_spinwait( input  uvm_object        ptr,
                                       input  uvm_reg_data_t    exp_data,
                                       input  uvm_check_e       check = default_csr_check,
                                       input  uvm_path_e        path = UVM_DEFAULT_PATH,
                                       input  uvm_reg_map       map = null,
                                       input  uvm_reg_frontdoor user_ftdr =
                                                                default_user_frontdoor,
                                       input  uint              spinwait_delay_ns = 0,
                                       input  uint              timeout_ns =
                                                                  cfg.csr_spinwait_timeout_ns,
                                       input  compare_op_e      compare_op = CompareOpEq,
                                       input  bit               backdoor = 0,
                                       input  uvm_verbosity     verbosity = UVM_HIGH,
                                       input  uint              clk_cycle_period_ns =
                                                                  (cfg.clk_rst_vif.clk_period_ps
                                                                  / 1000),
                                       input  string start_stop_ev_name = "start_stop_spinwait_ev"
                                      );
    csr_spinwait_stoppable( .ptr(ptr), .exp_data(exp_data), .check(check),
                            .path(path), .map(map), .user_ftdr(user_ftdr),
                            .spinwait_delay_ns(spinwait_delay_ns),
                            .timeout_ns(timeout_ns), .compare_op(compare_op),
                            .backdoor(backdoor), .verbosity(verbosity),
                            .clk_cycle_period_ns(clk_cycle_period_ns),
                            .start_stop_ev_name("start_stop_spinwait_ev")
                            );
  endtask

  // Start sequences on the spi_agent (configured as a Device) that will respond to host bus activity.
  // Currently we use "spi_device_cmd_rsp_seq", which discards write-data, and responds with random data for reads.
  virtual task start_agent_reactive_seqs();
    fork
      for( int i = 0; i < SPI_HOST_NUM_CS; i++) begin
        m_spi_device_seq[i] = spi_device_cmd_rsp_seq::type_id::create($sformatf("spi_host[%0d]",i));
        m_spi_device_seq[i].start(p_sequencer.spi_sequencer_h);
      end
    join
  endtask : start_agent_reactive_seqs

  // Call this function to cleanup the above started reactive-sequences, such as if we
  // exit early, or are running sequences back-to-back.
  virtual task cleanup_reactive_seq();
    p_sequencer.spi_sequencer_h.stop_sequences();
    if (cfg.m_spi_agent_cfg.has_req_fifo) p_sequencer.spi_sequencer_h.req_analysis_fifo.flush();
    if (cfg.m_spi_agent_cfg.has_rsp_fifo) p_sequencer.spi_sequencer_h.rsp_analysis_fifo.flush();
  endtask : cleanup_reactive_seq

  task post_start();
    super.post_start();
    cleanup_reactive_seq();
  endtask

  function void transaction_init();
    transaction = spi_transaction_item::type_id::create("transaction");

    transaction.read_weight     = cfg.seq_cfg.read_pct;
    transaction.write_weight    = cfg.seq_cfg.write_pct;
    transaction.std_en          = cfg.seq_cfg.std_en;
    transaction.dual_en         = cfg.seq_cfg.dual_en;
    transaction.quad_en         = cfg.seq_cfg.quad_en;
    transaction.rx_only_weight  = cfg.seq_cfg.rx_only_weight;
    transaction.tx_only_weight  = cfg.seq_cfg.tx_only_weight;
    transaction.spi_len_min     = cfg.seq_cfg.host_spi_min_len;
    transaction.spi_len_max     = cfg.seq_cfg.host_spi_max_len;
    transaction.spi_num_seg_min = cfg.seq_cfg.host_spi_min_num_seg;
    transaction.spi_num_seg_max = cfg.seq_cfg.host_spi_max_num_seg;
    transaction.num_cmd_bytes   = cfg.num_cmd_bytes;
    transaction.num_dummy       = cfg.num_dummy;
  endfunction



  // setup basic spi_host features
  virtual task spi_host_init();
    bit [TL_DW-1:0] intr_state;

    wait(cfg.m_spi_agent_cfg.vif.rst_n);
    // program sw_reset for spi_host dut
    program_spi_host_sw_reset();
    // enable then clear interrupt
    csr_wr(.ptr(ral.intr_enable), .value({TL_DW{1'b1}}));
    csr_rd(.ptr(ral.intr_state), .value(intr_state));
    csr_wr(.ptr(ral.intr_state), .value(intr_state));
  endtask : spi_host_init

  // In addition to un/setting sw_rst also triggers a uvm_event (and uvm_object)
  // so any csr_spinwaits can be halted until the reset is over
  virtual task program_spi_host_sw_reset(int drain_cycles = SPI_HOST_RX_DEPTH);
    uvm_reg_data_t control_reg;
    csr_spinwait_ctrl_object spinwait_ctrl_obj;
    spinwait_ctrl_obj = csr_spinwait_ctrl_object::type_id::create("spinwait_ctrl_obj");
    ral.control.sw_rst.set(1'b1);
    csr_update(ral.control);

    spinwait_ctrl_obj.stop = 1;
    start_stop_spinwait_ev.trigger(spinwait_ctrl_obj);
    `uvm_info(`gfn, "Triggered 'start_stop_spinwait_ev' due to SW_RST=1", UVM_DEBUG)
    // make sure data completely drained from fifo then release reset
    wait_for_fifos_empty(AllFifos);
    // Backdoor read to avoid writing something different to what's there
    csr_rd(.ptr(ral.control), .value(control_reg), .backdoor(1));
    control_reg[30] = 0; // SW reset field
    csr_wr(.ptr(ral.control), .value(control_reg));
    spinwait_ctrl_obj.stop = 0;
    start_stop_spinwait_ev.trigger(spinwait_ctrl_obj);
    `uvm_info(`gfn, "Triggered 'start_stop_spinwait_ev' due to SW_RST=0", UVM_DEBUG)

    start_stop_spinwait_ev.reset();
    `uvm_info(`gfn, "Resetting 'start_stop_spinwait_ev'", UVM_DEBUG)
  endtask : program_spi_host_sw_reset

  virtual task program_spi_host_regs();
    // IMPORTANT: configopt regs must be programmed before command reg
    program_configopt_regs();
    program_control_reg();
    program_csid_reg();
    csr_wr(.ptr(ral.error_enable), .value(error_enable));
    csr_wr(.ptr(ral.event_enable), .value(event_enable));
    csr_wr(.ptr(ral.intr_enable), .value(intr_enable));
    // TODO(#18886)
    update_spi_agent_regs();
  endtask : program_spi_host_regs

  virtual task program_csid_reg();
    // enable one of CS lines
    csr_wr(.ptr(ral.csid), .value(spi_host_ctrl_reg.csid));
  endtask : program_csid_reg

  virtual task program_control_reg();
    ral.control.tx_watermark.set(spi_host_ctrl_reg.tx_watermark);
    ral.control.rx_watermark.set(spi_host_ctrl_reg.rx_watermark);
    // activate spi_host dut
    ral.control.spien.set(1'b1);
    ral.control.output_en.set(1'b1);
    csr_update(ral.control);
  endtask : program_control_reg


  // CONFIGOPTS register fields
  virtual task program_configopt_regs();
    ral.configopts.cpol.set(spi_config_regs.cpol);
    ral.configopts.cpha.set(spi_config_regs.cpha);
    ral.configopts.fullcyc.set(spi_config_regs.fullcyc);
    ral.configopts.csnlead.set(spi_config_regs.csnlead);
    ral.configopts.csntrail.set(spi_config_regs.csntrail);
    ral.configopts.csnidle.set(spi_config_regs.csnidle);
    ral.configopts.clkdiv.set(spi_config_regs.clkdiv);
    csr_wr(ral.configopts, .value(ral.configopts.get()));
  endtask : program_configopt_regs


  virtual task program_command_reg(spi_host_command_t cmd);
    // COMMAND register fields
    ral.command.direction.set(cmd.direction);
    ral.command.speed.set(cmd.mode);
    ral.command.csaat.set(cmd.csaat);
    ral.command.len.set(cmd.len);
    // ensure a write - even if values didn't change
    csr_wr(ral.command, .value(ral.command.get()));
  endtask : program_command_reg


  // read interrupts and randomly clear interrupts if set
  virtual task process_interrupts();
    bit [TL_DW-1:0] intr_state, intr_clear;

    // read interrupt
    csr_rd(.ptr(ral.intr_state), .value(intr_state));
    // clear interrupt if it is set
    `DV_CHECK_STD_RANDOMIZE_WITH_FATAL(intr_clear,
                                       foreach (intr_clear[i]) {
                                         intr_state[i] -> intr_clear[i] == 1;
                                       })

    `DV_CHECK_MEMBER_RANDOMIZE_FATAL(clear_intr_dly)
    cfg.clk_rst_vif.wait_clks(clear_intr_dly);
    csr_wr(.ptr(ral.intr_state), .value(intr_clear));
  endtask : process_interrupts


  // override apply_reset to handle core_reset domain
  virtual task apply_reset(string kind = "HARD");
      super.apply_reset(kind);
  endtask


  // wait until fifos empty
  virtual task wait_for_fifos_empty(spi_host_fifo_e fifo = AllFifos);
    if (fifo == TxFifo || TxFifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.txempty), .exp_data(1'b1));
    end
    if (fifo == RxFifo || TxFifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.rxempty), .exp_data(1'b1));
    end
  endtask : wait_for_fifos_empty


  // wait dut ready for new command
  virtual task wait_ready_for_command(bit backdoor = 1'b0);
    csr_spinwait(.ptr(ral.status.ready), .exp_data(1'b1), .backdoor(backdoor));
  endtask : wait_ready_for_command


  // reads out the STATUS and INTR_STATE csrs so scb can check the status
  virtual task check_status_and_clear_intrs();
    bit [TL_DW-1:0] data;

    // read then clear interrupts
    csr_rd(.ptr(ral.intr_state), .value(data));
    csr_wr(.ptr(ral.intr_state), .value(data));
    // read status register
    csr_rd(.ptr(ral.status), .value(data));
  endtask : check_status_and_clear_intrs


  // wait until fifos has available entries to read/write
  virtual task wait_for_fifos_available(spi_host_fifo_e fifo = AllFifos);
    // Wait for control.sw_rst = 0 before checking for fifo availability, since
    // a SW reset causes both TX/RX FIFOs to drain
    csr_spinwait(.ptr(ral.control.sw_rst), .exp_data(1'b0));
    if (fifo == TxFifo || fifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.txfull), .exp_data(1'b0));
    end
    if (fifo == RxFifo || fifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.rxempty), .exp_data(1'b0));
    end
  endtask


  // wait until no rx/tx_trans stalled
  virtual task wait_for_trans_complete(spi_host_fifo_e fifo = AllFifos);
    if (fifo == TxFifo || fifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.txstall), .exp_data(1'b0));
      `uvm_info(`gfn, $sformatf("\n  base_vseq: tx_trans is not stalled"), UVM_DEBUG)
    end
    if (fifo == RxFifo || fifo == AllFifos) begin
      csr_spinwait(.ptr(ral.status.rxstall), .exp_data(1'b0));
      `uvm_info(`gfn, $sformatf("\n  base_vseq: rx_trans is not stalled"), UVM_DEBUG)
    end
  endtask : wait_for_trans_complete


  // update spi_agent registers
  virtual function void update_spi_agent_regs();
    cfg.m_spi_agent_cfg.sck_polarity[0] = spi_config_regs.cpol;
    cfg.m_spi_agent_cfg.sck_phase[0]    = spi_config_regs.cpha;
    cfg.m_spi_agent_cfg.full_cyc[0]     = spi_config_regs.fullcyc;
    cfg.m_spi_agent_cfg.csn_lead[0]     = spi_config_regs.csnlead;
    cfg.m_spi_agent_cfg.csid            = spi_host_ctrl_reg.csid;
    cfg.m_spi_agent_cfg.spi_mode        = spi_host_command_reg.mode;
    cfg.m_spi_agent_cfg.decode_commands = 1'b1;
    print_spi_host_regs();
  endfunction : update_spi_agent_regs

  // print the content of spi_host_regs[channel]
  virtual function void print_spi_host_regs(uint en_print = 1);
    if (en_print) begin
      string str = "";

      str = {str, "\n  base_vseq, values programed to the dut registers:"};
      str = {str, $sformatf("\n    csid         %0d", spi_host_ctrl_reg.csid)};
      str = {str, $sformatf("\n    tx_watermark         %0b", spi_host_ctrl_reg.tx_watermark)};
      str = {str, $sformatf("\n    rx_watermark         %0b", spi_host_ctrl_reg.rx_watermark)};
      str = {str, $sformatf("\n    Mode        %s",  spi_host_command_reg.mode.name())};
      str = {str, $sformatf("\n    direction    %s",  spi_host_command_reg.direction.name())};
      str = {str, $sformatf("\n    csaat        %b",  spi_host_command_reg.csaat)};
      str = {str, $sformatf("\n    len          %0d", spi_host_command_reg.len)};
      str = {str, $sformatf("\n    config")};
      str = {str, $sformatf("\n      cpol       %b", spi_config_regs.cpol)};
      str = {str, $sformatf("\n      cpha       %b", spi_config_regs.cpha)};
      str = {str, $sformatf("\n      fullcyc    %b", spi_config_regs.fullcyc)};
      str = {str, $sformatf("\n      csnlead    %0d", spi_config_regs.csnlead)};
      str = {str, $sformatf("\n      csntrail   %0d", spi_config_regs.csntrail)};
      str = {str, $sformatf("\n      csnidle    %0d", spi_config_regs.csnidle)};
      str = {str, $sformatf("\n      clkdiv     %0d\n", spi_config_regs.clkdiv)};
      `uvm_info(`gfn, str, UVM_LOW)
    end
  endfunction : print_spi_host_regs


  // phase alignment for resets signal of core and bus domain
  virtual task do_phase_align_reset(bit en_phase_align_reset = 1'b0);
    if (en_phase_align_reset) begin
      fork
        cfg.clk_rst_vif.wait_clks($urandom_range(5, 10));
      join
    end
  endtask : do_phase_align_reset


  // Send TL-UL read/write request to a memory address (window type)
  // > Randomly select between blocking/non-blocking accesses by default
  virtual local task tl_access_inner(bit [TL_AW-1:0]  addr,
                                     bit [TL_DW-1:0]  data,
                                     bit              write,
                                     bit [TL_DBW-1:0] mask = {TL_DBW{1'b1}},
                                     bit              blocking = $urandom_range(0, 1));
    super.tl_access(.addr(addr), .write(write), .data(data), .mask(mask), .blocking(blocking));
    `uvm_info(`gfn,
              $sformatf("\n  rxtx_vseq, TL_%s to addr 0x%0x, data: 0x%8x, blk %b, mask %b",
                        write ? "WRITE" : "READ", addr, data, blocking, mask),
              UVM_HIGH)
  endtask : tl_access_inner

  // TODO (#24198): incorporate into a tl_access task wrapper and use whenever the mask is 0x0,
  // or non-3 byte strobes for TXFIFO
  virtual task accessinval_error_check(bit [TL_DBW-1:0] mask, bit txfifo);
    int num_try = 2;
    bit accessinval_error;

    if (!is_valid_mask (mask, txfifo)) begin

      repeat (num_try) begin
        csr_rd(.ptr(ral.error_status.accessinval), .value(accessinval_error));
        if (accessinval_error) begin
          break;
        end
      end
      if (!accessinval_error) begin
        `uvm_fatal(`gfn, {$sformatf("%m - ACCESSINVAL_ERROR not set despite of sending a"),
                          $sformatf("mask = %0d",mask)})
      end else begin
        // Clear the error bit to allow the RTL to move forward.
        csr_wr(.ptr(ral.error_status.accessinval), .value(1));
        `uvm_info(`gfn, {"Sent ral.error_status.accessinval = 0x1 to clear the error and let",
                         " the simulation proceed"}, UVM_DEBUG)
      end
    end
  endtask

  // Create TL access(es) to either TXFIFO/RXFIFO to write/read data.
  // fifo == TxFifo : Write all bits in data_q to the TxFifo
  //      == RxFifo : Read single 32-bit word from RxFifo
  virtual task access_data_fifo(ref bit [7:0] data_q[$], input spi_host_fifo_e fifo,
                                    bit fifo_avail_chk = 1'b1);
    typedef enum bit {WRITE = 1'b1, READ = 1'b0} rdwr_e;
    rdwr_e                  rw                 = (fifo == RxFifo) ? READ : WRITE;
    bit [TL_AW-1:0]         align_addr         = (fifo == RxFifo) ? SPI_HOST_RXDATA_OFFSET:
                                                                    SPI_HOST_TXDATA_OFFSET;
    bit [TL_DBW-1:0][7:0]   data               = '0;
    bit [TL_DBW-1:0]        mask               = '0;
    int                     cnt                =  0;
    `DV_CHECK_NE_FATAL(fifo, AllFifos)

    // Check for free space in the fifo
    // TODO(#18886) add interrupt handling if FIFO overflows
    if (fifo_avail_chk) wait_for_fifos_available(fifo);

    if (rw == WRITE) begin
      // Pull bytes from data_q, assembling them into 32-bit words for TL-UL writes.
      // If data_q.size()%4 != 0, add a runt access with the remaining data (mask-off empty bytes)
      while (data_q.size() > 0) begin
        data[cnt] = data_q.pop_front();
        mask[cnt] = 1'b1;

        // TX - FIFO doesn't support 3-strobes set. Sending a 3-byte strobes
        // in write causes an ACCESSINVAL which locks the RTL until is cleared
        // Currently neither the scoreboard nor the VSEQs handle this scenario well,
        // hence restricting here
        if ((cnt == 3) || (cnt == 1 && data_q.size == 1)) begin
          tl_access_inner(.addr(align_addr), .data(data), .write(WRITE),
                          .mask(mask), .blocking(1'b1));
          cnt  = 0;
          data = '0;
          mask = '0;
        end else begin
          cnt++;
        end
      end

      // add runts
      if (cnt != 0) begin
        tl_access_inner(.addr(align_addr), .data(data), .write(WRITE), .mask(mask),
                        .blocking(1'b1));
      end
    end else if (rw == READ) begin
      // Read a single 32-bit word
      tl_access_inner(.addr(align_addr), .data(data), .write(READ), .mask(mask), .blocking(1'b1));
      data_q = {<<8{data}};
    end
  endtask : access_data_fifo

endclass : spi_host_base_vseq
