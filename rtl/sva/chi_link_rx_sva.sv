module chi_link_rx_sva #(
  parameter int unsigned LCRD_DEPTH = 8,
  parameter int unsigned COUNT_W =
    (LCRD_DEPTH < 2) ? 1 : $clog2(LCRD_DEPTH + 1),
  parameter bit PARITY_EN = 1'b0,
  parameter int unsigned FLIT_W = 8,
  parameter int unsigned PARITY_W = (FLIT_W + 7) / 8
) (
  input logic clk,
  input logic resetn,
  input logic FLITV,
  input logic [FLIT_W-1:0] FLIT,
  input logic [PARITY_W-1:0] FLITP,
  input logic parityError,
  input logic bufferOverflow,
  input logic [COUNT_W-1:0] bufferCount,
  input logic [COUNT_W-1:0] pendingCredits,
  input logic [COUNT_W-1:0] peerCredits,
  input logic lcrdReturnFlit,
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

  // A flit is legal in DEACTIVATE as well as in RUN: the Transmitter can race
  // its last protocol flit against the deassertion of LINKACTIVEREQ, and the
  // L-Credit return flits are only sent once in DEACTIVATE (IHI 0050H B14.5).
  NO_RECEIVE_OUTSIDE_ACTIVE: assert property (
    @(posedge clk) disable iff (!resetn)
    FLITV |-> ((linkState == RUN) || (linkState == DEACTIVATE)));

  // An LCrdReturn returns a credit and carries no message, so it must never
  // reach the protocol layer (IHI 0050H B13.11).
  LCRD_RETURN_NOT_DELIVERED: assert property (
    @(posedge clk) disable iff (!resetn)
    (FLITV && lcrdReturnFlit) |-> !pushFlit);

  PEER_CREDITS_IN_RANGE: assert property (
    @(posedge clk) disable iff (!resetn)
    peerCredits <= LCRD_DEPTH_COUNT);

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

  // The link may only go back to STOP once the buffer is empty and every
  // credit issued to the peer has been returned (IHI 0050H B14.6.3.2).
  DEACTIVATION_BUFFER_DRAINED: assert property (
    @(posedge clk) disable iff (!resetn)
    ($past(linkState) == DEACTIVATE) && (linkState == STOP)
      |-> (($past(bufferCount) == '0)
           && ($past(peerCredits) == '0)));

  // Odd byte parity (IHI 0050H B9.3.1), computed independently of the
  // checker: a mismatch is exactly a byte that, with its check bit, holds an
  // even number of ones.
  function automatic logic parityOdd(
    input logic [FLIT_W-1:0] flit,
    input logic [PARITY_W-1:0] check
  );
    logic odd;
    logic bytesOdd;
    bytesOdd = 1'b1;
    for (int unsigned b = 0; b < PARITY_W; b++) begin
      odd = check[b];
      for (int unsigned i = 0; i < 8; i++)
        if ((b * 8 + i) < FLIT_W)
          odd = odd ^ flit[b * 8 + i];
      bytesOdd = bytesOdd && odd;
    end
    return bytesOdd;
  endfunction

  RX_PARITY_CHECK_ODD: assert property (
    @(posedge clk) disable iff (!resetn)
    PARITY_EN |-> (parityMismatch == !parityOdd(FLIT, FLITP)));

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
  .PARITY_EN(PARITY_EN),
  .FLIT_W(FLIT_W),
  .PARITY_W(PARITY_W)
) chi_link_rx_assertions (
  .clk(clk),
  .resetn(resetn),
  .FLITV(FLITV),
  .FLIT(FLIT),
  .FLITP(FLITP),
  .parityError(parityError),
  .bufferOverflow(bufferOverflow),
  .bufferCount(bufferCount),
  .pendingCredits(pendingCredits),
  .peerCredits(peerCredits),
  .lcrdReturnFlit(lcrdReturnFlit),
  .pushFlit(pushFlit),
  .parityMismatch(parityMismatch),
  .linkState(linkState)
);
