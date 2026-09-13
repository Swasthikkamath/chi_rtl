// CHI link layer peer, shared by the Requester and Subordinate driver BFMs.
//
// Included inside a driver BFM interface. The includer must provide a chi_if
// port named chiPort and a REQUESTER_PORT parameter, and must import
// chiGlobalsPkg.
//
// The fabric owns only its half of every link: it initiates the direction it
// transmits on and acknowledges the direction it receives on. With no peer on
// the node side each receive link stays in STOP, no L-Credits are ever issued
// and no flit can move, so the testbench has to supply a real link layer
// before any protocol activity is possible [SPEC:IHI0050H B13.5].
//
// This is the mirror image of link/chi_link_port. Unlike tb/chi_node_link_bfm,
// which counts arriving flits and throws them away, received flits are queued
// for the protocol layer above to read, because the whole point here is to
// respond to them.
//
// Three of the DUT's own receive assertions constrain what this may do, and
// all three are satisfied by one rule: never present a flit without holding a
// credit for it. Credits are only issued from the RUN state, so a held credit
// is itself proof that the far side is ready, which is what
// NO_RECEIVE_OUTSIDE_ACTIVE, NO_BUFFER_OVERFLOW and PEER_CREDITS_IN_RANGE
// each require [sva/chi_link_rx_sva.sv].

localparam int unsigned LCRD_DEPTH =
    (CHI_CFG.lcrdDepth > 1) ? CHI_CFG.lcrdDepth : 2;
localparam int unsigned CREDIT_W = $clog2(LCRD_DEPTH + 1);

// A Requester transmits REQ, RSP and DAT and receives RSP, SNP and DAT. A
// Subordinate transmits RSP and DAT and receives REQ, RSP and DAT. Neither
// class ever transmits a snoop [SPEC:IHI0050H B13.3]. Two of these are wider
// than the protocol needs and match what the fabric's link ports do: see the
// note on channelApplies in chiGlobalsPkg.
localparam bit TX_REQ_APPLIES = REQUESTER_PORT;
localparam bit TX_RSP_APPLIES = 1'b1;
localparam bit TX_DAT_APPLIES = 1'b1;
localparam bit RX_REQ_APPLIES = !REQUESTER_PORT;
localparam bit RX_RSP_APPLIES = 1'b1;
localparam bit RX_SNP_APPLIES = REQUESTER_PORT;
localparam bit RX_DAT_APPLIES = 1'b1;

// ---------------------------------------------------------------------------
// Activation
// ---------------------------------------------------------------------------
// linkEnable gates the transmit direction, which this side initiates.
// sysCoReqDrive is separate because system coherency entry is a protocol level
// decision made by a fully coherent Requester, not part of link bring-up
// [SPEC:IHI0050H B14.7].
bit linkEnable = 1'b0;
bit sysCoReqDrive = 1'b0;

chiLinkStateE txLinkState;
chiLinkStateE rxLinkState;

bit rxLinkAck;

// Signal ownership is split with link/chi_link_port, which drives everything
// this block does not: CLK, RESETn, SYSCOACK, TXLINKACTIVEACK,
// RXLINKACTIVEREQ, the TX L-Credit valids, the whole RX flit group and every
// single-bit check pin. The node therefore owns exactly three control signals,
// the RX L-Credit valids and the TX flit groups, and driving anything else
// would put two drivers on one variable.
//
// TXSACTIVE and RXSACTIVE are among the signals the fabric drives, even though
// the spec makes TXSACTIVE the transmitting node's [SPEC:IHI0050H B14.4]. See
// OPEN QUESTIONS.
always_comb begin
  chiPort.TXLINKACTIVEREQ = linkEnable;
  chiPort.RXLINKACTIVEACK = rxLinkAck;
  chiPort.SYSCOREQ        = sysCoReqDrive;
end

// This side acknowledges the direction it receives on. Stage 1 never
// deactivates a link, so the acknowledgement simply follows the request.
always_ff @(posedge chiPort.CLK) begin
  if (!chiPort.RESETn) rxLinkAck <= 1'b0;
  else                 rxLinkAck <= chiPort.RXLINKACTIVEREQ;
end

// Both directions are tracked as a four state FSM rather than a single
// "running" bit so the monitor can report real state transitions
// [SPEC:IHI0050H B14.5.1 Table B14.1].
always_ff @(posedge chiPort.CLK) begin
  if (!chiPort.RESETn) begin
    txLinkState <= CHI_LINK_STOP;
    rxLinkState <= CHI_LINK_STOP;
  end else begin
    case (txLinkState)
      CHI_LINK_STOP:
        if (linkEnable) txLinkState <= CHI_LINK_ACTIVATE;
      CHI_LINK_ACTIVATE: begin
        if (!linkEnable)                    txLinkState <= CHI_LINK_DEACTIVATE;
        else if (chiPort.TXLINKACTIVEACK)   txLinkState <= CHI_LINK_RUN;
      end
      CHI_LINK_RUN:
        if (!linkEnable) txLinkState <= CHI_LINK_DEACTIVATE;
      CHI_LINK_DEACTIVATE:
        if (!chiPort.TXLINKACTIVEACK) txLinkState <= CHI_LINK_STOP;
      default: txLinkState <= CHI_LINK_STOP;
    endcase

    case (rxLinkState)
      CHI_LINK_STOP:
        if (chiPort.RXLINKACTIVEREQ) rxLinkState <= CHI_LINK_ACTIVATE;
      CHI_LINK_ACTIVATE: begin
        if (!chiPort.RXLINKACTIVEREQ) rxLinkState <= CHI_LINK_DEACTIVATE;
        else if (rxLinkAck)           rxLinkState <= CHI_LINK_RUN;
      end
      CHI_LINK_RUN:
        if (!chiPort.RXLINKACTIVEREQ) rxLinkState <= CHI_LINK_DEACTIVATE;
      CHI_LINK_DEACTIVATE:
        rxLinkState <= CHI_LINK_STOP;
      default: rxLinkState <= CHI_LINK_STOP;
    endcase
  end
end

// ---------------------------------------------------------------------------
// Transmit
// ---------------------------------------------------------------------------
// Each channel is a queue drained by one clocked process. Presenting flits
// from a single process, rather than from whichever thread happened to call a
// send task, is what makes the credit accounting atomic: the decision to spend
// a credit and the assertion of FLITV happen together and cannot interleave
// with another sender on the same channel.
logic [REQ_FLIT_W-1:0] reqTxQueue [$];
logic [RSP_FLIT_W-1:0] rspTxQueue [$];
logic [DAT_FLIT_W-1:0] datTxQueue [$];

logic [CREDIT_W-1:0] reqTxCredits;
logic [CREDIT_W-1:0] rspTxCredits;
logic [CREDIT_W-1:0] datTxCredits;

// Flits actually presented, so a send task can block until its own flit has
// gone rather than merely until it was queued.
int unsigned reqTxSent;
int unsigned rspTxSent;
int unsigned datTxSent;

// FLITPEND is a wake-up hint raised while a flit is waiting, ahead of the
// credit that will let it go [SPEC:IHI0050H B14.3]. The DUT's receiver ignores
// it, but it is driven correctly so the pins tell the truth.
always_comb begin
  chiPort.TXREQFLITPEND = TX_REQ_APPLIES && (reqTxQueue.size() != 0);
  chiPort.TXRSPFLITPEND = TX_RSP_APPLIES && (rspTxQueue.size() != 0);
  chiPort.TXDATFLITPEND = TX_DAT_APPLIES && (datTxQueue.size() != 0);
  chiPort.TXSNPFLITPEND = 1'b0;
end

// This side never transmits snoops in either class, so the whole channel is
// held quiet.
always_comb begin
  chiPort.TXSNPFLITV = 1'b0;
  chiPort.TXSNPFLIT  = '0;
end

`define CHI_TX_CHANNEL(QUEUE, CREDITS, SENT, APPLIES, FLITV, FLIT, LCRDV)   \
  always_ff @(posedge chiPort.CLK) begin                                    \
    if (!chiPort.RESETn) begin                                              \
      CREDITS <= '0;                                                        \
      SENT    <= 0;                                                         \
      FLITV   <= 1'b0;                                                      \
      FLIT    <= '0;                                                        \
      QUEUE.delete();                                                       \
    end else begin                                                          \
      FLITV <= 1'b0;                                                        \
      if (APPLIES && (QUEUE.size() != 0) && (CREDITS != '0)) begin          \
        FLIT    <= QUEUE.pop_front();                                       \
        FLITV   <= 1'b1;                                                    \
        CREDITS <= CREDITS - CREDIT_W'(1) + CREDIT_W'(LCRDV);               \
        SENT    <= SENT + 1;                                                \
      end else begin                                                        \
        CREDITS <= CREDITS + CREDIT_W'(LCRDV);                              \
      end                                                                   \
    end                                                                     \
  end

`CHI_TX_CHANNEL(reqTxQueue, reqTxCredits, reqTxSent, TX_REQ_APPLIES,
                chiPort.TXREQFLITV, chiPort.TXREQFLIT, chiPort.TXREQLCRDV)
`CHI_TX_CHANNEL(rspTxQueue, rspTxCredits, rspTxSent, TX_RSP_APPLIES,
                chiPort.TXRSPFLITV, chiPort.TXRSPFLIT, chiPort.TXRSPLCRDV)
`CHI_TX_CHANNEL(datTxQueue, datTxCredits, datTxSent, TX_DAT_APPLIES,
                chiPort.TXDATFLITV, chiPort.TXDATFLIT, chiPort.TXDATLCRDV)

`undef CHI_TX_CHANNEL

// ---------------------------------------------------------------------------
// Receive
// ---------------------------------------------------------------------------
// One credit is issued per cycle while the pool is short, matching what
// chi_link_rx does on the other side of the link. Credits are only issued once
// this side has acknowledged activation [SPEC:IHI0050H B14.5.1].
logic [REQ_FLIT_W-1:0] reqRxQueue [$];
logic [RSP_FLIT_W-1:0] rspRxQueue [$];
logic [SNP_FLIT_W-1:0] snpRxQueue [$];
logic [DAT_FLIT_W-1:0] datRxQueue [$];

logic [CREDIT_W-1:0] reqRxGranted;
logic [CREDIT_W-1:0] rspRxGranted;
logic [CREDIT_W-1:0] snpRxGranted;
logic [CREDIT_W-1:0] datRxGranted;

bit reqRxLcrd;
bit rspRxLcrd;
bit snpRxLcrd;
bit datRxLcrd;

always_comb begin
  reqRxLcrd = RX_REQ_APPLIES && rxLinkAck && (reqRxGranted < CREDIT_W'(LCRD_DEPTH));
  rspRxLcrd = RX_RSP_APPLIES && rxLinkAck && (rspRxGranted < CREDIT_W'(LCRD_DEPTH));
  snpRxLcrd = RX_SNP_APPLIES && rxLinkAck && (snpRxGranted < CREDIT_W'(LCRD_DEPTH));
  datRxLcrd = RX_DAT_APPLIES && rxLinkAck && (datRxGranted < CREDIT_W'(LCRD_DEPTH));

  chiPort.RXREQLCRDV = reqRxLcrd;
  chiPort.RXRSPLCRDV = rspRxLcrd;
  chiPort.RXSNPLCRDV = snpRxLcrd;
  chiPort.RXDATLCRDV = datRxLcrd;
end

// An L-Credit return carries no message and must not be handed upstream. It is
// identified by a zero Opcode field, which is exactly what the fabric's own
// receiver looks for [SPEC:IHI0050H B13.11, link/chi_link_rx.sv].
localparam logic [REQ_FLIT_W-1:0] REQ_OPCODE_MASK = reqOpcodeMask(CHI_CFG);
localparam logic [RSP_FLIT_W-1:0] RSP_OPCODE_MASK = rspOpcodeMask(CHI_CFG);
localparam logic [SNP_FLIT_W-1:0] SNP_OPCODE_MASK = snpOpcodeMask(CHI_CFG);
localparam logic [DAT_FLIT_W-1:0] DAT_OPCODE_MASK = datOpcodeMask(CHI_CFG);

`define CHI_RX_CHANNEL(QUEUE, GRANTED, LCRD, FLITV, FLIT, MASK)             \
  always_ff @(posedge chiPort.CLK) begin                                    \
    if (!chiPort.RESETn) begin                                              \
      GRANTED <= '0;                                                        \
      QUEUE.delete();                                                       \
    end else begin                                                          \
      GRANTED <= GRANTED + CREDIT_W'(LCRD) - CREDIT_W'(FLITV);              \
      if (FLITV && ((FLIT & MASK) != '0)) QUEUE.push_back(FLIT);            \
    end                                                                     \
  end

`CHI_RX_CHANNEL(reqRxQueue, reqRxGranted, reqRxLcrd, chiPort.RXREQFLITV,
                chiPort.RXREQFLIT, REQ_OPCODE_MASK)
`CHI_RX_CHANNEL(rspRxQueue, rspRxGranted, rspRxLcrd, chiPort.RXRSPFLITV,
                chiPort.RXRSPFLIT, RSP_OPCODE_MASK)
`CHI_RX_CHANNEL(snpRxQueue, snpRxGranted, snpRxLcrd, chiPort.RXSNPFLITV,
                chiPort.RXSNPFLIT, SNP_OPCODE_MASK)
`CHI_RX_CHANNEL(datRxQueue, datRxGranted, datRxLcrd, chiPort.RXDATFLITV,
                chiPort.RXDATFLIT, DAT_OPCODE_MASK)

`undef CHI_RX_CHANNEL

// ---------------------------------------------------------------------------
// Parity
// ---------------------------------------------------------------------------
// Byte parity over the flit, computed the same way the fabric's transmitter
// computes it [SPEC:IHI0050H B9.3.3, link/chi_link_tx.sv]. With parityEn clear
// the check buses are unused and held low.
function automatic logic [(REQ_FLIT_W+7)/8-1:0] reqParity(
    input logic [REQ_FLIT_W-1:0] flit);
  logic [(REQ_FLIT_W+7)/8-1:0] value;
  value = '0;
  if (CHI_CFG.parityEn)
    for (int unsigned b = 0; b < REQ_FLIT_W; b++)
      value[b/8] = value[b/8] ^ flit[b];
  return value;
endfunction

function automatic logic [(RSP_FLIT_W+7)/8-1:0] rspParity(
    input logic [RSP_FLIT_W-1:0] flit);
  logic [(RSP_FLIT_W+7)/8-1:0] value;
  value = '0;
  if (CHI_CFG.parityEn)
    for (int unsigned b = 0; b < RSP_FLIT_W; b++)
      value[b/8] = value[b/8] ^ flit[b];
  return value;
endfunction

function automatic logic [(DAT_FLIT_W+7)/8-1:0] datParity(
    input logic [DAT_FLIT_W-1:0] flit);
  logic [(DAT_FLIT_W+7)/8-1:0] value;
  value = '0;
  if (CHI_CFG.parityEn)
    for (int unsigned b = 0; b < DAT_FLIT_W; b++)
      value[b/8] = value[b/8] ^ flit[b];
  return value;
endfunction

// Only the per-flit parity buses belong to the node. The single-bit check pins
// are all driven by the fabric's link port, so they are left alone here.
always_comb begin
  chiPort.TXREQFLITCHK = reqParity(chiPort.TXREQFLIT);
  chiPort.TXRSPFLITCHK = rspParity(chiPort.TXRSPFLIT);
  chiPort.TXDATFLITCHK = datParity(chiPort.TXDATFLIT);
  chiPort.TXSNPFLITCHK = '0;
end

// ---------------------------------------------------------------------------
// Link layer services offered to the protocol layer
// ---------------------------------------------------------------------------
task automatic waitOutOfReset();
  if (!chiPort.RESETn) @(posedge chiPort.RESETn);
  @(posedge chiPort.CLK);
endtask

task automatic activateLink();
  linkEnable = 1'b1;
endtask

task automatic setSysCoReq(input bit value);
  sysCoReqDrive = value;
endtask

// System coherency entry. A fully coherent Requester asserts SYSCOREQ and may
// not issue coherent requests until SYSCOACK is returned [SPEC:IHI0050H B14.7].
task automatic enterSystemCoherency();
  sysCoReqDrive = 1'b1;
  while (!chiPort.SYSCOACK) @(posedge chiPort.CLK);
endtask

// Both directions in RUN. Waiting on the transmit direction alone would let a
// Requester issue a request before it could receive the response to it.
task automatic waitLinkRun();
  while ((txLinkState != CHI_LINK_RUN) || (rxLinkState != CHI_LINK_RUN))
    @(posedge chiPort.CLK);
endtask

// Credits are only granted from RUN, so waiting for the first credit on each
// applicable transmit channel proves the far side is ready to be sent to.
task automatic waitTxCreditsReady();
  while ((TX_REQ_APPLIES && (reqTxCredits == '0))
      || (TX_RSP_APPLIES && (rspTxCredits == '0))
      || (TX_DAT_APPLIES && (datTxCredits == '0)))
    @(posedge chiPort.CLK);
endtask

function automatic bit linkIsRun();
  return (txLinkState == CHI_LINK_RUN) && (rxLinkState == CHI_LINK_RUN);
endfunction

// Send tasks return once the flit has been presented on the pins, not merely
// queued, so a caller that needs ordering between channels gets it.
task automatic sendReqFlit(input logic [REQ_FLIT_W-1:0] flit);
  int unsigned target;
  target = reqTxSent + reqTxQueue.size() + 1;
  reqTxQueue.push_back(flit);
  while (reqTxSent < target) @(posedge chiPort.CLK);
endtask

task automatic sendRspFlit(input logic [RSP_FLIT_W-1:0] flit);
  int unsigned target;
  target = rspTxSent + rspTxQueue.size() + 1;
  rspTxQueue.push_back(flit);
  while (rspTxSent < target) @(posedge chiPort.CLK);
endtask

task automatic sendDatFlit(input logic [DAT_FLIT_W-1:0] flit);
  int unsigned target;
  target = datTxSent + datTxQueue.size() + 1;
  datTxQueue.push_back(flit);
  while (datTxSent < target) @(posedge chiPort.CLK);
endtask

// Blocking receives. Each queue has exactly one consumer in the protocol layer
// above, so a pop cannot race another reader. These poll on the clock rather
// than waiting on the queue itself, because a queue is a variable and not
// every simulator re-evaluates a wait expression when one is pushed to.
task automatic getReqFlit(output logic [REQ_FLIT_W-1:0] flit);
  while (reqRxQueue.size() == 0) @(posedge chiPort.CLK);
  flit = reqRxQueue.pop_front();
endtask

task automatic getRspFlit(output logic [RSP_FLIT_W-1:0] flit);
  while (rspRxQueue.size() == 0) @(posedge chiPort.CLK);
  flit = rspRxQueue.pop_front();
endtask

task automatic getSnpFlit(output logic [SNP_FLIT_W-1:0] flit);
  while (snpRxQueue.size() == 0) @(posedge chiPort.CLK);
  flit = snpRxQueue.pop_front();
endtask

task automatic getDatFlit(output logic [DAT_FLIT_W-1:0] flit);
  while (datRxQueue.size() == 0) @(posedge chiPort.CLK);
  flit = datRxQueue.pop_front();
endtask
