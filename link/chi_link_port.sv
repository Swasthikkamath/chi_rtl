// Link layer for one CHI port (IHI 0050H B13).
//
// This wrapper puts a real credit-based link between a node's CHI pins and
// the interconnect's internal ready/valid fabric. Each channel gets its own
// L-Credit accounting and receive buffer, while the link activation handshake
// is shared by every channel in one direction because activation is a
// property of the link, not of a channel (IHI 0050H B13.5).
//
// The shared activation signals combine the per-channel state with an OR.
// Every channel in a direction leaves STOP on the same cycle, so the OR
// matches an AND at activation; during deactivation the OR holds the
// handshake asserted until the last channel has returned its credits, which
// is what the link FSM requires.
//
// A Requester port receives REQ, RSP, and DAT from the node and transmits
// RSP, SNP, and DAT to it. A Subordinate port receives RSP and DAT and
// transmits REQ, RSP, and DAT. Channels a port does not use are tied off.
//
// The interface signals are mirrored into local nets before they reach the
// channel instances. That keeps every instance pin a plain net, which avoids
// a Verilator elaboration failure on interface members used as instance pins.
module chi_link_port #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter bit REQUESTER_PORT = 1'b1,
  parameter int unsigned REQ_FLIT_W = chi_pkg::reqFlitWidth(CFG),
  parameter int unsigned RSP_FLIT_W = chi_pkg::rspFlitWidth(CFG),
  parameter int unsigned SNP_FLIT_W = chi_pkg::snpFlitWidth(CFG),
  parameter int unsigned DAT_FLIT_W = chi_pkg::datFlitWidth(CFG)
) (
  input  logic clk,
  input  logic resetn,
  chi_if chiPort,
  output logic reqRxValid,
  input  logic reqRxReady,
  output logic [REQ_FLIT_W-1:0] reqRxFlit,
  output logic rspRxValid,
  input  logic rspRxReady,
  output logic [RSP_FLIT_W-1:0] rspRxFlit,
  output logic datRxValid,
  input  logic datRxReady,
  output logic [DAT_FLIT_W-1:0] datRxFlit,
  input  logic reqTxValid,
  output logic reqTxReady,
  input  logic [REQ_FLIT_W-1:0] reqTxFlit,
  input  logic rspTxValid,
  output logic rspTxReady,
  input  logic [RSP_FLIT_W-1:0] rspTxFlit,
  input  logic snpTxValid,
  output logic snpTxReady,
  input  logic [SNP_FLIT_W-1:0] snpTxFlit,
  input  logic datTxValid,
  output logic datTxReady,
  input  logic [DAT_FLIT_W-1:0] datTxFlit,
  output logic linkUp,
  output logic parityError,
  output logic creditError
);
  import chi_pkg::*;

  localparam int unsigned LCRD_DEPTH =
    (CFG.lcrdDepth > 1) ? CFG.lcrdDepth : 2;
  localparam int unsigned COUNT_W = $clog2(LCRD_DEPTH + 1);
  localparam int unsigned REQ_CHK_W = parityWidth(REQ_FLIT_W);
  localparam int unsigned RSP_CHK_W = parityWidth(RSP_FLIT_W);
  localparam int unsigned SNP_CHK_W = parityWidth(SNP_FLIT_W);
  localparam int unsigned DAT_CHK_W = parityWidth(DAT_FLIT_W);
  localparam logic [1:0] LINK_RUN = 2'b10;

  logic txLinkActiveReq;
  logic txLinkActiveAck;
  logic rxLinkActiveReq;
  logic rxLinkActiveAck;

  logic nodeReqFlitV;
  logic nodeReqFlitPend;
  logic [REQ_FLIT_W-1:0] nodeReqFlit;
  logic [REQ_CHK_W-1:0] nodeReqFlitChk;
  logic nodeReqLcrdV;
  logic nodeRspFlitV;
  logic nodeRspFlitPend;
  logic [RSP_FLIT_W-1:0] nodeRspFlit;
  logic [RSP_CHK_W-1:0] nodeRspFlitChk;
  logic nodeRspLcrdV;
  logic nodeDatFlitV;
  logic nodeDatFlitPend;
  logic [DAT_FLIT_W-1:0] nodeDatFlit;
  logic [DAT_CHK_W-1:0] nodeDatFlitChk;
  logic nodeDatLcrdV;

  logic hostReqFlitV;
  logic hostReqFlitPend;
  logic [REQ_FLIT_W-1:0] hostReqFlit;
  logic [REQ_CHK_W-1:0] hostReqFlitChk;
  logic hostReqLcrdV;
  logic hostRspFlitV;
  logic hostRspFlitPend;
  logic [RSP_FLIT_W-1:0] hostRspFlit;
  logic [RSP_CHK_W-1:0] hostRspFlitChk;
  logic hostRspLcrdV;
  logic hostSnpFlitV;
  logic hostSnpFlitPend;
  logic [SNP_FLIT_W-1:0] hostSnpFlit;
  logic [SNP_CHK_W-1:0] hostSnpFlitChk;
  logic hostSnpLcrdV;
  logic hostDatFlitV;
  logic hostDatFlitPend;
  logic [DAT_FLIT_W-1:0] hostDatFlit;
  logic [DAT_CHK_W-1:0] hostDatFlitChk;
  logic hostDatLcrdV;

  // The interconnect initiates its own transmit links and keeps them running
  // while out of reset. Sequenced power-down is left to integration.
  logic txActivate;

  logic reqRxActive;
  logic rspRxActive;
  logic datRxActive;
  logic reqTxActive;
  logic rspTxActive;
  logic snpTxActive;
  logic datTxActive;

  logic reqRxParityError;
  logic rspRxParityError;
  logic datRxParityError;
  logic reqRxOverflow;
  logic rspRxOverflow;
  logic datRxOverflow;
  logic reqTxOverflow;
  logic rspTxOverflow;
  logic snpTxOverflow;
  logic datTxOverflow;
  logic reqTxUnderflow;
  logic rspTxUnderflow;
  logic snpTxUnderflow;
  logic datTxUnderflow;

  logic [1:0] reqRxState;
  logic [1:0] rspRxState;
  logic [1:0] datRxState;
  logic [1:0] reqTxState;
  logic [1:0] rspTxState;
  logic [1:0] snpTxState;
  logic [1:0] datTxState;
  logic [COUNT_W-1:0] reqRxCount;
  logic [COUNT_W-1:0] rspRxCount;
  logic [COUNT_W-1:0] datRxCount;
  logic [COUNT_W-1:0] reqTxCount;
  logic [COUNT_W-1:0] rspTxCount;
  logic [COUNT_W-1:0] snpTxCount;
  logic [COUNT_W-1:0] datTxCount;

  always_comb begin
    txActivate = resetn;

    nodeReqFlitV = chiPort.TXREQFLITV;
    nodeReqFlitPend = chiPort.TXREQFLITPEND;
    nodeReqFlit = chiPort.TXREQFLIT;
    nodeReqFlitChk = chiPort.TXREQFLITCHK;
    nodeRspFlitV = chiPort.TXRSPFLITV;
    nodeRspFlitPend = chiPort.TXRSPFLITPEND;
    nodeRspFlit = chiPort.TXRSPFLIT;
    nodeRspFlitChk = chiPort.TXRSPFLITCHK;
    nodeDatFlitV = chiPort.TXDATFLITV;
    nodeDatFlitPend = chiPort.TXDATFLITPEND;
    nodeDatFlit = chiPort.TXDATFLIT;
    nodeDatFlitChk = chiPort.TXDATFLITCHK;
    txLinkActiveReq = chiPort.TXLINKACTIVEREQ;
    rxLinkActiveAck = chiPort.RXLINKACTIVEACK;
    hostReqLcrdV = chiPort.RXREQLCRDV;
    hostRspLcrdV = chiPort.RXRSPLCRDV;
    hostSnpLcrdV = chiPort.RXSNPLCRDV;
    hostDatLcrdV = chiPort.RXDATLCRDV;

    txLinkActiveAck = reqRxActive || rspRxActive || datRxActive;
    rxLinkActiveReq = reqTxActive || rspTxActive || snpTxActive
                      || datTxActive;
    linkUp = (reqRxState == LINK_RUN) || (rspRxState == LINK_RUN)
             || (datRxState == LINK_RUN);
    parityError = reqRxParityError || rspRxParityError || datRxParityError;
    creditError = reqRxOverflow || rspRxOverflow || datRxOverflow
                  || reqTxOverflow || rspTxOverflow || snpTxOverflow
                  || datTxOverflow || reqTxUnderflow || rspTxUnderflow
                  || snpTxUnderflow || datTxUnderflow;

    chiPort.CLK = clk;
    chiPort.RESETn = resetn;
    chiPort.TXSACTIVE = resetn;
    chiPort.RXSACTIVE = resetn;
    chiPort.SYSCOACK = chiPort.SYSCOREQ;
    chiPort.TXLINKACTIVEACK = txLinkActiveAck;
    chiPort.RXLINKACTIVEREQ = rxLinkActiveReq;
    chiPort.TXREQLCRDV = nodeReqLcrdV;
    chiPort.TXRSPLCRDV = nodeRspLcrdV;
    chiPort.TXDATLCRDV = nodeDatLcrdV;
    // No port in this design receives snoops from a node.
    chiPort.TXSNPLCRDV = 1'b0;
    chiPort.RXREQFLITV = hostReqFlitV;
    chiPort.RXREQFLITPEND = hostReqFlitPend;
    chiPort.RXREQFLIT = hostReqFlit;
    chiPort.RXREQFLITCHK = hostReqFlitChk;
    chiPort.RXRSPFLITV = hostRspFlitV;
    chiPort.RXRSPFLITPEND = hostRspFlitPend;
    chiPort.RXRSPFLIT = hostRspFlit;
    chiPort.RXRSPFLITCHK = hostRspFlitChk;
    chiPort.RXSNPFLITV = hostSnpFlitV;
    chiPort.RXSNPFLITPEND = hostSnpFlitPend;
    chiPort.RXSNPFLIT = hostSnpFlit;
    chiPort.RXSNPFLITCHK = hostSnpFlitChk;
    chiPort.RXDATFLITV = hostDatFlitV;
    chiPort.RXDATFLITPEND = hostDatFlitPend;
    chiPort.RXDATFLIT = hostDatFlit;
    chiPort.RXDATFLITCHK = hostDatFlitChk;

    chiPort.TXLINKACTIVEREQCHK = 1'b0;
    chiPort.TXLINKACTIVEACKCHK = 1'b0;
    chiPort.RXLINKACTIVEREQCHK = 1'b0;
    chiPort.RXLINKACTIVEACKCHK = 1'b0;
    chiPort.TXSACTIVECHK = 1'b0;
    chiPort.RXSACTIVECHK = 1'b0;
    chiPort.SYSCOREQCHK = 1'b0;
    chiPort.SYSCOACKCHK = 1'b0;
    chiPort.TXREQFLITPENDCHK = 1'b0;
    chiPort.TXREQFLITVCHK = 1'b0;
    chiPort.TXREQLCRDVCHK = 1'b0;
    chiPort.TXRSPFLITPENDCHK = 1'b0;
    chiPort.TXRSPFLITVCHK = 1'b0;
    chiPort.TXRSPLCRDVCHK = 1'b0;
    chiPort.TXSNPFLITPENDCHK = 1'b0;
    chiPort.TXSNPFLITVCHK = 1'b0;
    chiPort.TXSNPLCRDVCHK = 1'b0;
    chiPort.TXDATFLITPENDCHK = 1'b0;
    chiPort.TXDATFLITVCHK = 1'b0;
    chiPort.TXDATLCRDVCHK = 1'b0;
    chiPort.RXREQFLITPENDCHK = 1'b0;
    chiPort.RXREQFLITVCHK = 1'b0;
    chiPort.RXREQLCRDVCHK = 1'b0;
    chiPort.RXRSPFLITPENDCHK = 1'b0;
    chiPort.RXRSPFLITVCHK = 1'b0;
    chiPort.RXRSPLCRDVCHK = 1'b0;
    chiPort.RXSNPFLITPENDCHK = 1'b0;
    chiPort.RXSNPFLITVCHK = 1'b0;
    chiPort.RXSNPLCRDVCHK = 1'b0;
    chiPort.RXDATFLITPENDCHK = 1'b0;
    chiPort.RXDATFLITVCHK = 1'b0;
    chiPort.RXDATLCRDVCHK = 1'b0;
  end

  // A Requester drives requests into the interconnect; a Subordinate never
  // does, so that receiver is replaced by a tie-off.
  if (REQUESTER_PORT) begin : req_receiver
    chi_link_rx #(
      .CFG(CFG), .FLIT_W(REQ_FLIT_W), .LCRD_DEPTH(LCRD_DEPTH),
      .PARITY_EN(CFG.parityEn), .COUNT_W(COUNT_W)
    ) req_rx (
      .clk, .resetn, .LINKACTIVEREQ(txLinkActiveReq),
      .LINKACTIVEACK(reqRxActive), .FLITV(nodeReqFlitV),
      .FLITPEND(nodeReqFlitPend), .FLIT(nodeReqFlit),
      .FLITP(nodeReqFlitChk), .LCRDV(nodeReqLcrdV),
      .internalValid(reqRxValid), .internalFlit(reqRxFlit),
      .internalReady(reqRxReady), .parityError(reqRxParityError),
      .bufferOverflow(reqRxOverflow), .bufferCount(reqRxCount),
      .linkState(reqRxState)
    );
  end else begin : no_req_receiver
    always_comb begin
      reqRxActive = 1'b0;
      reqRxValid = 1'b0;
      reqRxFlit = '0;
      reqRxParityError = 1'b0;
      reqRxOverflow = 1'b0;
      reqRxCount = '0;
      reqRxState = 2'b00;
      nodeReqLcrdV = 1'b0;
    end
  end

  chi_link_rx #(
    .CFG(CFG), .FLIT_W(RSP_FLIT_W), .LCRD_DEPTH(LCRD_DEPTH),
    .PARITY_EN(CFG.parityEn), .COUNT_W(COUNT_W)
  ) rsp_rx (
    .clk, .resetn, .LINKACTIVEREQ(txLinkActiveReq),
    .LINKACTIVEACK(rspRxActive), .FLITV(nodeRspFlitV),
    .FLITPEND(nodeRspFlitPend), .FLIT(nodeRspFlit),
    .FLITP(nodeRspFlitChk), .LCRDV(nodeRspLcrdV),
    .internalValid(rspRxValid), .internalFlit(rspRxFlit),
    .internalReady(rspRxReady), .parityError(rspRxParityError),
    .bufferOverflow(rspRxOverflow), .bufferCount(rspRxCount),
    .linkState(rspRxState)
  );

  chi_link_rx #(
    .CFG(CFG), .FLIT_W(DAT_FLIT_W), .LCRD_DEPTH(LCRD_DEPTH),
    .PARITY_EN(CFG.parityEn), .COUNT_W(COUNT_W)
  ) dat_rx (
    .clk, .resetn, .LINKACTIVEREQ(txLinkActiveReq),
    .LINKACTIVEACK(datRxActive), .FLITV(nodeDatFlitV),
    .FLITPEND(nodeDatFlitPend), .FLIT(nodeDatFlit),
    .FLITP(nodeDatFlitChk), .LCRDV(nodeDatLcrdV),
    .internalValid(datRxValid), .internalFlit(datRxFlit),
    .internalReady(datRxReady), .parityError(datRxParityError),
    .bufferOverflow(datRxOverflow), .bufferCount(datRxCount),
    .linkState(datRxState)
  );

  // Only a Subordinate port is sent requests.
  if (REQUESTER_PORT) begin : no_req_transmitter
    always_comb begin
      reqTxActive = 1'b0;
      reqTxReady = 1'b0;
      reqTxOverflow = 1'b0;
      reqTxUnderflow = 1'b0;
      reqTxCount = '0;
      reqTxState = 2'b00;
      hostReqFlitPend = 1'b0;
      hostReqFlitV = 1'b0;
      hostReqFlit = '0;
      hostReqFlitChk = '0;
    end
  end else begin : req_transmitter
    chi_link_tx #(
      .CFG(CFG), .FLIT_W(REQ_FLIT_W), .TXNID_W(CFG.txnIdW),
      .LCRD_DEPTH(LCRD_DEPTH), .REPL_CHANNELS(1), .LANE_ID(0),
      .PARITY_EN(CFG.parityEn), .COUNT_W(COUNT_W)
    ) req_tx (
      .clk, .resetn, .activate(txActivate), .deactivate(1'b0),
      .LINKACTIVEREQ(reqTxActive), .LINKACTIVEACK(rxLinkActiveAck),
      .LCRDV(hostReqLcrdV), .creditReturn(1'b0),
      .internalValid(reqTxValid), .internalFlit(reqTxFlit),
      .internalTxnId('0), .internalReady(reqTxReady),
      .FLITV(hostReqFlitV), .FLITPEND(hostReqFlitPend),
      .FLIT(hostReqFlit), .FLITP(hostReqFlitChk),
      .creditCount(reqTxCount), .creditOverflow(reqTxOverflow),
      .creditUnderflow(reqTxUnderflow), .linkState(reqTxState)
    );
  end

  chi_link_tx #(
    .CFG(CFG), .FLIT_W(RSP_FLIT_W), .TXNID_W(CFG.txnIdW),
    .LCRD_DEPTH(LCRD_DEPTH), .REPL_CHANNELS(1), .LANE_ID(0),
    .PARITY_EN(CFG.parityEn), .COUNT_W(COUNT_W)
  ) rsp_tx (
    .clk, .resetn, .activate(txActivate), .deactivate(1'b0),
    .LINKACTIVEREQ(rspTxActive), .LINKACTIVEACK(rxLinkActiveAck),
    .LCRDV(hostRspLcrdV), .creditReturn(1'b0),
    .internalValid(rspTxValid), .internalFlit(rspTxFlit),
    .internalTxnId('0), .internalReady(rspTxReady),
    .FLITV(hostRspFlitV), .FLITPEND(hostRspFlitPend),
    .FLIT(hostRspFlit), .FLITP(hostRspFlitChk),
    .creditCount(rspTxCount), .creditOverflow(rspTxOverflow),
    .creditUnderflow(rspTxUnderflow), .linkState(rspTxState)
  );

  // Only a Requester port is sent snoops.
  if (REQUESTER_PORT) begin : snp_transmitter
    chi_link_tx #(
      .CFG(CFG), .FLIT_W(SNP_FLIT_W), .TXNID_W(CFG.txnIdW),
      .LCRD_DEPTH(LCRD_DEPTH), .REPL_CHANNELS(1), .LANE_ID(0),
      .PARITY_EN(CFG.parityEn), .COUNT_W(COUNT_W)
    ) snp_tx (
      .clk, .resetn, .activate(txActivate), .deactivate(1'b0),
      .LINKACTIVEREQ(snpTxActive), .LINKACTIVEACK(rxLinkActiveAck),
      .LCRDV(hostSnpLcrdV), .creditReturn(1'b0),
      .internalValid(snpTxValid), .internalFlit(snpTxFlit),
      .internalTxnId('0), .internalReady(snpTxReady),
      .FLITV(hostSnpFlitV), .FLITPEND(hostSnpFlitPend),
      .FLIT(hostSnpFlit), .FLITP(hostSnpFlitChk),
      .creditCount(snpTxCount), .creditOverflow(snpTxOverflow),
      .creditUnderflow(snpTxUnderflow), .linkState(snpTxState)
    );
  end else begin : no_snp_transmitter
    always_comb begin
      snpTxActive = 1'b0;
      snpTxReady = 1'b0;
      snpTxOverflow = 1'b0;
      snpTxUnderflow = 1'b0;
      snpTxCount = '0;
      snpTxState = 2'b00;
      hostSnpFlitPend = 1'b0;
      hostSnpFlitV = 1'b0;
      hostSnpFlit = '0;
      hostSnpFlitChk = '0;
    end
  end

  chi_link_tx #(
    .CFG(CFG), .FLIT_W(DAT_FLIT_W), .TXNID_W(CFG.txnIdW),
    .LCRD_DEPTH(LCRD_DEPTH), .REPL_CHANNELS(1), .LANE_ID(0),
    .PARITY_EN(CFG.parityEn), .COUNT_W(COUNT_W)
  ) dat_tx (
    .clk, .resetn, .activate(txActivate), .deactivate(1'b0),
    .LINKACTIVEREQ(datTxActive), .LINKACTIVEACK(rxLinkActiveAck),
    .LCRDV(hostDatLcrdV), .creditReturn(1'b0),
    .internalValid(datTxValid), .internalFlit(datTxFlit),
    .internalTxnId('0), .internalReady(datTxReady),
    .FLITV(hostDatFlitV), .FLITPEND(hostDatFlitPend),
    .FLIT(hostDatFlit), .FLITP(hostDatFlitChk),
    .creditCount(datTxCount), .creditOverflow(datTxOverflow),
    .creditUnderflow(datTxUnderflow), .linkState(datTxState)
  );
endmodule
