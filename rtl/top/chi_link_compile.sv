module chi_link_compile #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned FLIT_W = chi_pkg::reqFlitWidth(CFG),
  parameter int unsigned PARITY_W = chi_pkg::parityWidth(FLIT_W),
  parameter int unsigned COUNT_W =
    (CFG.lcrdDepth < 2) ? 1 : $clog2(CFG.lcrdDepth + 1)
) (
  input logic clk,
  input logic resetn
);
  logic activate;
  logic deactivate;
  logic linkActiveReq;
  logic linkActiveAck;
  logic lcrdValid;
  logic internalTxReady;
  logic flitValid;
  logic flitPending;
  logic [FLIT_W-1:0] flit;
  logic [PARITY_W-1:0] flitParity;
  logic internalRxValid;
  logic [FLIT_W-1:0] internalRxFlit;
  logic [COUNT_W-1:0] txCreditCount;
  logic [COUNT_W-1:0] rxBufferCount;
  logic txCreditOverflow;
  logic txCreditUnderflow;
  logic rxParityError;
  logic rxBufferOverflow;
  logic [1:0] txLinkState;
  logic [1:0] rxLinkState;

  always_comb begin
    activate = 1'b1;
    deactivate = 1'b0;
  end

  chi_link_tx #(
    .CFG(CFG),
    .FLIT_W(FLIT_W)
  ) tx (
    .clk(clk),
    .resetn(resetn),
    .activate(activate),
    .deactivate(deactivate),
    .LINKACTIVEREQ(linkActiveReq),
    .LINKACTIVEACK(linkActiveAck),
    .LCRDV(lcrdValid),
    .creditReturn(1'b0),
    .internalValid(1'b0),
    .internalFlit('0),
    .internalTxnId('0),
    .internalReady(internalTxReady),
    .FLITV(flitValid),
    .FLITPEND(flitPending),
    .FLIT(flit),
    .FLITP(flitParity),
    .creditCount(txCreditCount),
    .creditOverflow(txCreditOverflow),
    .creditUnderflow(txCreditUnderflow),
    .linkState(txLinkState)
  );

  chi_link_rx #(
    .CFG(CFG),
    .FLIT_W(FLIT_W)
  ) rx (
    .clk(clk),
    .resetn(resetn),
    .LINKACTIVEREQ(linkActiveReq),
    .LINKACTIVEACK(linkActiveAck),
    .FLITV(flitValid),
    .FLITPEND(flitPending),
    .FLIT(flit),
    .FLITP(flitParity),
    .LCRDV(lcrdValid),
    .internalValid(internalRxValid),
    .internalFlit(internalRxFlit),
    .internalReady(1'b1),
    .parityError(rxParityError),
    .bufferOverflow(rxBufferOverflow),
    .bufferCount(rxBufferCount),
    .linkState(rxLinkState)
  );
endmodule
