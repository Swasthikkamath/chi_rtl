module chi_link_rx_sva #(
  parameter int unsigned LCRD_DEPTH = 8,
  parameter int unsigned COUNT_W =
    (LCRD_DEPTH < 2) ? 1 : $clog2(LCRD_DEPTH + 1),
  parameter bit PARITY_EN = 1'b0
) (
  input logic clk,
  input logic resetn,
  input logic FLITV,
  input logic parityError,
  input logic bufferOverflow,
  input logic [COUNT_W-1:0] bufferCount,
  input logic [COUNT_W-1:0] pendingCredits,
  input logic pushFlit,
  input logic parityMismatch,
  input logic [1:0] linkState
);
  localparam logic [1:0] STOP = 2'b00;
  localparam logic [1:0] ACTIVATE = 2'b01;
  localparam logic [1:0] RUN = 2'b10;
  localparam logic [1:0] DEACTIVATE = 2'b11;
  localparam logic [COUNT_W-1:0] LCRD_DEPTH_COUNT =
    COUNT_W'(LCRD_DEPTH);

  BUFFER_COUNT_IN_RANGE: assert property (
    @(posedge clk) disable iff (!resetn)
    bufferCount <= LCRD_DEPTH_COUNT);

  NO_BUFFER_OVERFLOW: assert property (
    @(posedge clk) disable iff (!resetn)
    !bufferOverflow);

  NO_RECEIVE_WITHOUT_RUN: assert property (
    @(posedge clk) disable iff (!resetn)
    FLITV |-> (linkState == RUN));

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

  DEACTIVATION_BUFFER_DRAINED: assert property (
    @(posedge clk) disable iff (!resetn)
    ($past(linkState) == DEACTIVATE) && (linkState == STOP)
      |-> (($past(bufferCount) == '0)
           && ($past(pendingCredits) == '0)));

  PARITY_ERROR_OBSERVED: assert property (
    @(posedge clk) disable iff (!resetn)
    (PARITY_EN && pushFlit && parityMismatch) |=> parityError);

  PARITY_ERROR_ONLY_WHEN_ENABLED: assert property (
    @(posedge clk) disable iff (!resetn)
    parityError |-> PARITY_EN);

  LINK_ACTIVATION: cover property (
    @(posedge clk) disable iff (!resetn)
    (linkState == RUN) && ($past(linkState) == ACTIVATE)
      && ($past(linkState, 2) == STOP));

  LINK_DEACTIVATION: cover property (
    @(posedge clk) disable iff (!resetn)
    (linkState == STOP) && ($past(linkState) == DEACTIVATE)
      && ($past(linkState, 2) == RUN));
endmodule

bind chi_link_rx chi_link_rx_sva #(
  .LCRD_DEPTH(LCRD_DEPTH),
  .COUNT_W(COUNT_W),
  .PARITY_EN(PARITY_EN)
) chi_link_rx_assertions (
  .clk(clk),
  .resetn(resetn),
  .FLITV(FLITV),
  .parityError(parityError),
  .bufferOverflow(bufferOverflow),
  .bufferCount(bufferCount),
  .pendingCredits(pendingCredits),
  .pushFlit(pushFlit),
  .parityMismatch(parityMismatch),
  .linkState(linkState)
);
