// Link reference model. It watches activation, linkUp, error pulses
// and credit balance from boundary samples only. It does not share
// state with the other three models or with any driver.
// [ASSUMPTION:3] [ASSUMPTION:9] [ASSUMPTION:16] [ASSUMPTION:17]
// [ASSUMPTION:18] See OPEN QUESTIONS Q17.

typedef struct packed {
  logic [31:0] ordinal;
  chiChannelE channel;
  chiDirE direction;
} topLinkKeyT;

class topLinkModel extends uvm_component;
  bit activeOrdinal[int unsigned];
  bit quietOrdinal[int unsigned];
  bit sawTxRun[int unsigned];
  bit sawRxRun[int unsigned];
  int unsigned parityPulses;
  int unsigned creditPulses;
  int unsigned protoCount[topLinkKeyT];
  int unsigned lcrdCount[topLinkKeyT];
  bit expectParityError;
  bit expectCreditError;
  virtual chiMonitorBfm bfmByOrdinal[int unsigned];

  // Live credit ledger. The end-of-test balance below proves the books
  // close; this proves they were never overdrawn in between, which a total
  // cannot show because a flit sent one cycle before its credit arrives
  // leaves the same total behind as one sent a cycle after.
  // [SPEC:IHI0050H B14.2 Flow control]
  int unsigned grantedCount[topLinkKeyT];
  int unsigned spentCount[topLinkKeyT];

  // Last observed activation state per direction, for checking that the
  // handshake walks its cycle rather than jumping.
  chiLinkStateE lastTxState[int unsigned];
  chiLinkStateE lastRxState[int unsigned];

  `uvm_component_utils(topLinkModel)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    parityPulses = 0;
    creditPulses = 0;
    expectParityError = 1'b0;
    expectCreditError = 1'b0;
  endfunction

  function void chiExpectActive(input int unsigned ordinal);
    activeOrdinal[ordinal] = 1'b1;
  endfunction

  function void chiMarkQuiet(input int unsigned ordinal);
    quietOrdinal[ordinal] = 1'b1;
  endfunction

  function topLinkKeyT chiLinkKey(
    input int unsigned ordinal,
    input chiChannelE channel,
    input chiDirE direction
  );
    topLinkKeyT key;
    key.ordinal = ordinal;
    key.channel = channel;
    key.direction = direction;
    return key;
  endfunction

  function void chiNoteFlit(
    input int unsigned ordinal,
    input chiChannelE channel,
    input chiDirE direction,
    input bit lcrd
  );
    topLinkKeyT key;
    chiLinkStateE senderState;
    key = chiLinkKey(ordinal, channel, direction);
    if (lcrd) begin
      if (!lcrdCount.exists(key))
        lcrdCount[key] = 0;
      lcrdCount[key]++;
    end else begin
      if (!protoCount.exists(key))
        protoCount[key] = 0;
      protoCount[key]++;
    end

    // Both a Protocol flit and an L-Credit return consume one credit.
    if (!spentCount.exists(key))
      spentCount[key] = 0;
    spentCount[key]++;
    if (spentCount[key] > (grantedCount.exists(key) ? grantedCount[key] : 0))
      `uvm_error("topLinkModel",
        $sformatf("ordinal %0d %s %s has sent %0d flits against %0d credits",
                  ordinal, channel.name(), direction.name(), spentCount[key],
                  grantedCount.exists(key) ? grantedCount[key] : 0))

    // A flit may only move while the link carrying it is running.
    // [SPEC:IHI0050H B13.5 Link activation and deactivation]
    senderState = (direction == CHI_DIR_TX)
      ? (lastTxState.exists(ordinal) ? lastTxState[ordinal] : LINK_STOP)
      : (lastRxState.exists(ordinal) ? lastRxState[ordinal] : LINK_STOP);
    if (senderState != LINK_RUN)
      `uvm_error("topLinkModel",
        $sformatf("ordinal %0d carried a %s flit while its %s link was %s",
                  ordinal, channel.name(), direction.name(), senderState.name()))
  endfunction

  function void chiNoteCredit(input chiCreditSampleT sample);
    topLinkKeyT key;
    int unsigned outstanding;
    key = chiLinkKey(sample.nodeOrdinal, sample.channel, sample.direction);
    if (!grantedCount.exists(key))
      grantedCount[key] = 0;
    grantedCount[key]++;
    outstanding = grantedCount[key] - (spentCount.exists(key) ? spentCount[key] : 0);
    // The DUT raises linkCreditError if it is ever given more credits than
    // its transmit depth, so this ceiling is a hard limit the testbench must
    // respect rather than a convention. [ASSUMPTION:9]
    if (outstanding > LCRD_DEPTH)
      `uvm_error("topLinkModel",
        $sformatf("ordinal %0d %s %s holds %0d credits, above the depth of %0d",
                  sample.nodeOrdinal, sample.channel.name(), sample.direction.name(),
                  outstanding, LCRD_DEPTH))
  endfunction

  // The activation handshake walks STOP, ACTIVATE, RUN, DEACTIVATE, STOP.
  // Any other step means one side moved without the other, which is the
  // thing the handshake exists to prevent.
  // [SPEC:IHI0050H B13.5 Link activation and deactivation]
  function bit chiLegalTransition(input chiLinkStateE from, input chiLinkStateE to);
    if (from == to)
      return 1'b1;
    case (from)
      LINK_STOP:       return to == LINK_ACTIVATE;
      LINK_ACTIVATE:   return to == LINK_RUN;
      LINK_RUN:        return to == LINK_DEACTIVATE;
      LINK_DEACTIVATE: return to == LINK_STOP;
      default:         return 1'b0;
    endcase
  endfunction

  function void chiNoteLink(input chiLinkSampleT sample);
    if (!lastTxState.exists(sample.nodeOrdinal)) begin
      lastTxState[sample.nodeOrdinal] = LINK_STOP;
      lastRxState[sample.nodeOrdinal] = LINK_STOP;
    end
    if (!chiLegalTransition(lastTxState[sample.nodeOrdinal], sample.txState))
      `uvm_error("topLinkModel",
        $sformatf("ordinal %0d TX link went %s to %s, which is not a step of the cycle",
                  sample.nodeOrdinal, lastTxState[sample.nodeOrdinal].name(),
                  sample.txState.name()))
    if (!chiLegalTransition(lastRxState[sample.nodeOrdinal], sample.rxState))
      `uvm_error("topLinkModel",
        $sformatf("ordinal %0d RX link went %s to %s, which is not a step of the cycle",
                  sample.nodeOrdinal, lastRxState[sample.nodeOrdinal].name(),
                  sample.rxState.name()))
    lastTxState[sample.nodeOrdinal] = sample.txState;
    lastRxState[sample.nodeOrdinal] = sample.rxState;
    if (sample.txState == LINK_RUN)
      sawTxRun[sample.nodeOrdinal] = 1'b1;
    if (sample.rxState == LINK_RUN)
      sawRxRun[sample.nodeOrdinal] = 1'b1;
    if (sample.parityError)
      parityPulses++;
    if (sample.creditError)
      creditPulses++;
    // linkUp follows the node-to-fabric direction only. [ASSUMPTION:17]
    if (sample.linkUp && (sample.txState != LINK_RUN))
      `uvm_error("topLinkModel",
        {$sformatf("linkUp set on ordinal %0d while TX state is %s",
          sample.nodeOrdinal, sample.txState.name())})
  endfunction

  function void chiCheckEnd();
    foreach (activeOrdinal[ordinal]) begin
      if (!sawTxRun.exists(ordinal))
        `uvm_error("topLinkModel",
          {$sformatf("ordinal %0d never reached TX RUN", ordinal)})
      if (!sawRxRun.exists(ordinal))
        `uvm_error("topLinkModel",
          {$sformatf("ordinal %0d never reached RX RUN", ordinal)})
    end
    foreach (bfmByOrdinal[ordinal]) begin
      if (bfmByOrdinal[ordinal].currentTxState() != LINK_STOP)
        `uvm_error("topLinkModel",
          {$sformatf("ordinal %0d TX link is %s at end of test",
            ordinal, bfmByOrdinal[ordinal].currentTxState().name())})
      // A quiet port never takes credits, so a fabric grant there is not
      // this port's balance to close. See OPEN QUESTIONS Q18.
      if (!quietOrdinal.exists(ordinal))
        chiCheckCredits(ordinal, bfmByOrdinal[ordinal]);
    end
    if (expectParityError && (parityPulses == 0))
      `uvm_error("topLinkModel", "expected a linkParityError pulse and saw none")
    if (!expectParityError && (parityPulses != 0))
      `uvm_error("topLinkModel",
        {$sformatf("unexpected linkParityError pulses: %0d", parityPulses)})
    if (expectCreditError && (creditPulses == 0))
      `uvm_warning("topLinkModel",
        "no linkCreditError pulse; the interconnect may have replenished credits first")
    if (!expectCreditError && (creditPulses != 0))
      `uvm_error("topLinkModel",
        {$sformatf("unexpected linkCreditError pulses: %0d", creditPulses)})
  endfunction

  function void chiCheckCredits(input int unsigned ordinal, virtual chiMonitorBfm bfm);
    chiChannelE channel;
    chiDirE direction;
    channel = CHI_CH_REQ;
    for (int unsigned ch = 0; ch < 4; ch++) begin
      channel = chiChannelE'(ch);
      direction = CHI_DIR_TX;
      for (int unsigned dir = 0; dir < 2; dir++) begin
        topLinkKeyT key;
        int unsigned proto;
        int unsigned lcrd;
        int unsigned grants;
        direction = chiDirE'(dir);
        key = chiLinkKey(ordinal, channel, direction);
        proto = protoCount.exists(key) ? protoCount[key] : 0;
        lcrd = lcrdCount.exists(key) ? lcrdCount[key] : 0;
        grants = bfm.creditGrants(channel, direction);
        if (grants != (proto + lcrd))
          `uvm_error("topLinkModel",
            {$sformatf("ordinal %0d %s %s credits %0d != flits %0d + returns %0d",
              ordinal, channel.name(), direction.name(), grants, proto, lcrd)})
      end
    end
  endfunction
endclass
