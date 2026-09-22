//==============================================================================
// chiMonitorBfm
//
// Why the monitor is a separate BFM from the drivers:
//
// The scoreboard has to be able to see a port that no driver owns. A passive
// agent, a port whose driver is disabled, and the sentinel port of a
// configured-out node class all need observation without stimulus, so the
// monitor cannot be a mode of the driver BFM. It also has to see what the
// drivers cannot: linkUp, linkParityError and linkCreditError are top-level
// DUT outputs indexed by node ordinal, not members of chi_if [TOP:ports], so
// they arrive here as ordinary interface ports from hdlTop.
//
// This interface drives nothing. Every signal is sampled, and the two error
// outputs are pulses rather than sticky bits [ASSUMPTION:17], so they are
// latched here; a proxy that polled them would miss them.
//
// Both directions of every channel are observed, including the channels a
// given port class does not use, so that traffic appearing where it should not
// is a finding the scoreboard can act on rather than something nobody watches.
//==============================================================================

interface chiMonitorBfm (
    input logic CLK,
    input logic RESETn,

    input logic TXLINKACTIVEREQ,
    input logic TXLINKACTIVEACK,
    input logic RXLINKACTIVEREQ,
    input logic RXLINKACTIVEACK,
    input logic TXSACTIVE,
    input logic RXSACTIVE,
    input logic SYSCOREQ,
    input logic SYSCOACK,

    input logic TXREQFLITV,
    input logic [chiGlobalsPkg::REQ_FLIT_W-1:0] TXREQFLIT,
    input logic TXREQLCRDV,
    input logic TXRSPFLITV,
    input logic [chiGlobalsPkg::RSP_FLIT_W-1:0] TXRSPFLIT,
    input logic TXRSPLCRDV,
    input logic TXDATFLITV,
    input logic [chiGlobalsPkg::DAT_FLIT_W-1:0] TXDATFLIT,
    input logic TXDATLCRDV,

    input logic RXREQFLITV,
    input logic [chiGlobalsPkg::REQ_FLIT_W-1:0] RXREQFLIT,
    input logic RXREQLCRDV,
    input logic RXRSPFLITV,
    input logic [chiGlobalsPkg::RSP_FLIT_W-1:0] RXRSPFLIT,
    input logic RXRSPLCRDV,
    input logic RXDATFLITV,
    input logic [chiGlobalsPkg::DAT_FLIT_W-1:0] RXDATFLIT,
    input logic RXDATLCRDV,
    input logic RXSNPFLITV,
    input logic [chiGlobalsPkg::SNP_FLIT_W-1:0] RXSNPFLIT,
    input logic RXSNPLCRDV,

    // Per-node status, which is a top-level DUT output rather than a chi_if
    // member [TOP:linkUp, linkParityError, linkCreditError]. The two error
    // outputs are pulses, so they are latched below [ASSUMPTION:17].
    input logic linkUp,
    input logic linkParityError,
    input logic linkCreditError
);

  import chiGlobalsPkg::*;

  // Identity is configured at time 0 rather than parameterized, for the same
  // reason as the driver BFMs: one `virtual chiMonitorBfm` type has to be able
  // to hold a handle to any port's monitor.
  int unsigned                 nodeOrdinal;
  chiGlobalsPkg::chiNodeClassE nodeClass;
  bit                          isRequesterPort;
  bit                          configured;

  task automatic configure(input int unsigned ordinal,
                           input chiGlobalsPkg::chiNodeClassE portClass);
    nodeOrdinal     = ordinal;
    nodeClass       = portClass;
    isRequesterPort = chiGlobalsPkg::nodeClassIsRequester(portClass);
    configured      = 1'b1;
  endtask

  task automatic waitConfigured();
    wait (configured == 1'b1);
  endtask

  chiGlobalsPkg::chiFlitSampleT flitQueue [$];
  chiGlobalsPkg::chiLinkSampleT linkQueue [$];

  // Latched error pulses, cleared only when the proxy takes them.
  bit parityErrorLatched;
  bit creditErrorLatched;
  int unsigned parityErrorCount;
  int unsigned creditErrorCount;

  // Credit events, counted per channel and direction so that the link
  // reference model can compare what was advertised against what was used
  // without the drivers telling it anything.
  int unsigned txReqCreditCount;
  int unsigned txRspCreditCount;
  int unsigned txDatCreditCount;
  int unsigned rxReqCreditCount;
  int unsigned rxRspCreditCount;
  int unsigned rxDatCreditCount;
  int unsigned rxSnpCreditCount;

  int unsigned flitCount;

  chiGlobalsPkg::chiLinkStateE observedTxState;
  chiGlobalsPkg::chiLinkStateE observedRxState;
  bit started;

  initial begin
    parityErrorLatched = 1'b0;
    creditErrorLatched = 1'b0;
    parityErrorCount = 0;
    creditErrorCount = 0;
    txReqCreditCount = 0;
    txRspCreditCount = 0;
    txDatCreditCount = 0;
    rxReqCreditCount = 0;
    rxRspCreditCount = 0;
    rxDatCreditCount = 0;
    rxSnpCreditCount = 0;
    flitCount = 0;
    observedTxState = chiGlobalsPkg::LINK_STOP;
    observedRxState = chiGlobalsPkg::LINK_STOP;
    started = 1'b0;
  end

  task automatic monitorStart();
    if (started) return;
    started = 1'b1;
    fork
      flitSampleLoop();
      creditSampleLoop();
      linkStatusLoop();
    join_none
  endtask

  //----------------------------------------------------------------------------
  // Flit sampling
  //
  // A flit is recorded whenever FLITV is high, with no reference to credits, so
  // that a flit sent with no credit is captured and can be reported instead of
  // vanishing.
  //----------------------------------------------------------------------------

  function automatic chiGlobalsPkg::chiFlitSampleT makeSample(
      input chiGlobalsPkg::chiChannelE channel,
      input chiGlobalsPkg::chiDirE direction,
      input chiGlobalsPkg::chiRawFlitT payload);
    chiGlobalsPkg::chiFlitSampleT sample;
    sample.nodeOrdinal = nodeOrdinal;
    sample.nodeClass   = nodeClass;
    sample.channel     = channel;
    sample.direction   = direction;
    sample.lcrdReturn  = chiGlobalsPkg::isLcrdReturn(channel, payload);
    sample.payload     = payload;
    sample.sampleTime  = $time;
    return sample;
  endfunction

  task automatic flitSampleLoop();
    forever begin
      @(posedge CLK);
      if (RESETn === 1'b1) begin
        if (TXREQFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_REQ,
                                         chiGlobalsPkg::CHI_DIR_TX,
                                         chiGlobalsPkg::chiRawFlitT'(TXREQFLIT)));
          flitCount++;
        end
        if (TXRSPFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_RSP,
                                         chiGlobalsPkg::CHI_DIR_TX,
                                         chiGlobalsPkg::chiRawFlitT'(TXRSPFLIT)));
          flitCount++;
        end
        if (TXDATFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_DAT,
                                         chiGlobalsPkg::CHI_DIR_TX,
                                         chiGlobalsPkg::chiRawFlitT'(TXDATFLIT)));
          flitCount++;
        end
        if (RXREQFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_REQ,
                                         chiGlobalsPkg::CHI_DIR_RX,
                                         chiGlobalsPkg::chiRawFlitT'(RXREQFLIT)));
          flitCount++;
        end
        if (RXRSPFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_RSP,
                                         chiGlobalsPkg::CHI_DIR_RX,
                                         chiGlobalsPkg::chiRawFlitT'(RXRSPFLIT)));
          flitCount++;
        end
        if (RXDATFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_DAT,
                                         chiGlobalsPkg::CHI_DIR_RX,
                                         chiGlobalsPkg::chiRawFlitT'(RXDATFLIT)));
          flitCount++;
        end
        if (RXSNPFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_SNP,
                                         chiGlobalsPkg::CHI_DIR_RX,
                                         chiGlobalsPkg::chiRawFlitT'(RXSNPFLIT)));
          flitCount++;
        end
      end
    end
  endtask

  task automatic creditSampleLoop();
    forever begin
      @(posedge CLK);
      if (RESETn === 1'b1) begin
        if (TXREQLCRDV === 1'b1) txReqCreditCount++;
        if (TXRSPLCRDV === 1'b1) txRspCreditCount++;
        if (TXDATLCRDV === 1'b1) txDatCreditCount++;
        if (RXREQLCRDV === 1'b1) rxReqCreditCount++;
        if (RXRSPLCRDV === 1'b1) rxRspCreditCount++;
        if (RXDATLCRDV === 1'b1) rxDatCreditCount++;
        if (RXSNPLCRDV === 1'b1) rxSnpCreditCount++;
      end
    end
  endtask

  //----------------------------------------------------------------------------
  // Link status
  //
  // The activation state is reconstructed from the two handshake pins on each
  // side, which is the only black-box view of it, and is pushed as a sample
  // whenever it changes so that the link reference model sees a transition
  // sequence rather than having to poll.
  //----------------------------------------------------------------------------

  function automatic chiGlobalsPkg::chiLinkStateE decodeLinkState(
      input logic activeReq, input logic activeAck);
    if ((activeReq === 1'b0) && (activeAck === 1'b0)) return chiGlobalsPkg::LINK_STOP;
    if ((activeReq === 1'b1) && (activeAck === 1'b0)) return chiGlobalsPkg::LINK_ACTIVATE;
    if ((activeReq === 1'b1) && (activeAck === 1'b1)) return chiGlobalsPkg::LINK_RUN;
    return chiGlobalsPkg::LINK_DEACTIVATE;
  endfunction

  task automatic linkStatusLoop();
    chiGlobalsPkg::chiLinkStateE nextTx;
    chiGlobalsPkg::chiLinkStateE nextRx;
    chiGlobalsPkg::chiLinkSampleT sample;
    bit changed;
    forever begin
      @(posedge CLK);
      if (RESETn !== 1'b1) begin
        observedTxState = chiGlobalsPkg::LINK_STOP;
        observedRxState = chiGlobalsPkg::LINK_STOP;
      end
      else begin
        nextTx = decodeLinkState(TXLINKACTIVEREQ, TXLINKACTIVEACK);
        nextRx = decodeLinkState(RXLINKACTIVEREQ, RXLINKACTIVEACK);
        changed = (nextTx != observedTxState) || (nextRx != observedRxState);
        if (linkParityError === 1'b1) begin
          parityErrorLatched = 1'b1;
          parityErrorCount++;
          changed = 1'b1;
        end
        if (linkCreditError === 1'b1) begin
          creditErrorLatched = 1'b1;
          creditErrorCount++;
          changed = 1'b1;
        end
        observedTxState = nextTx;
        observedRxState = nextRx;
        if (changed) begin
          sample.nodeOrdinal = nodeOrdinal;
          sample.linkUp      = (linkUp === 1'b1);
          sample.parityError = (linkParityError === 1'b1);
          sample.creditError = (linkCreditError === 1'b1);
          sample.txState     = observedTxState;
          sample.rxState     = observedRxState;
          sample.sysCoReq    = (SYSCOREQ === 1'b1);
          sample.sysCoAck    = (SYSCOACK === 1'b1);
          sample.sampleTime  = $time;
          linkQueue.push_back(sample);
        end
      end
    end
  endtask

  //----------------------------------------------------------------------------
  // Accessors used by chiRequesterMonitorProxy, chiSubordinateMonitorProxy and
  // the end-of-test checks
  //----------------------------------------------------------------------------

  task automatic getFlitSample(output chiGlobalsPkg::chiFlitSampleT sample);
    wait (flitQueue.size() > 0);
    sample = flitQueue.pop_front();
  endtask

  task automatic getLinkSample(output chiGlobalsPkg::chiLinkSampleT sample);
    wait (linkQueue.size() > 0);
    sample = linkQueue.pop_front();
  endtask

  // Non-blocking pops. check_phase is a function, so it cannot call the
  // waiting tasks above. Leftover samples, including L-Credit returns from
  // link deactivation, are already queued by then.
  function automatic bit tryGetFlitSample(output chiGlobalsPkg::chiFlitSampleT sample);
    if (flitQueue.size() == 0)
      return 1'b0;
    sample = flitQueue.pop_front();
    return 1'b1;
  endfunction

  function automatic bit tryGetLinkSample(output chiGlobalsPkg::chiLinkSampleT sample);
    if (linkQueue.size() == 0)
      return 1'b0;
    sample = linkQueue.pop_front();
    return 1'b1;
  endfunction

  function automatic int unsigned pendingFlitSamples();
    return flitQueue.size();
  endfunction

  function automatic int unsigned pendingLinkSamples();
    return linkQueue.size();
  endfunction

  function automatic bit sawParityError();
    return parityErrorLatched;
  endfunction

  function automatic bit sawCreditError();
    return creditErrorLatched;
  endfunction

  function automatic int unsigned parityErrors();
    return parityErrorCount;
  endfunction

  function automatic int unsigned creditErrors();
    return creditErrorCount;
  endfunction

  function automatic bit linkIsUp();
    return linkUp === 1'b1;
  endfunction

  function automatic int unsigned observedFlitCount();
    return flitCount;
  endfunction

  function automatic int unsigned ownOrdinal();
    return nodeOrdinal;
  endfunction

  function automatic chiGlobalsPkg::chiNodeClassE ownNodeClass();
    return nodeClass;
  endfunction

  function automatic chiGlobalsPkg::chiLinkStateE currentTxState();
    return observedTxState;
  endfunction

  function automatic chiGlobalsPkg::chiLinkStateE currentRxState();
    return observedRxState;
  endfunction

  // Grants seen on LCRDV. The link model compares these with the flits
  // and L-Credit returns it counted, after the link is back in STOP.
  // [ASSUMPTION:9]
  function automatic int unsigned creditGrants(
    input chiGlobalsPkg::chiChannelE channel,
    input chiGlobalsPkg::chiDirE direction
  );
    if (direction == chiGlobalsPkg::CHI_DIR_TX) begin
      case (channel)
        chiGlobalsPkg::CHI_CH_REQ: return txReqCreditCount;
        chiGlobalsPkg::CHI_CH_RSP: return txRspCreditCount;
        chiGlobalsPkg::CHI_CH_DAT: return txDatCreditCount;
        default: return 0;
      endcase
    end
    case (channel)
      chiGlobalsPkg::CHI_CH_REQ: return rxReqCreditCount;
      chiGlobalsPkg::CHI_CH_RSP: return rxRspCreditCount;
      chiGlobalsPkg::CHI_CH_DAT: return rxDatCreditCount;
      default: return rxSnpCreditCount;
    endcase
  endfunction

endinterface : chiMonitorBfm
