// Copyright lowRISC contributors (OpenTitan project).
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0
//

module prim_alert_rxtx_async_bind_fpv;

  bind prim_alert_rxtx_async_tb
        prim_alert_rxtx_async_assert_fpv prim_alert_rxtx_async_assert_fpv (
    .clk_i,
    .rst_ni,
    .ping_err_pi,
    .ping_err_ni,
    .ping_skew_i,
    .ack_err_pi,
    .ack_err_ni,
    .ack_skew_i,
    .alert_err_pi,
    .alert_err_ni,
    .alert_skew_i,
    .alert_test_i,
    .init_trig_i,
    .alert_req_i,
    .alert_ack_o,
    .alert_state_o,
    .ping_req_i,
    .ping_ok_o,
    .integ_fail_o,
    .alert_o
  );

endmodule : prim_alert_rxtx_async_bind_fpv
