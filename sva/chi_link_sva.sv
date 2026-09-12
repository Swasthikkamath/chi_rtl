module chi_link_sva #(
  parameter int unsigned LCRD_DEPTH = 8,
  parameter int unsigned COUNT_W =
    (LCRD_DEPTH < 2) ? 1 : $clog2(LCRD_DEPTH + 1)
) (
  input logic clk,
  input logic resetn,
  input logic FLITV,
  input logic lcrdReturnSend,
  input logic [COUNT_W-1:0] creditCount,
  input logic creditOverflow,
  input logic creditUnderflow,
  input logic [1:0] linkState
);
  localparam logic [1:0] STOP = 2'b00;
  localparam logic [1:0] ACTIVATE = 2'b01;
  localparam logic [1:0] RUN = 2'b10;
  localparam logic [1:0] DEACTIVATE = 2'b11;
  localparam logic [COUNT_W-1:0] LCRD_DEPTH_COUNT =
    COUNT_W'(LCRD_DEPTH);

  // A flit always spends a credit, and a protocol flit is only sent in RUN.
  // The one exception is an LCrdReturn, which is sent in DEACTIVATE and whose
  // purpose is to spend a credit without carrying a message
  // (IHI 0050H B13.11, B14.5).
  NO_SEND_WITHOUT_RUN_OR_CREDIT: assert property (
    @(posedge clk) disable iff (!resetn)
    FLITV |-> ((creditCount != '0)
               && (lcrdReturnSend ? (linkState == DEACTIVATE)
                                  : (linkState == RUN))));

  NO_CREDIT_OVERFLOW: assert property (
    @(posedge clk) disable iff (!resetn)
    !creditOverflow);

  NO_CREDIT_UNDERFLOW: assert property (
    @(posedge clk) disable iff (!resetn)
    !creditUnderflow);

  STOP_TRANSITION_VALID: assert property (
    @(posedge clk) disable iff (!resetn)
    ($past(linkState) == STOP)
      |-> ((linkState == STOP) || (linkState == ACTIVATE)));

  ACTIVATE_TRANSITION_VALID: assert property (
    @(posedge clk) disable iff (!resetn)
    ($past(linkState) == ACTIVATE)
      |-> ((linkState == ACTIVATE) || (linkState == RUN)
           || (linkState == DEACTIVATE)));

  RUN_TRANSITION_VALID: assert property (
    @(posedge clk) disable iff (!resetn)
    ($past(linkState) == RUN)
      |-> ((linkState == RUN) || (linkState == DEACTIVATE)));

  DEACTIVATE_TRANSITION_VALID: assert property (
    @(posedge clk) disable iff (!resetn)
    ($past(linkState) == DEACTIVATE)
      |-> ((linkState == DEACTIVATE) || (linkState == STOP)));

  // Every credit must have been handed back before the link reaches STOP, so
  // the Transmitter holds none of them at that point (IHI 0050H B14.6.3.2).
  DEACTIVATION_CREDITS_DRAINED: assert property (
    @(posedge clk) disable iff (!resetn)
    ($past(linkState) == DEACTIVATE) && (linkState == STOP)
      |-> ($past(creditCount) == '0));

  LINK_ACTIVATION: cover property (
    @(posedge clk) disable iff (!resetn)
    (linkState == RUN) && ($past(linkState) == ACTIVATE)
      && ($past(linkState, 2) == STOP));

  LINK_DEACTIVATION: cover property (
    @(posedge clk) disable iff (!resetn)
    (linkState == STOP) && ($past(linkState) == DEACTIVATE)
      && ($past(linkState, 2) == RUN));
endmodule

bind chi_link_tx chi_link_sva #(
  .LCRD_DEPTH(LCRD_DEPTH),
  .COUNT_W(COUNT_W)
) chi_link_tx_assertions (
  .clk(clk),
  .resetn(resetn),
  .FLITV(FLITV),
  .lcrdReturnSend(lcrdReturnSend),
  .creditCount(creditCount),
  .creditOverflow(creditOverflow),
  .creditUnderflow(creditUnderflow),
  .linkState(linkState)
);
