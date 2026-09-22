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

  // Per-cycle credit accounting, one signed ledger per in-use channel and
  // direction, indexed [channel][direction]. The ledger holds the credits
  // the transmitter is allowed to spend: it rises on LCRDV and falls on
  // FLITV, both sampled on the same posedge so there is no cross-loop race.
  // Three violations are counted per ledger:
  //   overdraw   - a flit with no credit in hand and no credit granted this
  //                same cycle. Same-cycle grant-and-use is tolerated because
  //                the sign-off DUT's exact credit timing is not yet proven;
  //                the directed credit test sends with no credit at all and
  //                is still caught [ASSUMPTION:17].
  //   ceiling    - the ledger exceeds LCRD_DEPTH, i.e. the receiver granted
  //                more outstanding credits than its receive buffer holds.
  //   outsideRun - a flit while the direction's link state is not RUN,
  //                other than an L-Credit return during DEACTIVATE, which is
  //                the legal drain [SPEC:B13.5].
  // Only channels that carry traffic on this port class are checked; a
  // tied-off channel could otherwise show phantom credits. The scoreboard
  // reads the counters at end of test and attributes them: on the RX
  // direction an overdraw is the DUT sending without a credit, on TX it is
  // this bench's own injection; the ceiling attribution is the mirror image.
  int creditAvail[4][2];
  int unsigned overdrawCount[4][2];
  int unsigned ceilingCount[4][2];
  int unsigned outsideRunCount[4][2];

  bit chkTxReq;
  bit chkTxRsp;
  bit chkTxDat;
  bit chkRxReq;
  bit chkRxRsp;
  bit chkRxDat;
  bit chkRxSnp;

  // linkUp and SACTIVE join the link sample's change detection, so a sample
  // is queued when they move even while the link states stand still.
  bit prevLinkUp;
  bit prevTxSActive;
  bit prevRxSActive;

  task automatic configure(input int unsigned ordinal,
                           input chiGlobalsPkg::chiNodeClassE portClass);
    nodeOrdinal     = ordinal;
    nodeClass       = portClass;
    isRequesterPort = chiGlobalsPkg::nodeClassIsRequester(portClass);
    configured      = 1'b1;
    // Channel usage per port class, mirroring the driver BFMs: a requester
    // transmits REQ/RSP/DAT and receives RSP/DAT/SNP; a subordinate
    // transmits RSP/DAT and receives REQ/RSP/DAT [ASSUMPTION:1].
    chkTxReq = isRequesterPort;
    chkTxRsp = 1'b1;
    chkTxDat = 1'b1;
    chkRxReq = !isRequesterPort;
    chkRxRsp = 1'b1;
    chkRxDat = 1'b1;
    chkRxSnp = isRequesterPort;
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

  // Flit events, counted per channel and direction alongside the credits.
  // Every flit on a channel, L-Credit returns included, accounts for exactly
  // one granted credit, so at a cleanly drained link the two counts are equal
  // and during RUN their difference is the credits the transmitter holds.
  int unsigned txReqFlitCount;
  int unsigned txRspFlitCount;
  int unsigned txDatFlitCount;
  int unsigned rxReqFlitCount;
  int unsigned rxRspFlitCount;
  int unsigned rxDatFlitCount;
  int unsigned rxSnpFlitCount;

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
    txReqFlitCount = 0;
    txRspFlitCount = 0;
    txDatFlitCount = 0;
    rxReqFlitCount = 0;
    rxRspFlitCount = 0;
    rxDatFlitCount = 0;
    rxSnpFlitCount = 0;
    flitCount = 0;
    for (int c = 0; c < 4; c++) begin
      for (int d = 0; d < 2; d++) begin
        creditAvail[c][d] = 0;
        overdrawCount[c][d] = 0;
        ceilingCount[c][d] = 0;
        outsideRunCount[c][d] = 0;
      end
    end
    chkTxReq = 1'b0;
    chkTxRsp = 1'b0;
    chkTxDat = 1'b0;
    chkRxReq = 1'b0;
    chkRxRsp = 1'b0;
    chkRxDat = 1'b0;
    chkRxSnp = 1'b0;
    prevLinkUp = 1'b0;
    prevTxSActive = 1'b0;
    prevRxSActive = 1'b0;
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
      creditCheckLoop();
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
          txReqFlitCount++;
        end
        if (TXRSPFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_RSP,
                                         chiGlobalsPkg::CHI_DIR_TX,
                                         chiGlobalsPkg::chiRawFlitT'(TXRSPFLIT)));
          flitCount++;
          txRspFlitCount++;
        end
        if (TXDATFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_DAT,
                                         chiGlobalsPkg::CHI_DIR_TX,
                                         chiGlobalsPkg::chiRawFlitT'(TXDATFLIT)));
          flitCount++;
          txDatFlitCount++;
        end
        if (RXREQFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_REQ,
                                         chiGlobalsPkg::CHI_DIR_RX,
                                         chiGlobalsPkg::chiRawFlitT'(RXREQFLIT)));
          flitCount++;
          rxReqFlitCount++;
        end
        if (RXRSPFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_RSP,
                                         chiGlobalsPkg::CHI_DIR_RX,
                                         chiGlobalsPkg::chiRawFlitT'(RXRSPFLIT)));
          flitCount++;
          rxRspFlitCount++;
        end
        if (RXDATFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_DAT,
                                         chiGlobalsPkg::CHI_DIR_RX,
                                         chiGlobalsPkg::chiRawFlitT'(RXDATFLIT)));
          flitCount++;
          rxDatFlitCount++;
        end
        if (RXSNPFLITV === 1'b1) begin
          flitQueue.push_back(makeSample(chiGlobalsPkg::CHI_CH_SNP,
                                         chiGlobalsPkg::CHI_DIR_RX,
                                         chiGlobalsPkg::chiRawFlitT'(RXSNPFLIT)));
          flitCount++;
          rxSnpFlitCount++;
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
  // Per-cycle credit and link-state checks
  //
  // One ledger per in-use channel and direction. A flit spends a credit that
  // was granted on an earlier cycle or this one; a credit is usable from the
  // cycle after it is granted at the latest, so tolerating same-cycle use is
  // the conservative reading [SPEC:B13.7]. The checks are deliberately kept
  // here rather than in the HVL link model: only a per-cycle sampler can see
  // a transient overdraw, because the totals reconcile again once later
  // credits arrive.
  //----------------------------------------------------------------------------

  function automatic void checkChannelLedger(
      input chiGlobalsPkg::chiChannelE channel,
      input chiGlobalsPkg::chiDirE direction,
      input logic flitV,
      input logic lcrdV,
      input chiGlobalsPkg::chiRawFlitT payload,
      input chiGlobalsPkg::chiLinkStateE state);
    int ci;
    int di;
    bit flit;
    bit lcrd;
    ci = int'(channel);
    di = int'(direction);
    flit = (flitV === 1'b1);
    lcrd = (lcrdV === 1'b1);
    if (flit) begin
      if ((creditAvail[ci][di] <= 0) && !lcrd)
        overdrawCount[ci][di]++;
      if ((state != chiGlobalsPkg::LINK_RUN) &&
          !((state == chiGlobalsPkg::LINK_DEACTIVATE) &&
            chiGlobalsPkg::isLcrdReturn(channel, payload)))
        outsideRunCount[ci][di]++;
    end
    creditAvail[ci][di] = creditAvail[ci][di] + (lcrd ? 1 : 0) - (flit ? 1 : 0);
    if (creditAvail[ci][di] > int'(chiGlobalsPkg::LCRD_DEPTH))
      ceilingCount[ci][di]++;
  endfunction

  task automatic creditCheckLoop();
    chiGlobalsPkg::chiLinkStateE txSt;
    chiGlobalsPkg::chiLinkStateE rxSt;
    forever begin
      @(posedge CLK);
      if (RESETn !== 1'b1) begin
        for (int c = 0; c < 4; c++) begin
          for (int d = 0; d < 2; d++)
            creditAvail[c][d] = 0;
        end
      end
      else begin
        txSt = decodeLinkState(TXLINKACTIVEREQ, TXLINKACTIVEACK);
        rxSt = decodeLinkState(RXLINKACTIVEREQ, RXLINKACTIVEACK);
        if (chkTxReq)
          checkChannelLedger(chiGlobalsPkg::CHI_CH_REQ, chiGlobalsPkg::CHI_DIR_TX,
            TXREQFLITV, TXREQLCRDV, chiGlobalsPkg::chiRawFlitT'(TXREQFLIT), txSt);
        if (chkTxRsp)
          checkChannelLedger(chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_TX,
            TXRSPFLITV, TXRSPLCRDV, chiGlobalsPkg::chiRawFlitT'(TXRSPFLIT), txSt);
        if (chkTxDat)
          checkChannelLedger(chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_TX,
            TXDATFLITV, TXDATLCRDV, chiGlobalsPkg::chiRawFlitT'(TXDATFLIT), txSt);
        if (chkRxReq)
          checkChannelLedger(chiGlobalsPkg::CHI_CH_REQ, chiGlobalsPkg::CHI_DIR_RX,
            RXREQFLITV, RXREQLCRDV, chiGlobalsPkg::chiRawFlitT'(RXREQFLIT), rxSt);
        if (chkRxRsp)
          checkChannelLedger(chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_RX,
            RXRSPFLITV, RXRSPLCRDV, chiGlobalsPkg::chiRawFlitT'(RXRSPFLIT), rxSt);
        if (chkRxDat)
          checkChannelLedger(chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_RX,
            RXDATFLITV, RXDATLCRDV, chiGlobalsPkg::chiRawFlitT'(RXDATFLIT), rxSt);
        if (chkRxSnp)
          checkChannelLedger(chiGlobalsPkg::CHI_CH_SNP, chiGlobalsPkg::CHI_DIR_RX,
            RXSNPFLITV, RXSNPLCRDV, chiGlobalsPkg::chiRawFlitT'(RXSNPFLIT), rxSt);
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
    bit curLinkUp;
    bit curTxSActive;
    bit curRxSActive;
    forever begin
      @(posedge CLK);
      if (RESETn !== 1'b1) begin
        observedTxState = chiGlobalsPkg::LINK_STOP;
        observedRxState = chiGlobalsPkg::LINK_STOP;
        prevLinkUp = 1'b0;
        prevTxSActive = 1'b0;
        prevRxSActive = 1'b0;
      end
      else begin
        nextTx = decodeLinkState(TXLINKACTIVEREQ, TXLINKACTIVEACK);
        nextRx = decodeLinkState(RXLINKACTIVEREQ, RXLINKACTIVEACK);
        curLinkUp = (linkUp === 1'b1);
        curTxSActive = (TXSACTIVE === 1'b1);
        curRxSActive = (RXSACTIVE === 1'b1);
        changed = (nextTx != observedTxState) || (nextRx != observedRxState) ||
          (curLinkUp != prevLinkUp) || (curTxSActive != prevTxSActive) ||
          (curRxSActive != prevRxSActive);
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
        prevLinkUp = curLinkUp;
        prevTxSActive = curTxSActive;
        prevRxSActive = curRxSActive;
        if (changed) begin
          sample.nodeOrdinal = nodeOrdinal;
          sample.linkUp      = curLinkUp;
          sample.parityError = (linkParityError === 1'b1);
          sample.creditError = (linkCreditError === 1'b1);
          sample.txState     = observedTxState;
          sample.rxState     = observedRxState;
          sample.sysCoReq    = (SYSCOREQ === 1'b1);
          sample.sysCoAck    = (SYSCOACK === 1'b1);
          sample.txSActive   = curTxSActive;
          sample.rxSActive   = curRxSActive;
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

  // Non-blocking drains for the scoreboard's extract_phase. When run_phase
  // ends, the proxies' sampling loops are killed wherever they happen to be,
  // so the last flits of the test can still be sitting in these queues. A
  // sample is either popped by a proxy (and forwarded on its analysis port)
  // or left here for the drain, never both, so the two paths cannot
  // double-count.
  function automatic bit tryFlitSample(output chiGlobalsPkg::chiFlitSampleT sample);
    if (flitQueue.size() == 0)
      return 1'b0;
    sample = flitQueue.pop_front();
    return 1'b1;
  endfunction

  function automatic bit tryLinkSample(output chiGlobalsPkg::chiLinkSampleT sample);
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

  // Per-channel counters for the end-of-test credit reconciliation. The
  // credit count is the number of LCRDV pulses observed on that channel's
  // credit pin; the flit count is every flit observed on the channel,
  // L-Credit returns included.
  function automatic int unsigned creditCount(
      input chiGlobalsPkg::chiChannelE channel,
      input chiGlobalsPkg::chiDirE direction);
    if (direction == chiGlobalsPkg::CHI_DIR_TX) begin
      case (channel)
        chiGlobalsPkg::CHI_CH_REQ: return txReqCreditCount;
        chiGlobalsPkg::CHI_CH_RSP: return txRspCreditCount;
        chiGlobalsPkg::CHI_CH_DAT: return txDatCreditCount;
        default:                   return 0;
      endcase
    end
    case (channel)
      chiGlobalsPkg::CHI_CH_REQ: return rxReqCreditCount;
      chiGlobalsPkg::CHI_CH_RSP: return rxRspCreditCount;
      chiGlobalsPkg::CHI_CH_SNP: return rxSnpCreditCount;
      default:                   return rxDatCreditCount;
    endcase
  endfunction

  function automatic int unsigned channelFlitCount(
      input chiGlobalsPkg::chiChannelE channel,
      input chiGlobalsPkg::chiDirE direction);
    if (direction == chiGlobalsPkg::CHI_DIR_TX) begin
      case (channel)
        chiGlobalsPkg::CHI_CH_REQ: return txReqFlitCount;
        chiGlobalsPkg::CHI_CH_RSP: return txRspFlitCount;
        chiGlobalsPkg::CHI_CH_DAT: return txDatFlitCount;
        default:                   return 0;
      endcase
    end
    case (channel)
      chiGlobalsPkg::CHI_CH_REQ: return rxReqFlitCount;
      chiGlobalsPkg::CHI_CH_RSP: return rxRspFlitCount;
      chiGlobalsPkg::CHI_CH_SNP: return rxSnpFlitCount;
      default:                   return rxDatFlitCount;
    endcase
  endfunction

  function automatic int unsigned ownOrdinal();
    return nodeOrdinal;
  endfunction

  function automatic chiGlobalsPkg::chiNodeClassE ownNodeClass();
    return nodeClass;
  endfunction

  // Per-cycle check counters, indexed by channel and direction. The
  // scoreboard reads them at end of test and decides what each one means
  // for this test's expectations.
  function automatic int unsigned overdrawErrors(
      input chiGlobalsPkg::chiChannelE channel,
      input chiGlobalsPkg::chiDirE direction);
    return overdrawCount[int'(channel)][int'(direction)];
  endfunction

  function automatic int unsigned ceilingErrors(
      input chiGlobalsPkg::chiChannelE channel,
      input chiGlobalsPkg::chiDirE direction);
    return ceilingCount[int'(channel)][int'(direction)];
  endfunction

  function automatic int unsigned outsideRunErrors(
      input chiGlobalsPkg::chiChannelE channel,
      input chiGlobalsPkg::chiDirE direction);
    return outsideRunCount[int'(channel)][int'(direction)];
  endfunction

  // The outstanding credits the transmitter still holds, per the ledger.
  // Exposed so the end-of-test reconciliation can cross-check it against
  // the credit and flit totals.
  function automatic int creditBalance(
      input chiGlobalsPkg::chiChannelE channel,
      input chiGlobalsPkg::chiDirE direction);
    return creditAvail[int'(channel)][int'(direction)];
  endfunction

endinterface : chiMonitorBfm
