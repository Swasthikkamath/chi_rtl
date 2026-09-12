// Node-side link layer for one CHI port, for simulation only.
//
// The interconnect owns only its half of each link: it initiates the
// direction it transmits on and acknowledges the direction it receives on
// (IHI 0050H B13.5). Without a peer on the node side, every receive link
// stays in STOP, no L-Credits are ever issued, and the fabric cannot move a
// flit. This model supplies that peer so that activation and credit exchange
// are actually exercised.
//
// It is the mirror image of chi_link_port. The node initiates its transmit
// direction while out of reset, acknowledges the interconnect's transmit
// direction, and issues L-Credits on the channels it receives. Flits arriving
// from the interconnect are counted and discarded, which keeps the credit
// pool full without needing a protocol model behind it.
//
// Channel applicability follows the port class. A Requester transmits REQ,
// RSP and DAT and receives RSP, SNP and DAT. A Subordinate transmits RSP and
// DAT and receives REQ, RSP and DAT. The interconnect never sends snoops to a
// Subordinate and never accepts them from any node, so the node-transmit snoop
// channel is unused in both directions.
module chi_node_link_bfm #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter bit REQUESTER_PORT = 1'b1,
  parameter int unsigned LCRD_DEPTH = (CFG.lcrdDepth > 1) ? CFG.lcrdDepth : 2,
  parameter int unsigned COUNT_W = $clog2(LCRD_DEPTH + 1)
) (
  input  logic clk,
  input  logic resetn,
  chi_if chiPort,
  // Asserted once both directions of the link have reached RUN, so a
  // stimulus generator can wait for a usable port.
  output logic nodeLinkRun,
  // Transmit credits the interconnect has issued to this node.
  output logic [COUNT_W-1:0] reqTxCredits,
  output logic [COUNT_W-1:0] rspTxCredits,
  output logic [COUNT_W-1:0] datTxCredits,
  // Flits this node has accepted, per channel.
  output int unsigned reqRxCount,
  output int unsigned rspRxCount,
  output int unsigned snpRxCount,
  output int unsigned datRxCount
);
  // The node receives a channel only if the interconnect transmits it.
  localparam bit RX_REQ = !REQUESTER_PORT;
  localparam bit RX_SNP = REQUESTER_PORT;

  logic txLinkRun;
  logic rxLinkAck;

  // Credits this node has issued and not yet seen consumed, per received
  // channel. A credit is returned as soon as the flit is accepted, because
  // this model has no downstream to back-pressure it.
  logic [COUNT_W-1:0] reqRxGranted;
  logic [COUNT_W-1:0] rspRxGranted;
  logic [COUNT_W-1:0] snpRxGranted;
  logic [COUNT_W-1:0] datRxGranted;

  logic reqRxLcrd;
  logic rspRxLcrd;
  logic snpRxLcrd;
  logic datRxLcrd;

  // The node initiates the direction it transmits on. Its transmit link is in
  // RUN once the interconnect has acknowledged.
  always_comb begin
    chiPort.TXLINKACTIVEREQ = resetn;
    chiPort.SYSCOREQ = resetn;
    chiPort.RXLINKACTIVEACK = rxLinkAck;
    txLinkRun = resetn && chiPort.TXLINKACTIVEACK;
    nodeLinkRun = txLinkRun && rxLinkAck && chiPort.RXLINKACTIVEREQ;
  end

  // A receiver acknowledges the request it is sent. This model never
  // deactivates, so the acknowledgement simply follows the request.
  always_ff @(posedge clk) begin
    if (!resetn) rxLinkAck <= 1'b0;
    else rxLinkAck <= chiPort.RXLINKACTIVEREQ;
  end

  // One credit is issued per cycle while the pool is short, which is the
  // behaviour chi_link_rx implements on the other side of the link.
  always_comb begin
    reqRxLcrd = RX_REQ && rxLinkAck && (reqRxGranted < COUNT_W'(LCRD_DEPTH));
    rspRxLcrd = rxLinkAck && (rspRxGranted < COUNT_W'(LCRD_DEPTH));
    snpRxLcrd = RX_SNP && rxLinkAck && (snpRxGranted < COUNT_W'(LCRD_DEPTH));
    datRxLcrd = rxLinkAck && (datRxGranted < COUNT_W'(LCRD_DEPTH));

    chiPort.RXREQLCRDV = reqRxLcrd;
    chiPort.RXRSPLCRDV = rspRxLcrd;
    chiPort.RXSNPLCRDV = snpRxLcrd;
    chiPort.RXDATLCRDV = datRxLcrd;
  end

  // This model originates no traffic. A stimulus generator replaces these
  // tie-offs once there is something to send.
  always_comb begin
    chiPort.TXREQFLITV = 1'b0;
    chiPort.TXREQFLITPEND = 1'b0;
    chiPort.TXREQFLIT = '0;
    chiPort.TXREQFLITCHK = '0;
    chiPort.TXRSPFLITV = 1'b0;
    chiPort.TXRSPFLITPEND = 1'b0;
    chiPort.TXRSPFLIT = '0;
    chiPort.TXRSPFLITCHK = '0;
    chiPort.TXSNPFLITV = 1'b0;
    chiPort.TXSNPFLITPEND = 1'b0;
    chiPort.TXSNPFLIT = '0;
    chiPort.TXSNPFLITCHK = '0;
    chiPort.TXDATFLITV = 1'b0;
    chiPort.TXDATFLITPEND = 1'b0;
    chiPort.TXDATFLIT = '0;
    chiPort.TXDATFLITCHK = '0;
  end

  always_ff @(posedge clk) begin
    if (!resetn) begin
      reqRxGranted <= '0;
      rspRxGranted <= '0;
      snpRxGranted <= '0;
      datRxGranted <= '0;
      reqTxCredits <= '0;
      rspTxCredits <= '0;
      datTxCredits <= '0;
      reqRxCount <= 0;
      rspRxCount <= 0;
      snpRxCount <= 0;
      datRxCount <= 0;
    end else begin
      reqRxGranted <= reqRxGranted + COUNT_W'(reqRxLcrd)
                    - COUNT_W'(chiPort.RXREQFLITV);
      rspRxGranted <= rspRxGranted + COUNT_W'(rspRxLcrd)
                    - COUNT_W'(chiPort.RXRSPFLITV);
      snpRxGranted <= snpRxGranted + COUNT_W'(snpRxLcrd)
                    - COUNT_W'(chiPort.RXSNPFLITV);
      datRxGranted <= datRxGranted + COUNT_W'(datRxLcrd)
                    - COUNT_W'(chiPort.RXDATFLITV);

      reqTxCredits <= reqTxCredits + COUNT_W'(chiPort.TXREQLCRDV);
      rspTxCredits <= rspTxCredits + COUNT_W'(chiPort.TXRSPLCRDV);
      datTxCredits <= datTxCredits + COUNT_W'(chiPort.TXDATLCRDV);

      if (chiPort.RXREQFLITV) reqRxCount <= reqRxCount + 1;
      if (chiPort.RXRSPFLITV) rspRxCount <= rspRxCount + 1;
      if (chiPort.RXSNPFLITV) snpRxCount <= snpRxCount + 1;
      if (chiPort.RXDATFLITV) datRxCount <= datRxCount + 1;
    end
  end
endmodule
