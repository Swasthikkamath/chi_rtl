module chi_link_tx #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned FLIT_W = chi_pkg::reqFlitWidth(CFG),
  parameter int unsigned TXNID_W = CFG.txnIdW,
  parameter int unsigned LCRD_DEPTH = CFG.lcrdDepth,
  parameter int unsigned REPL_CHANNELS = CFG.replChannels,
  parameter int unsigned LANE_ID = 0,
  parameter bit PARITY_EN = CFG.parityEn,
  parameter int unsigned PARITY_W = (FLIT_W + 7) / 8,
  parameter int unsigned COUNT_W =
    (LCRD_DEPTH < 2) ? 1 : $clog2(LCRD_DEPTH + 1)
) (
  input  logic                  clk,
  input  logic                  resetn,
  input  logic                  activate,
  input  logic                  deactivate,
  output logic                  LINKACTIVEREQ,
  input  logic                  LINKACTIVEACK,
  input  logic                  LCRDV,
  input  logic                  creditReturn,
  input  logic                  internalValid,
  input  logic [FLIT_W-1:0]     internalFlit,
  input  logic [TXNID_W-1:0]    internalTxnId,
  output logic                  internalReady,
  output logic                  FLITV,
  output logic                  FLITPEND,
  output logic [FLIT_W-1:0]     FLIT,
  output logic [PARITY_W-1:0]   FLITP,
  output logic [COUNT_W-1:0]    creditCount,
  output logic                  creditOverflow,
  output logic                  creditUnderflow,
  output logic [1:0]            linkState
);
  localparam logic [1:0] LINK_DEACTIVATE = 2'b11;

  logic creditAvailable;
  logic creditsFull;
  logic linkRun;
  logic laneSelected;
  int unsigned laneIndex;
  logic flitTransfer;
  logic lcrdReturnSend;
  logic [FLIT_W-1:0] outboundFlit;
  logic deactivateSafe;

  always_comb begin
    laneIndex = 32'(internalTxnId);
    if (REPL_CHANNELS <= 1) begin
      laneSelected = (LANE_ID == 0);
    end else begin
      laneSelected = ((laneIndex % REPL_CHANNELS) == LANE_ID);
    end
    internalReady = linkRun && creditAvailable && laneSelected;
    flitTransfer = internalValid && internalReady;
    // Every credit still held when the link deactivates has to be handed back
    // with an LCrdReturn flit, and the link stays in DEACTIVATE until the last
    // one has gone (IHI 0050H B13.11, B14.6.3.2). An LCrdReturn is a zero
    // Opcode and a zero TxnID with every other field unused, so an all-zero
    // flit is one.
    lcrdReturnSend = (linkState == LINK_DEACTIVATE) && creditAvailable;
    outboundFlit = lcrdReturnSend ? '0 : internalFlit;
    // Deactivation only waits for the protocol side to go quiet; the credits
    // are returned from the DEACTIVATE state itself rather than collected
    // before entering it.
    deactivateSafe = deactivate && !(internalValid && laneSelected);
  end

  chi_lcrd_mgr #(
    .LCRD_DEPTH(LCRD_DEPTH),
    .COUNT_W(COUNT_W)
  ) creditManager (
    .clk(clk),
    .resetn(resetn),
    .creditGrant(LCRDV),
    .creditReturn(creditReturn),
    .creditConsume(flitTransfer || lcrdReturnSend),
    .creditCount(creditCount),
    .creditAvailable(creditAvailable),
    .creditsFull(creditsFull),
    .overflow(creditOverflow),
    .underflow(creditUnderflow)
  );

  chi_link_fsm #(
    .INITIATOR(1'b1)
  ) activationFsm (
    .clk(clk),
    .resetn(resetn),
    .activate(activate),
    .deactivate(deactivateSafe),
    .peerLinkActive(LINKACTIVEACK),
    .creditsQuiescent(!creditAvailable),
    .linkActive(LINKACTIVEREQ),
    .linkRun(linkRun),
    .state(linkState)
  );

  integer byteIndex;
  integer bitIndex;
  always_comb begin
    FLITV = flitTransfer || lcrdReturnSend;
    FLITPEND = (internalValid && laneSelected) || lcrdReturnSend;
    FLIT = outboundFlit;
    FLITP = '0;
    if (PARITY_EN) begin
      for (byteIndex = 0; byteIndex < PARITY_W; byteIndex = byteIndex + 1) begin
        for (bitIndex = 0; bitIndex < 8; bitIndex = bitIndex + 1) begin
          if (((byteIndex * 8) + bitIndex) < FLIT_W) begin
            FLITP[byteIndex] =
              FLITP[byteIndex] ^ outboundFlit[(byteIndex * 8) + bitIndex];
          end
        end
      end
    end
  end
endmodule
