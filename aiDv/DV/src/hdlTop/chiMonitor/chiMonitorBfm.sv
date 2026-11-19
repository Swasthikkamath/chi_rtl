// Passive pin observer for one CHI port.
//
// One implementation serves both roles. A monitor only reads pins, and the
// pins of a Requester port and a Subordinate port are the same interface; what
// differs is which channels ever carry a flit, and an idle channel simply
// produces nothing. Splitting this per role would be two copies of identical
// sampling code.
//
// Nothing here is shared with the driver BFM. The monitor reconstructs what
// happened from the wires alone, so a driver that builds a malformed flit is
// still reported as what it actually sent rather than as what it meant to
// send.
interface chiMonitorBfm (
  chi_if chiPort
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chiGlobalsPkg::*;

  int unsigned     agentId   = 0;
  chi_node_class_e nodeClass = NODE_RNF;

  function automatic void configure(input int unsigned id,
                                    input chi_node_class_e cls);
    agentId   = id;
    nodeClass = cls;
  endfunction

  localparam logic [REQ_FLIT_W-1:0] REQ_OPCODE_MASK = reqOpcodeMask(CHI_CFG);
  localparam logic [RSP_FLIT_W-1:0] RSP_OPCODE_MASK = rspOpcodeMask(CHI_CFG);
  localparam logic [SNP_FLIT_W-1:0] SNP_OPCODE_MASK = snpOpcodeMask(CHI_CFG);
  localparam logic [DAT_FLIT_W-1:0] DAT_OPCODE_MASK = datOpcodeMask(CHI_CFG);

  chiSampledFlitS flitQueue [$];
  chiLinkEventS   eventQueue [$];

  // -------------------------------------------------------------------------
  // Link state
  // -------------------------------------------------------------------------
  // The spec defines the four link states directly as the two handshake
  // signals, so they are decoded rather than tracked with a second FSM
  // [SPEC:IHI0050H B14.5.1 Table B14.1].
  function automatic chiLinkStateE decodeLinkState(input bit req, input bit ack);
    case ({req, ack})
      2'b00:   return CHI_LINK_STOP;
      2'b10:   return CHI_LINK_ACTIVATE;
      2'b11:   return CHI_LINK_RUN;
      default: return CHI_LINK_DEACTIVATE;
    endcase
  endfunction

  chiLinkStateE txState;
  chiLinkStateE rxState;

  always_comb begin
    txState = decodeLinkState(chiPort.TXLINKACTIVEREQ, chiPort.TXLINKACTIVEACK);
    rxState = decodeLinkState(chiPort.RXLINKACTIVEREQ, chiPort.RXLINKACTIVEACK);
  end

  // Every field is named explicitly rather than defaulted, because a struct
  // holding enumerations cannot be zero-filled without violating strong
  // typing: zero is not necessarily a legal member of each enumeration.
  function automatic chiLinkEventS emptyEvent();
    chiLinkEventS event_;
    event_.kind        = CHI_LINK_EVT_STATE_CHANGE;
    event_.direction   = CHI_DIR_TX;
    event_.channel     = CHI_CHANNEL_REQ;
    event_.state       = CHI_LINK_STOP;
    event_.creditCount = 0;
    event_.sysCoReq    = 1'b0;
    event_.sysCoAck    = 1'b0;
    return event_;
  endfunction

  function automatic void pushLinkState(input chiDirectionE direction,
                                        input chiLinkStateE state);
    chiLinkEventS event_;
    event_             = emptyEvent();
    event_.kind        = CHI_LINK_EVT_STATE_CHANGE;
    event_.direction   = direction;
    event_.state       = state;
    eventQueue.push_back(event_);
  endfunction

  function automatic void pushCredit(input chiDirectionE direction,
                                     input chi_channel_e channel,
                                     input int unsigned count);
    chiLinkEventS event_;
    event_             = emptyEvent();
    event_.kind        = CHI_LINK_EVT_CREDIT_GRANT;
    event_.direction   = direction;
    event_.channel     = channel;
    event_.creditCount = count;
    eventQueue.push_back(event_);
  endfunction

  function automatic void pushSysCo();
    chiLinkEventS event_;
    event_          = emptyEvent();
    event_.kind     = CHI_LINK_EVT_SYSCO;
    event_.sysCoReq = chiPort.SYSCOREQ;
    event_.sysCoAck = chiPort.SYSCOACK;
    eventQueue.push_back(event_);
  endfunction

  chiLinkStateE txStatePrev;
  chiLinkStateE rxStatePrev;
  bit           sysCoReqPrev;
  bit           sysCoAckPrev;

  // Credits currently held, per channel and direction: one is gained when the
  // receiver grants it and spent when a flit is presented. This balance is the
  // quantity the channel depth bounds, not the running total of grants, which
  // rises without limit as credits are spent and replaced
  // [SPEC:IHI0050H B14.6.3].
  //
  // Every valid flit spends a credit, including an L-Credit return, which is
  // why the decrement does not filter on opcode the way the flit stream does
  // [link/chi_link_rx.sv peerCredits].
  int unsigned txCreditBalance [4];
  int unsigned rxCreditBalance [4];

  function automatic int unsigned creditDelta(input bit granted,
                                              input bit spent,
                                              input int unsigned balance);
    int unsigned value;
    value = balance;
    if (granted) value = value + 1;
    if (spent && (value > 0)) value = value - 1;
    return value;
  endfunction

  always_ff @(posedge chiPort.CLK) begin
    if (!chiPort.RESETn) begin
      txStatePrev  <= CHI_LINK_STOP;
      rxStatePrev  <= CHI_LINK_STOP;
      sysCoReqPrev <= 1'b0;
      sysCoAckPrev <= 1'b0;
      for (int unsigned c = 0; c < 4; c++) begin
        txCreditBalance[c] <= 0;
        rxCreditBalance[c] <= 0;
      end
    end else begin
      if (txState != txStatePrev) begin
        pushLinkState(CHI_DIR_TX, txState);
        txStatePrev <= txState;
      end
      if (rxState != rxStatePrev) begin
        pushLinkState(CHI_DIR_RX, rxState);
        rxStatePrev <= rxState;
      end

      if ((chiPort.SYSCOREQ != sysCoReqPrev)
          || (chiPort.SYSCOACK != sysCoAckPrev)) begin
        pushSysCo();
        sysCoReqPrev <= chiPort.SYSCOREQ;
        sysCoAckPrev <= chiPort.SYSCOACK;
      end

      // A credit on a TX channel is one the fabric granted to this node; a
      // credit on an RX channel is one this node granted to the fabric. Both
      // are reported only when the balance moves, which is on a grant: a flit
      // being sent is already visible as a flit, and reporting that twice
      // would double the traffic the scoreboard has to sift.
      if (chiPort.TXREQLCRDV || chiPort.TXREQFLITV) begin
        txCreditBalance[CHI_CHANNEL_REQ] <= creditDelta(
            chiPort.TXREQLCRDV, chiPort.TXREQFLITV,
            txCreditBalance[CHI_CHANNEL_REQ]);
        if (chiPort.TXREQLCRDV)
          pushCredit(CHI_DIR_TX, CHI_CHANNEL_REQ,
                     creditDelta(chiPort.TXREQLCRDV, chiPort.TXREQFLITV,
                                 txCreditBalance[CHI_CHANNEL_REQ]));
      end
      if (chiPort.TXRSPLCRDV || chiPort.TXRSPFLITV) begin
        txCreditBalance[CHI_CHANNEL_RSP] <= creditDelta(
            chiPort.TXRSPLCRDV, chiPort.TXRSPFLITV,
            txCreditBalance[CHI_CHANNEL_RSP]);
        if (chiPort.TXRSPLCRDV)
          pushCredit(CHI_DIR_TX, CHI_CHANNEL_RSP,
                     creditDelta(chiPort.TXRSPLCRDV, chiPort.TXRSPFLITV,
                                 txCreditBalance[CHI_CHANNEL_RSP]));
      end
      if (chiPort.TXDATLCRDV || chiPort.TXDATFLITV) begin
        txCreditBalance[CHI_CHANNEL_DAT] <= creditDelta(
            chiPort.TXDATLCRDV, chiPort.TXDATFLITV,
            txCreditBalance[CHI_CHANNEL_DAT]);
        if (chiPort.TXDATLCRDV)
          pushCredit(CHI_DIR_TX, CHI_CHANNEL_DAT,
                     creditDelta(chiPort.TXDATLCRDV, chiPort.TXDATFLITV,
                                 txCreditBalance[CHI_CHANNEL_DAT]));
      end
      if (chiPort.RXREQLCRDV || chiPort.RXREQFLITV) begin
        rxCreditBalance[CHI_CHANNEL_REQ] <= creditDelta(
            chiPort.RXREQLCRDV, chiPort.RXREQFLITV,
            rxCreditBalance[CHI_CHANNEL_REQ]);
        if (chiPort.RXREQLCRDV)
          pushCredit(CHI_DIR_RX, CHI_CHANNEL_REQ,
                     creditDelta(chiPort.RXREQLCRDV, chiPort.RXREQFLITV,
                                 rxCreditBalance[CHI_CHANNEL_REQ]));
      end
      if (chiPort.RXRSPLCRDV || chiPort.RXRSPFLITV) begin
        rxCreditBalance[CHI_CHANNEL_RSP] <= creditDelta(
            chiPort.RXRSPLCRDV, chiPort.RXRSPFLITV,
            rxCreditBalance[CHI_CHANNEL_RSP]);
        if (chiPort.RXRSPLCRDV)
          pushCredit(CHI_DIR_RX, CHI_CHANNEL_RSP,
                     creditDelta(chiPort.RXRSPLCRDV, chiPort.RXRSPFLITV,
                                 rxCreditBalance[CHI_CHANNEL_RSP]));
      end
      if (chiPort.RXSNPLCRDV || chiPort.RXSNPFLITV) begin
        rxCreditBalance[CHI_CHANNEL_SNP] <= creditDelta(
            chiPort.RXSNPLCRDV, chiPort.RXSNPFLITV,
            rxCreditBalance[CHI_CHANNEL_SNP]);
        if (chiPort.RXSNPLCRDV)
          pushCredit(CHI_DIR_RX, CHI_CHANNEL_SNP,
                     creditDelta(chiPort.RXSNPLCRDV, chiPort.RXSNPFLITV,
                                 rxCreditBalance[CHI_CHANNEL_SNP]));
      end
      if (chiPort.RXDATLCRDV || chiPort.RXDATFLITV) begin
        rxCreditBalance[CHI_CHANNEL_DAT] <= creditDelta(
            chiPort.RXDATLCRDV, chiPort.RXDATFLITV,
            rxCreditBalance[CHI_CHANNEL_DAT]);
        if (chiPort.RXDATLCRDV)
          pushCredit(CHI_DIR_RX, CHI_CHANNEL_DAT,
                     creditDelta(chiPort.RXDATLCRDV, chiPort.RXDATFLITV,
                                 rxCreditBalance[CHI_CHANNEL_DAT]));
      end
    end
  end

  // -------------------------------------------------------------------------
  // Flits
  // -------------------------------------------------------------------------
  // L-Credit returns are filtered out. They carry no message and are link
  // mechanics rather than protocol content [SPEC:IHI0050H B13.11]; the credit
  // accounting above already reports them.
  function automatic void pushFlit(input chiDirectionE direction,
                                   input chi_channel_e channel,
                                   input logic [CHI_WIDEST_FLIT_W-1:0] flit);
    chiSampledFlitS sample;
    sample.direction = direction;
    sample.channel   = channel;
    sample.flit      = flit;
    flitQueue.push_back(sample);
  endfunction

  always_ff @(posedge chiPort.CLK) begin
    if (chiPort.RESETn) begin
      // Node to interconnect.
      if (chiPort.TXREQFLITV && ((chiPort.TXREQFLIT & REQ_OPCODE_MASK) != '0))
        pushFlit(CHI_DIR_TX, CHI_CHANNEL_REQ,
                 CHI_WIDEST_FLIT_W'(chiPort.TXREQFLIT));
      if (chiPort.TXRSPFLITV && ((chiPort.TXRSPFLIT & RSP_OPCODE_MASK) != '0))
        pushFlit(CHI_DIR_TX, CHI_CHANNEL_RSP,
                 CHI_WIDEST_FLIT_W'(chiPort.TXRSPFLIT));
      if (chiPort.TXDATFLITV && ((chiPort.TXDATFLIT & DAT_OPCODE_MASK) != '0))
        pushFlit(CHI_DIR_TX, CHI_CHANNEL_DAT,
                 CHI_WIDEST_FLIT_W'(chiPort.TXDATFLIT));

      // Interconnect to node.
      if (chiPort.RXREQFLITV && ((chiPort.RXREQFLIT & REQ_OPCODE_MASK) != '0))
        pushFlit(CHI_DIR_RX, CHI_CHANNEL_REQ,
                 CHI_WIDEST_FLIT_W'(chiPort.RXREQFLIT));
      if (chiPort.RXRSPFLITV && ((chiPort.RXRSPFLIT & RSP_OPCODE_MASK) != '0))
        pushFlit(CHI_DIR_RX, CHI_CHANNEL_RSP,
                 CHI_WIDEST_FLIT_W'(chiPort.RXRSPFLIT));
      if (chiPort.RXSNPFLITV && ((chiPort.RXSNPFLIT & SNP_OPCODE_MASK) != '0))
        pushFlit(CHI_DIR_RX, CHI_CHANNEL_SNP,
                 CHI_WIDEST_FLIT_W'(chiPort.RXSNPFLIT));
      if (chiPort.RXDATFLITV && ((chiPort.RXDATFLIT & DAT_OPCODE_MASK) != '0))
        pushFlit(CHI_DIR_RX, CHI_CHANNEL_DAT,
                 CHI_WIDEST_FLIT_W'(chiPort.RXDATFLIT));
    end
  end

  // -------------------------------------------------------------------------
  // Services offered to the monitor proxy
  // -------------------------------------------------------------------------
  task automatic getFlit(output chiSampledFlitS sample);
    while (flitQueue.size() == 0) @(posedge chiPort.CLK);
    sample = flitQueue.pop_front();
  endtask

  task automatic getLinkEvent(output chiLinkEventS event_);
    while (eventQueue.size() == 0) @(posedge chiPort.CLK);
    event_ = eventQueue.pop_front();
  endtask
endinterface
