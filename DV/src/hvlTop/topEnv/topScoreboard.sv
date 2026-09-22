// Fans every observed flit out to the four reference models and to
// coverage. The models do not share state with each other or with any
// driver. Leftover monitor samples, including L-Credit returns from
// deactivation, are drained here in check_phase through the non-blocking
// pops, because check_phase is a function. [ASSUMPTION:18]
// See OPEN QUESTIONS Q18.

class topScoreboard extends uvm_component;
  topEnvConfig cfg;
  topLinkModel linkModel;
  topLifecycleModel lifecycleModel;
  topDirectoryModel directoryModel;
  topMemoryModel memoryModel;
  topCoverage cov;
  virtual chiMonitorBfm bfmByOrdinal[int unsigned];
  topReqSink txReqSink[int unsigned];
  topReqSink rxReqSink[int unsigned];
  topRspSink txRspSink[int unsigned];
  topRspSink rxRspSink[int unsigned];
  topDatSink txDatSink[int unsigned];
  topDatSink rxDatSink[int unsigned];
  topSnpSink rxSnpSink[int unsigned];
  topLinkSink linkSink[int unsigned];
  topFlitSink flitSink[int unsigned];
  topCreditSink creditSink[int unsigned];

  `uvm_component_utils(topScoreboard)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(topEnvConfig)::get(this, "", "topEnvConfig", cfg))
      `uvm_fatal("topEnvConfig", "config_db get failed for key topEnvConfig")
    linkModel = topLinkModel::type_id::create("linkModel", this);
    lifecycleModel = topLifecycleModel::type_id::create("lifecycleModel", this);
    directoryModel = topDirectoryModel::type_id::create("directoryModel", this);
    memoryModel = topMemoryModel::type_id::create("memoryModel", this);
    chiBuildPorts(RN_F, NUM_RNF, OFF_RNF);
    chiBuildPorts(RN_D, NUM_RND, OFF_RND);
    chiBuildPorts(RN_I, NUM_RNI, OFF_RNI);
    chiBuildPorts(SN_F, NUM_SNF, OFF_SNF);
    chiBuildPorts(SN_I, NUM_SNI, OFF_SNI);
  endfunction

  function void chiBuildPorts(
    input chiNodeClassE nodeClass,
    input int unsigned count,
    input int unsigned base
  );
    for (int unsigned i = 0; i < count; i++) begin
      int unsigned ordinal;
      virtual chiMonitorBfm bfm;
      string key;
      ordinal = base + i;
      if (cfg.chiHoldQuiet(nodeClass, i))
        linkModel.chiMarkQuiet(ordinal);
      else
        linkModel.chiExpectActive(ordinal);
      key = monitorBfmKey(ordinal);
      if (!uvm_config_db#(virtual chiMonitorBfm)::get(null, "*", key, bfm))
        `uvm_fatal("topScoreboard", {"config_db get failed for key ", key})
      bfmByOrdinal[ordinal] = bfm;
      linkModel.bfmByOrdinal[ordinal] = bfm;
      txReqSink[ordinal] = chiMakeReqSink($sformatf("txReqSink%0d", ordinal), ordinal, nodeClass, 1'b1);
      rxReqSink[ordinal] = chiMakeReqSink($sformatf("rxReqSink%0d", ordinal), ordinal, nodeClass, 1'b0);
      txRspSink[ordinal] = chiMakeRspSink($sformatf("txRspSink%0d", ordinal), ordinal, nodeClass, 1'b1);
      rxRspSink[ordinal] = chiMakeRspSink($sformatf("rxRspSink%0d", ordinal), ordinal, nodeClass, 1'b0);
      txDatSink[ordinal] = chiMakeDatSink($sformatf("txDatSink%0d", ordinal), ordinal, nodeClass, 1'b1);
      rxDatSink[ordinal] = chiMakeDatSink($sformatf("rxDatSink%0d", ordinal), ordinal, nodeClass, 1'b0);
      rxSnpSink[ordinal] = chiMakeSnpSink($sformatf("rxSnpSink%0d", ordinal), ordinal, nodeClass);
      linkSink[ordinal] = chiMakeLinkSink($sformatf("linkSink%0d", ordinal), ordinal);
      creditSink[ordinal] = chiMakeCreditSink($sformatf("creditSink%0d", ordinal));
      if (!nodeClassIsRequester(nodeClass))
        flitSink[ordinal] = chiMakeFlitSink($sformatf("flitSink%0d", ordinal), ordinal);
    end
  endfunction

  function topReqSink chiMakeReqSink(
    input string name,
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx
  );
    topReqSink sink;
    sink = topReqSink::type_id::create(name, this);
    sink.ordinal = ordinal;
    sink.nodeClass = nodeClass;
    sink.isTx = isTx;
    sink.sb = this;
    return sink;
  endfunction

  function topRspSink chiMakeRspSink(
    input string name,
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx
  );
    topRspSink sink;
    sink = topRspSink::type_id::create(name, this);
    sink.ordinal = ordinal;
    sink.nodeClass = nodeClass;
    sink.isTx = isTx;
    sink.sb = this;
    return sink;
  endfunction

  function topDatSink chiMakeDatSink(
    input string name,
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx
  );
    topDatSink sink;
    sink = topDatSink::type_id::create(name, this);
    sink.ordinal = ordinal;
    sink.nodeClass = nodeClass;
    sink.isTx = isTx;
    sink.sb = this;
    return sink;
  endfunction

  function topSnpSink chiMakeSnpSink(
    input string name,
    input int unsigned ordinal,
    input chiNodeClassE nodeClass
  );
    topSnpSink sink;
    sink = topSnpSink::type_id::create(name, this);
    sink.ordinal = ordinal;
    sink.nodeClass = nodeClass;
    sink.isTx = 1'b0;
    sink.sb = this;
    return sink;
  endfunction

  function topFlitSink chiMakeFlitSink(input string name, input int unsigned ordinal);
    topFlitSink sink;
    sink = topFlitSink::type_id::create(name, this);
    sink.sb = this;
    return sink;
  endfunction

  function topCreditSink chiMakeCreditSink(input string name);
    topCreditSink sink;
    sink = topCreditSink::type_id::create(name, this);
    sink.sb = this;
    return sink;
  endfunction

  function topLinkSink chiMakeLinkSink(input string name, input int unsigned ordinal);
    topLinkSink sink;
    sink = topLinkSink::type_id::create(name, this);
    sink.ordinal = ordinal;
    sink.sb = this;
    return sink;
  endfunction

  function void chiNoteReq(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiReqFlitT flit
  );
    linkModel.chiNoteFlit(ordinal, CHI_CH_REQ,
      isTx ? CHI_DIR_TX : CHI_DIR_RX, flit.opcode == REQ_LCRD_RETURN);
    lifecycleModel.chiNoteReq(ordinal, nodeClass, isTx, flit);
    memoryModel.chiNoteReq(ordinal, nodeClass, isTx, flit);
    // The directory model needs the request too: a completion carries no
    // address, so without this it cannot tell which line was acquired.
    directoryModel.chiNoteReq(ordinal, nodeClass, isTx, flit);
    if (cov != null)
      cov.chiSampleReq(nodeClass, isTx, flit);
  endfunction

  function void chiNoteRsp(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiRspFlitT flit
  );
    linkModel.chiNoteFlit(ordinal, CHI_CH_RSP,
      isTx ? CHI_DIR_TX : CHI_DIR_RX, flit.opcode == RSP_LCRD_RETURN);
    lifecycleModel.chiNoteRsp(ordinal, nodeClass, isTx, flit);
    memoryModel.chiNoteRsp(ordinal, nodeClass, isTx, flit);
    directoryModel.chiNoteRsp(ordinal, nodeClass, isTx, flit);
  endfunction

  function void chiNoteDat(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiDatFlitT flit
  );
    linkModel.chiNoteFlit(ordinal, CHI_CH_DAT,
      isTx ? CHI_DIR_TX : CHI_DIR_RX, flit.opcode == DAT_LCRD_RETURN);
    lifecycleModel.chiNoteDat(ordinal, nodeClass, isTx, flit);
    memoryModel.chiNoteDat(ordinal, nodeClass, isTx, flit);
    directoryModel.chiNoteDat(ordinal, nodeClass, isTx, flit);
  endfunction

  function void chiNoteSnp(
    input int unsigned ordinal,
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiSnpFlitT flit
  );
    linkModel.chiNoteFlit(ordinal, CHI_CH_SNP,
      isTx ? CHI_DIR_TX : CHI_DIR_RX, flit.opcode == SNP_LCRD_RETURN);
    directoryModel.chiNoteSnp(ordinal, nodeClass, isTx, flit);
  endfunction

  function void chiNoteLink(input chiLinkSampleT sample);
    linkModel.chiNoteLink(sample);
  endfunction

  function void chiNoteCredit(input chiCreditSampleT sample);
    linkModel.chiNoteCredit(sample);
  endfunction

  function void chiNoteSample(input chiFlitSampleT sample);
    bit isTx;
    isTx = (sample.direction == CHI_DIR_TX);
    case (sample.channel)
      CHI_CH_REQ: chiNoteReq(sample.nodeOrdinal, sample.nodeClass, isTx, unpackReq(sample.payload));
      CHI_CH_RSP: chiNoteRsp(sample.nodeOrdinal, sample.nodeClass, isTx, unpackRsp(sample.payload));
      CHI_CH_DAT: chiNoteDat(sample.nodeOrdinal, sample.nodeClass, isTx, unpackDat(sample.payload));
      default: chiNoteSnp(sample.nodeOrdinal, sample.nodeClass, isTx, unpackSnp(sample.payload));
    endcase
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    foreach (bfmByOrdinal[ordinal]) begin
      chiFlitSampleT flitSample;
      chiLinkSampleT linkSample;
      chiCreditSampleT creditSample;
      // Credits first: a flit drained here was sent against a credit that
      // may also still be queued, and crediting after spending would report
      // an overdraft that never happened.
      while (bfmByOrdinal[ordinal].tryGetCreditSample(creditSample))
        chiNoteCredit(creditSample);
      while (bfmByOrdinal[ordinal].tryGetFlitSample(flitSample))
        chiNoteSample(flitSample);
      while (bfmByOrdinal[ordinal].tryGetLinkSample(linkSample))
        chiNoteLink(linkSample);
    end
    linkModel.chiCheckEnd();
    lifecycleModel.chiCheckEnd();
    directoryModel.chiCheckEnd();
    memoryModel.chiCheckEnd();
  endfunction
endclass
