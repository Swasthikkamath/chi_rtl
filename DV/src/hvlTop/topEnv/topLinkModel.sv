//==============================================================================
// topLinkModel
//
// The link-layer reference model. It is fed the change-driven link sample
// stream from every monitor BFM and, at end of test, the per-cycle credit
// ledgers the monitors keep. Between the two it checks everything the link
// layer owes the boundary:
//
//   - the four-state activation machine on each direction of each port takes
//     only legal steps [SPEC:B13.5];
//   - linkUp reflects the node-to-fabric direction reaching RUN, and only
//     that (finding F-3), so it may not rise before the link has ever run
//     and must agree with the final link state;
//   - both SACTIVE pins read constant 1 out of reset, because the DUT drives
//     them to resetn (finding F-2);
//   - SYSCOACK is the combinational copy of SYSCOREQ [ASSUMPTION:4];
//   - credits are never overspent, never over-granted past LCRD_DEPTH, and
//     flits never move outside RUN except the DEACTIVATE credit drain;
//   - at a cleanly drained link every granted credit was returned, so flits
//     and credits balance exactly;
//   - the linkParityError / linkCreditError outputs fire exactly when the
//     test's injection knobs say they should [ASSUMPTION:17].
//
// The per-cycle violation counters live in the monitor BFM because only a
// per-cycle sampler sees a transient overdraw; this model reads them at the
// end and attributes them. On the RX direction the DUT is the transmitter,
// so an overdraw there is a DUT bug; on TX it is this bench's own directed
// injection, forgiven only when the test asked for it. The ceiling check is
// the mirror image.
//==============================================================================

class topLinkModel extends uvm_component;

  topEnvConfig cfg;

  // Monitor BFM handles, one per external port ordinal, fetched in
  // build_phase so check_phase can reconcile the credit ledgers.
  virtual chiMonitorBfm monBfm[int unsigned];

  // Per-node observed link state, updated from the sample stream.
  chiLinkStateE lastTxState[int unsigned];
  chiLinkStateE lastRxState[int unsigned];
  bit           sawSample[int unsigned];
  bit           everTxRun[int unsigned];
  bit           sawLinkUp[int unsigned];
  bit           lastLinkUp[int unsigned];

  int unsigned linkSampleCount;
  int unsigned transitionErrorCount;
  int unsigned linkUpErrorCount;
  int unsigned sactiveErrorCount;
  int unsigned syscoErrorCount;

  `uvm_component_utils(topLinkModel)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    linkSampleCount = 0;
    transitionErrorCount = 0;
    linkUpErrorCount = 0;
    sactiveErrorCount = 0;
    syscoErrorCount = 0;
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    for (int unsigned ord = 0; ord < chiGlobalsPkg::OFF_HNF; ord++) begin
      if (!uvm_config_db#(virtual chiMonitorBfm)::get(this, "",
            chiGlobalsPkg::monitorBfmKey(ord), monBfm[ord]))
        `uvm_fatal("LINK/BFM", $sformatf(
          "no monitor BFM published for node ordinal %0d", ord))
    end
  endfunction

  // Legal and tolerated steps of the four-state machine. Tolerated but not
  // forward steps: ACTIVATE->STOP (the transmitter abandons an activation)
  // and DEACTIVATE->RUN (it changes its mind before the drain completes).
  // Anything that skips a state or moves both handshake pins at once is a
  // violation.
  function automatic bit transitionOk(input chiLinkStateE from,
                                      input chiLinkStateE to);
    if (from == to)
      return 1'b1;
    case (from)
      chiGlobalsPkg::LINK_STOP:
        return (to == chiGlobalsPkg::LINK_ACTIVATE);
      chiGlobalsPkg::LINK_ACTIVATE:
        return (to == chiGlobalsPkg::LINK_RUN) || (to == chiGlobalsPkg::LINK_STOP);
      chiGlobalsPkg::LINK_RUN:
        return (to == chiGlobalsPkg::LINK_DEACTIVATE);
      default:
        return (to == chiGlobalsPkg::LINK_STOP) || (to == chiGlobalsPkg::LINK_RUN);
    endcase
  endfunction

  function void noteLink(input chiGlobalsPkg::chiLinkSampleT sample);
    int unsigned node;
    chiLinkStateE prevTx;
    chiLinkStateE prevRx;
    bit wasRun;
    if (!cfg.enableLinkChecks)
      return;
    node = sample.nodeOrdinal;
    linkSampleCount++;
    prevTx = sawSample.exists(node) ? lastTxState[node] : chiGlobalsPkg::LINK_STOP;
    prevRx = sawSample.exists(node) ? lastRxState[node] : chiGlobalsPkg::LINK_STOP;

    if (!transitionOk(prevTx, sample.txState)) begin
      transitionErrorCount++;
      `uvm_error("LINK/TXSTATE", $sformatf(
        "node %0d TX link jumped %s -> %s", node,
        prevTx.name(), sample.txState.name()))
    end
    if (!transitionOk(prevRx, sample.rxState)) begin
      transitionErrorCount++;
      `uvm_error("LINK/RXSTATE", $sformatf(
        "node %0d RX link jumped %s -> %s", node,
        prevRx.name(), sample.rxState.name()))
    end

    // linkUp may only ever be high once the node-to-fabric direction has
    // run; it is that direction's RUN level, nothing else [F-3].
    wasRun = everTxRun.exists(node) && everTxRun[node];
    if (sample.txState == chiGlobalsPkg::LINK_RUN) begin
      everTxRun[node] = 1'b1;
      wasRun = 1'b1;
    end
    if (sample.linkUp) begin
      sawLinkUp[node] = 1'b1;
      if (!wasRun) begin
        linkUpErrorCount++;
        `uvm_error("LINK/LINKUP", $sformatf(
          "node %0d linkUp high while its TX link is %s and has never run",
          node, sample.txState.name()))
      end
    end

    // SACTIVE is driven to resetn on both pins [F-2]; out of reset anything
    // but constant 1, X included, is a violation. The monitor only samples
    // out of reset, so the sample must show 1.
    if (!sample.txSActive || !sample.rxSActive) begin
      sactiveErrorCount++;
      `uvm_error("LINK/SACTIVE", $sformatf(
        "node %0d SACTIVE not constant high out of reset (tx=%0b rx=%0b)",
        node, sample.txSActive, sample.rxSActive))
    end

    // SYSCOACK is a combinational copy of SYSCOREQ [ASSUMPTION:4]; sampled
    // on the same edge they must always agree.
    if (sample.sysCoAck != sample.sysCoReq) begin
      syscoErrorCount++;
      `uvm_error("LINK/SYSCO", $sformatf(
        "node %0d SYSCOACK=%0b is not a copy of SYSCOREQ=%0b",
        node, sample.sysCoAck, sample.sysCoReq))
    end

    sawSample[node] = 1'b1;
    lastTxState[node] = sample.txState;
    lastRxState[node] = sample.rxState;
    lastLinkUp[node] = sample.linkUp;
  endfunction

  // Reconcile one channel's ledger at end of test.
  function automatic void reconcileChannel(input int unsigned node,
      input chiGlobalsPkg::chiChannelE channel,
      input chiGlobalsPkg::chiDirE direction);
    int unsigned flits;
    int unsigned credits;
    int unsigned overdraw;
    int unsigned ceiling;
    int unsigned outsideRun;
    bit dutTransmits;
    string chName;
    string dirName;
    flits = monBfm[node].channelFlitCount(channel, direction);
    credits = monBfm[node].creditCount(channel, direction);
    overdraw = monBfm[node].overdrawErrors(channel, direction);
    ceiling = monBfm[node].ceilingErrors(channel, direction);
    outsideRun = monBfm[node].outsideRunErrors(channel, direction);
    dutTransmits = (direction == chiGlobalsPkg::CHI_DIR_RX);
    chName = chiGlobalsPkg::channelName(channel);
    dirName = dutTransmits ? "RX (DUT transmits)" : "TX (node transmits)";

    if (overdraw > 0) begin
      if (dutTransmits)
        `uvm_error("LINK/OVERDRAW", $sformatf(
          "node %0d %s %s: DUT sent %0d flits with no credit",
          node, chName, dirName, overdraw))
      else if (!cfg.allowTbCreditViolation)
        `uvm_error("LINK/OVERDRAW", $sformatf(
          "node %0d %s %s: bench sent %0d flits with no credit",
          node, chName, dirName, overdraw))
    end
    if (ceiling > 0) begin
      if (!dutTransmits)
        `uvm_error("LINK/CEILING", $sformatf(
          "node %0d %s %s: DUT granted more than LCRD_DEPTH=%0d outstanding credits (%0d cycles)",
          node, chName, dirName, chiGlobalsPkg::LCRD_DEPTH, ceiling))
      else if (!cfg.allowTbCreditViolation)
        `uvm_error("LINK/CEILING", $sformatf(
          "node %0d %s %s: bench granted more than LCRD_DEPTH=%0d outstanding credits (%0d cycles)",
          node, chName, dirName, chiGlobalsPkg::LCRD_DEPTH, ceiling))
    end
    if (outsideRun > 0)
      `uvm_error("LINK/OUTSIDERUN", $sformatf(
        "node %0d %s %s: %0d flits moved while the link was not in RUN",
        node, chName, dirName, outsideRun))

    // Totals must reconcile: no chronic overdraw, no persistent over-grant.
    if (flits > credits)
      `uvm_error("LINK/CREDITS", $sformatf(
        "node %0d %s %s: %0d flits but only %0d credits granted",
        node, chName, dirName, flits, credits))
    if (credits - flits > chiGlobalsPkg::LCRD_DEPTH)
      `uvm_error("LINK/CREDITS", $sformatf(
        "node %0d %s %s: %0d credits outstanding against LCRD_DEPTH=%0d",
        node, chName, dirName, credits - flits, chiGlobalsPkg::LCRD_DEPTH))
    if (monBfm[node].creditBalance(channel, direction) !=
        int'(credits) - int'(flits))
      `uvm_error("LINK/LEDGER", $sformatf(
        "node %0d %s %s: monitor ledger %0d disagrees with totals %0d - %0d",
        node, chName, dirName, monBfm[node].creditBalance(channel, direction),
        credits, flits))

    // A node-transmit channel that finished its drain owes every credit
    // back, so flits and credits balance exactly [SPEC:B13.5].
    if ((direction == chiGlobalsPkg::CHI_DIR_TX) &&
        sawSample.exists(node) &&
        (lastTxState[node] == chiGlobalsPkg::LINK_STOP) &&
        (flits != credits))
      `uvm_error("LINK/DRAIN", $sformatf(
        "node %0d %s TX: link stopped with %0d flits against %0d credits (drain incomplete)",
        node, chName, flits, credits))
  endfunction

  function automatic void reconcileNode(input int unsigned node);
    bit isReq;
    isReq = chiGlobalsPkg::nodeClassIsRequester(
      chiGlobalsPkg::nodeClassOfOrdinal(node));
    if (isReq)
      reconcileChannel(node, chiGlobalsPkg::CHI_CH_REQ, chiGlobalsPkg::CHI_DIR_TX);
    reconcileChannel(node, chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_TX);
    reconcileChannel(node, chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_TX);
    if (!isReq)
      reconcileChannel(node, chiGlobalsPkg::CHI_CH_REQ, chiGlobalsPkg::CHI_DIR_RX);
    reconcileChannel(node, chiGlobalsPkg::CHI_CH_RSP, chiGlobalsPkg::CHI_DIR_RX);
    reconcileChannel(node, chiGlobalsPkg::CHI_CH_DAT, chiGlobalsPkg::CHI_DIR_RX);
    if (isReq)
      reconcileChannel(node, chiGlobalsPkg::CHI_CH_SNP, chiGlobalsPkg::CHI_DIR_RX);
  endfunction

  function void check_phase(uvm_phase phase);
    int unsigned totalParity;
    int unsigned totalCredit;
    super.check_phase(phase);
    if (!cfg.enableLinkChecks)
      return;
    totalParity = 0;
    totalCredit = 0;
    for (int unsigned ord = 0; ord < chiGlobalsPkg::OFF_HNF; ord++) begin
      // linkUp must end in agreement with the node-to-fabric link state,
      // and must have risen if that link ever ran [F-3].
      if (sawSample.exists(ord)) begin
        if (lastLinkUp[ord] != (lastTxState[ord] == chiGlobalsPkg::LINK_RUN))
          `uvm_error("LINK/LINKUP", $sformatf(
            "node %0d ended with linkUp=%0b but TX link state %s",
            ord, lastLinkUp[ord], lastTxState[ord].name()))
        if (everTxRun.exists(ord) && everTxRun[ord] &&
            !(sawLinkUp.exists(ord) && sawLinkUp[ord]))
          `uvm_error("LINK/LINKUP", $sformatf(
            "node %0d TX link ran but linkUp never rose", ord))
      end
      reconcileNode(ord);
      totalParity += monBfm[ord].parityErrors();
      totalCredit += monBfm[ord].creditErrors();
    end

    // The directed error outputs are pulses; the monitors latched and
    // counted them. Each must match the test's expectation exactly
    // [ASSUMPTION:17].
    if (cfg.expectLinkParityError && (totalParity == 0))
      `uvm_error("LINK/PARITY", "test injected a parity fault but linkParityError never fired")
    if (!cfg.expectLinkParityError && (totalParity > 0))
      `uvm_error("LINK/PARITY", $sformatf(
        "linkParityError fired %0d times with no injection configured",
        totalParity))
    if (cfg.expectLinkCreditError && (totalCredit == 0))
      `uvm_error("LINK/CREDITERR", "test injected a credit fault but linkCreditError never fired")
    if (!cfg.expectLinkCreditError && (totalCredit > 0))
      `uvm_error("LINK/CREDITERR", $sformatf(
        "linkCreditError fired %0d times with no injection configured",
        totalCredit))
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("LINK/SUMMARY", $sformatf(
      "link model: %0d link samples, %0d transition / %0d linkUp / %0d SACTIVE / %0d SYSCO errors",
      linkSampleCount, transitionErrorCount, linkUpErrorCount,
      sactiveErrorCount, syscoErrorCount), UVM_MEDIUM)
  endfunction

endclass
