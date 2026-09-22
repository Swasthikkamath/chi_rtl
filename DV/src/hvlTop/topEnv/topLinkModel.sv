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
  endfunction

  function void chiNoteLink(input chiLinkSampleT sample);
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
