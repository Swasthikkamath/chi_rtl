// What the interconnect actually asked a Subordinate to do.
//
// This is the only place the DUT's downstream behaviour is measured. The
// requester coverage says what was asked of the interconnect; this says
// what the interconnect chose to do about it, which is a different and
// less predictable thing: whether it ever used ReadNoSnpSep, whether it
// ever cancelled a write, whether it forwarded an atomic rather than
// executing it at the Home.
//
// As on the requester side, bins for a feature the configuration disabled
// live in their own covergroup that is built only when the feature is on,
// so a disabled feature is absent rather than permanently at zero.
// [ASSUMPTION:15]

covergroup chiSubordinateReqCg with function sample(
  chiReqOpcodeE opcode,
  chiNodeClassE nodeClass,
  logic [SIZE_W-1:0] size,
  logic [ORDER_W-1:0] order,
  logic [MEM_ATTR_W-1:0] memAttr
);
  opcodeCp: coverpoint opcode {
    bins readNoSnp = {REQ_READ_NO_SNP};
    bins readNoSnpSep = {REQ_READ_NO_SNP_SEP};
    bins writeNoSnpFull = {REQ_WRITE_NO_SNP_FULL};
    bins writeNoSnpPtl = {REQ_WRITE_NO_SNP_PTL};
    bins writeNoSnpZero = {REQ_WRITE_NO_SNP_ZERO};
    bins writeNoSnpDef = {REQ_WRITE_NO_SNP_DEF};
    bins cleanShared = {REQ_CLEAN_SHARED};
    bins cleanSharedPersist = {REQ_CLEAN_SHARED_PERSIST};
    bins cleanSharedPersistSep = {REQ_CLEAN_SHARED_PERSIST_SEP};
    bins cleanInvalid = {REQ_CLEAN_INVALID};
    bins cleanInvalidPoPA = {REQ_CLEAN_INVALID_POPA};
    bins cleanInvalidStorage = {REQ_CLEAN_INVALID_STORAGE};
    bins makeInvalid = {REQ_MAKE_INVALID};
    bins prefetchTgt = {REQ_PREFETCH_TGT};
  }
  classCp: coverpoint nodeClass {
    bins snf = {SN_F};
    bins sni = {SN_I};
  }
  sizeCp: coverpoint size {
    bins b1 = {3'd0};
    bins b2 = {3'd1};
    bins b4 = {3'd2};
    bins b8 = {3'd3};
    bins b16 = {3'd4};
    bins b32 = {3'd5};
    bins b64 = {3'd6};
  }
  // Order 0b01 is Request Accepted, the only non-zero value a Home may send
  // to an SN-F, and the only one that asks for a ReadReceipt.
  // [SPEC:IHI0050H B2.7.5 Table B2.9]
  orderCp: coverpoint order {
    bins none = {2'b00};
    bins requestAccepted = {2'b01};
    bins other = {[2'b10:2'b11]};
  }
  memAttrCp: coverpoint memAttr;
  opcodeClassCx: cross opcodeCp, classCp {
    // Table B4.3 gives HN-I to SN-I only ReadNoSnp, and PrefetchTgt is
    // defined as targeting an SN-F.
    ignore_bins sniOnly = binsof(classCp) intersect {SN_I}
      && binsof(opcodeCp) intersect {REQ_READ_NO_SNP_SEP, REQ_PREFETCH_TGT};
  }
  opcodeSizeCx: cross opcodeCp, sizeCp;
endgroup

// The nine Combined Write and CMO requests a Home may send to a
// Subordinate. Kept separate from the main group because the interesting
// question is whether the DUT ever combines at all.
// [SPEC:IHI0050H B4.2.4 Table B4.20]
covergroup chiSubordinateCombinedCg with function sample(chiReqOpcodeE opcode);
  combinedCp: coverpoint opcode {
    bins ptlCleanInv = {REQ_WRITE_NO_SNP_PTL_CLEAN_INV};
    bins fullCleanInv = {REQ_WRITE_NO_SNP_FULL_CLEAN_INV};
    bins ptlCleanSh = {REQ_WRITE_NO_SNP_PTL_CLEAN_SH};
    bins fullCleanSh = {REQ_WRITE_NO_SNP_FULL_CLEAN_SH};
    bins ptlCleanShPerSep = {REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP};
    bins fullCleanShPerSep = {REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP};
    bins ptlCleanInvPoPA = {REQ_WRITE_NO_SNP_PTL_CLEAN_INV_POPA};
    bins fullCleanInvPoPA = {REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA};
    bins fullCleanInvStrg = {REQ_WRITE_NO_SNP_FULL_CLEAN_INV_STRG};
  }
endgroup

// Forwarding an atomic to the Subordinate is permitted but not required, so
// this group answers whether this interconnect ever does.
// [SPEC:IHI0050H B2.3.9.6]
covergroup chiSubordinateAtomicCg with function sample(chiReqOpcodeE opcode);
  atomicCp: coverpoint opcode {
    bins store = {[REQ_ATOMIC_STORE_ADD:REQ_ATOMIC_STORE_UMIN]};
    bins load = {[REQ_ATOMIC_LOAD_ADD:REQ_ATOMIC_LOAD_UMIN]};
    bins swap = {REQ_ATOMIC_SWAP};
    bins compare = {REQ_ATOMIC_COMPARE};
  }
endgroup

// What the Subordinate was made to answer with. Response shape is a
// testbench choice, so this group measures the testbench's own spread and
// exists to prove the DUT saw both alternatives of every flow that has two.
covergroup chiSubordinateRespCg with function sample(
  chiRspOpcodeE opcode,
  chiRespErrE respErr,
  bit combined
);
  respOpcodeCp: coverpoint opcode {
    bins comp = {RSP_COMP};
    bins dbidResp = {RSP_DBID_RESP};
    bins compDbidResp = {RSP_COMP_DBID_RESP};
    bins readReceipt = {RSP_READ_RECEIPT};
    bins persist = {RSP_PERSIST};
    bins compPersist = {RSP_COMP_PERSIST};
    bins compCmo = {RSP_COMP_CMO};
  }
  respErrCp: coverpoint respErr;
  combinedCp: coverpoint combined {
    bins separate = {1'b0};
    bins combinedShape = {1'b1};
  }
  shapeCx: cross respOpcodeCp, combinedCp;
endgroup

// Write data the Subordinate received, including the cancellation case and
// transfers that carried fewer packets than Size implied.
covergroup chiSubordinateWriteDataCg with function sample(
  chiDatOpcodeE opcode,
  logic [NUM_DAT_W-1:0] numDat,
  bit fullLine
);
  datOpcodeCp: coverpoint opcode {
    bins nonCopyBack = {DAT_NON_COPY_BACK_WR_DATA};
    bins copyBack = {DAT_COPY_BACK_WR_DATA};
    bins cancel = {DAT_WRITE_DATA_CANCEL};
    bins ncbWithAck = {DAT_NCB_WR_DATA_COMP_ACK};
  }
  numDatCp: coverpoint numDat;
  fullLineCp: coverpoint fullLine;
endgroup

class chiSubordinateCoverage extends uvm_component;
  chiSubordinateConfig cfg;
  chiSubordinateReqCg reqCg;
  chiSubordinateRespCg respCg;
  chiSubordinateWriteDataCg writeDataCg;
  chiSubordinateCombinedCg combinedCg;
  chiSubordinateAtomicCg atomicCg;

  `uvm_component_utils(chiSubordinateCoverage)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    reqCg = new();
    respCg = new();
    writeDataCg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (CHI_CFG.atomicEn)
      atomicCg = new();
    // Combined Write and CMO has no enable field: it is unconditionally
    // present and the HN-F implements it. See OPEN QUESTIONS Q15.
    combinedCg = new();
  endfunction

  function void sampleRequest(input chiReqFlitT req, input chiSubordinateTx rule);
    reqCg.sample(req.opcode, cfg.nodeClass, req.size, req.order, req.memAttr);
    if ((combinedCg != null) && chiCombinedOpcode(req.opcode))
      combinedCg.sample(req.opcode);
    if ((atomicCg != null) && chiAtomicOpcode(req.opcode))
      atomicCg.sample(req.opcode);
  endfunction

  function void sampleResponse(
    input chiRspOpcodeE opcode,
    input chiRespErrE respErr,
    input bit combined
  );
    respCg.sample(opcode, respErr, combined);
  endfunction

  function void sampleWriteData(input chiDatFlitT flit, input bit fullLine);
    writeDataCg.sample(flit.opcode, flit.numDat, fullLine);
  endfunction

  function bit chiCombinedOpcode(input chiReqOpcodeE opcode);
    return opcode inside {
      REQ_WRITE_NO_SNP_PTL_CLEAN_INV, REQ_WRITE_NO_SNP_FULL_CLEAN_INV,
      REQ_WRITE_NO_SNP_PTL_CLEAN_SH, REQ_WRITE_NO_SNP_FULL_CLEAN_SH,
      REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP, REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP,
      REQ_WRITE_NO_SNP_PTL_CLEAN_INV_POPA, REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA,
      REQ_WRITE_NO_SNP_FULL_CLEAN_INV_STRG};
  endfunction

  function bit chiAtomicOpcode(input chiReqOpcodeE opcode);
    return ((opcode >= REQ_ATOMIC_STORE_ADD) && (opcode <= REQ_ATOMIC_LOAD_UMIN))
           || (opcode inside {REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE});
  endfunction
endclass
