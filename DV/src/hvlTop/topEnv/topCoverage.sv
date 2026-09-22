// Opcode coverage at the boundary, crossed with the node class of the
// port that carried the request. A disabled feature has its own
// covergroup, built only when that feature is enabled, so it is absent
// from the model otherwise. [ASSUMPTION:15] [ASSUMPTION:18]
//
// The groups are package types. An embedded covergroup would be built
// with the component, which would keep a disabled feature in the model.

covergroup topIssueCg with function sample(
  chiReqOpcodeE opcode,
  chiNodeClassE nodeClass
);
  opcodeCp: coverpoint opcode {
    option.auto_bin_max = 0;
    bins readShared = {REQ_READ_SHARED};
    bins readClean = {REQ_READ_CLEAN};
    bins readOnce = {REQ_READ_ONCE};
    bins readNoSnp = {REQ_READ_NO_SNP};
    bins readNoSnpSep = {REQ_READ_NO_SNP_SEP};
    bins readUnique = {REQ_READ_UNIQUE};
    bins cleanShared = {REQ_CLEAN_SHARED};
    bins cleanInvalid = {REQ_CLEAN_INVALID};
    bins makeInvalid = {REQ_MAKE_INVALID};
    bins cleanUnique = {REQ_CLEAN_UNIQUE};
    bins makeUnique = {REQ_MAKE_UNIQUE};
    bins evict = {REQ_EVICT};
    bins writeBack = {REQ_WRITE_BACK_FULL};
    bins writeClean = {REQ_WRITE_CLEAN_FULL};
    bins writeUnique = {REQ_WRITE_UNIQUE_FULL};
    bins writeNoSnp = {REQ_WRITE_NO_SNP_FULL};
    bins writeUniqueZero = {REQ_WRITE_UNIQUE_ZERO};
    bins writeNoSnpZero = {REQ_WRITE_NO_SNP_ZERO};
    bins prefetch = {REQ_PREFETCH_TGT};
    bins pcrdReturn = {REQ_P_CRD_RETURN};
  }
  classCp: coverpoint nodeClass {
    option.auto_bin_max = 0;
    bins rnf = {RN_F};
    bins rnd = {RN_D};
    bins rni = {RN_I};
    bins snf = {SN_F};
    bins sni = {SN_I};
  }
  opcodeClassCx: cross opcodeCp, classCp {
    ignore_bins rndCache = binsof(classCp) intersect {RN_D, SN_F, SN_I}
      && binsof(opcodeCp) intersect {
        REQ_READ_SHARED, REQ_READ_CLEAN, REQ_READ_UNIQUE, REQ_CLEAN_UNIQUE,
        REQ_MAKE_UNIQUE, REQ_EVICT, REQ_WRITE_BACK_FULL, REQ_WRITE_CLEAN_FULL,
        REQ_PREFETCH_TGT
      };
    ignore_bins rniCache = binsof(classCp) intersect {RN_I}
      && binsof(opcodeCp) intersect {
        REQ_READ_SHARED, REQ_READ_CLEAN, REQ_READ_ONCE, REQ_READ_UNIQUE,
        REQ_CLEAN_UNIQUE, REQ_MAKE_UNIQUE, REQ_EVICT, REQ_WRITE_BACK_FULL,
        REQ_WRITE_CLEAN_FULL, REQ_WRITE_UNIQUE_FULL, REQ_WRITE_UNIQUE_ZERO,
        REQ_PREFETCH_TGT
      };
    ignore_bins sniCache = binsof(classCp) intersect {SN_I}
      && binsof(opcodeCp) intersect {
        REQ_WRITE_UNIQUE_FULL, REQ_WRITE_UNIQUE_ZERO, REQ_PREFETCH_TGT,
        REQ_READ_ONCE, REQ_READ_SHARED
      };
  }
endgroup

covergroup topAtomicCg with function sample(chiReqOpcodeE opcode);
  atomicCp: coverpoint opcode {
    option.auto_bin_max = 0;
    bins loadAdd = {REQ_ATOMIC_LOAD_ADD};
    bins storeAdd = {REQ_ATOMIC_STORE_ADD};
    bins swap = {REQ_ATOMIC_SWAP};
    bins compare = {REQ_ATOMIC_COMPARE};
  }
endgroup

covergroup topDvmCg with function sample(chiReqOpcodeE opcode);
  dvmCp: coverpoint opcode {
    option.auto_bin_max = 0;
    bins dvm = {REQ_DVM_OP};
  }
endgroup

covergroup topStashCg with function sample(chiReqOpcodeE opcode);
  stashCp: coverpoint opcode {
    option.auto_bin_max = 0;
    bins stash = {REQ_STASH_ONCE_SHARED};
  }
endgroup

covergroup topExclCg with function sample(bit excl);
  exclCp: coverpoint excl {
    option.auto_bin_max = 0;
    bins exclusive = {1'b1};
  }
endgroup

covergroup topMpamCg with function sample(bit mpamSet);
  mpamCp: coverpoint mpamSet {
    option.auto_bin_max = 0;
    bins set = {1'b1};
  }
endgroup

covergroup topPbhaCg with function sample(bit pbhaSet);
  pbhaCp: coverpoint pbhaSet {
    option.auto_bin_max = 0;
    bins set = {1'b1};
  }
endgroup

covergroup topMteCg with function sample(bit tagSet);
  mteCp: coverpoint tagSet {
    option.auto_bin_max = 0;
    bins set = {1'b1};
  }
endgroup

// Which snoops the interconnect chose to send, which is the one part of
// its coherence behaviour no requester-side stimulus can ask for directly.
// A read that finds the line uncached snoops nobody; the same read with
// another node holding the line produces a snoop whose type is the
// interconnect's decision. Forwarding snoops appear only when DCT is on,
// but they are in the same group because the enable does not remove them
// from the DUT: a forwarding snoop arriving with dctEn clear is a finding,
// not an unreachable bin. [SPEC:IHI0050H B4.7 Snoop request types]
covergroup topSnoopCg with function sample(
  chiSnpOpcodeE opcode,
  chiNodeClassE nodeClass
);
  snpOpcodeCp: coverpoint opcode {
    option.auto_bin_max = 0;
    bins snpShared = {SNP_SHARED};
    bins snpClean = {SNP_CLEAN};
    bins snpOnce = {SNP_ONCE};
    bins snpNotSharedDirty = {SNP_NOT_SHARED_DIRTY};
    bins snpUnique = {SNP_UNIQUE};
    bins snpCleanShared = {SNP_CLEAN_SHARED};
    bins snpCleanInvalid = {SNP_CLEAN_INVALID};
    bins snpMakeInvalid = {SNP_MAKE_INVALID};
    bins snpDvmOp = {SNP_DVM_OP};
    bins snpStashShared = {SNP_STASH_SHARED};
    bins snpStashUnique = {SNP_STASH_UNIQUE};
    bins snpSharedFwd = {SNP_SHARED_FWD};
    bins snpCleanFwd = {SNP_CLEAN_FWD};
    bins snpOnceFwd = {SNP_ONCE_FWD};
    bins snpNotSharedDirtyFwd = {SNP_NOT_SHARED_DIRTY_FWD};
    bins snpUniqueFwd = {SNP_UNIQUE_FWD};
  }
  snpClassCp: coverpoint nodeClass {
    option.auto_bin_max = 0;
    bins rnf = {RN_F};
    bins rnd = {RN_D};
    bins rni = {RN_I};
  }
  // A non-DVM snoop to RN-D or RN-I would be a finding rather than a hole,
  // so the cross keeps those bins rather than ignoring them.
  snpOpcodeClassCx: cross snpOpcodeCp, snpClassCp;
endgroup

// How transactions ended at the Requester, which is where an error has to
// arrive to have been delivered. Sampled from completions only, so an
// L-Credit return or a snoop response does not dilute the RespErr bins.
// [SPEC:IHI0050H B9.4 Error response]
covergroup topCompletionCg with function sample(
  chiRspOpcodeE opcode,
  chiRespErrE respErr
);
  compOpcodeCp: coverpoint opcode {
    option.auto_bin_max = 0;
    bins comp = {RSP_COMP};
    bins compDbidResp = {RSP_COMP_DBID_RESP};
    bins dbidResp = {RSP_DBID_RESP};
    bins dbidRespOrd = {RSP_DBID_RESP_ORD};
    bins readReceipt = {RSP_READ_RECEIPT};
    bins respSepData = {RSP_RESP_SEP_DATA};
    bins compCmo = {RSP_COMP_CMO};
    bins persist = {RSP_PERSIST};
    bins compPersist = {RSP_COMP_PERSIST};
    bins retryAck = {RSP_RETRY_ACK};
    bins pCrdGrant = {RSP_P_CRD_GRANT};
    bins stashDone = {RSP_STASH_DONE};
    bins compStashDone = {RSP_COMP_STASH_DONE};
    bins tagMatch = {RSP_TAG_MATCH};
  }
  respErrCp: coverpoint respErr {
    option.auto_bin_max = 0;
    bins ok = {RESP_ERR_OK};
    bins exok = {RESP_ERR_EXOK};
    bins derr = {RESP_ERR_DERR};
    bins nderr = {RESP_ERR_NDERR};
  }
  compErrCx: cross compOpcodeCp, respErrCp {
    // RetryAck, PCrdGrant and ReadReceipt carry no completion status.
    ignore_bins noStatus = binsof(compOpcodeCp) intersect {
      RSP_RETRY_ACK, RSP_P_CRD_GRANT, RSP_READ_RECEIPT}
      && binsof(respErrCp) intersect {RESP_ERR_EXOK, RESP_ERR_DERR, RESP_ERR_NDERR};
  }
endgroup

// Read data arriving at a Requester, crossed with the error status,
// because a data error is reported on the data beat rather than on a
// response flit. [SPEC:IHI0050H B9.4]
covergroup topReadDataCg with function sample(
  chiDatOpcodeE opcode,
  chiRespErrE respErr
);
  datOpcodeCp: coverpoint opcode {
    option.auto_bin_max = 0;
    bins compData = {DAT_COMP_DATA};
    bins dataSepResp = {DAT_DATA_SEP_RESP};
  }
  datErrCp: coverpoint respErr {
    option.auto_bin_max = 0;
    bins ok = {RESP_ERR_OK};
    bins exok = {RESP_ERR_EXOK};
    bins derr = {RESP_ERR_DERR};
    bins nderr = {RESP_ERR_NDERR};
  }
  datErrCx: cross datOpcodeCp, datErrCp;
endgroup

class topCoverage extends uvm_component;
  topIssueCg issueCg;
  topAtomicCg atomicCg;
  topDvmCg dvmCg;
  topStashCg stashCg;
  topExclCg exclCg;
  topMpamCg mpamCg;
  topPbhaCg pbhaCg;
  topMteCg mteCg;
  topSnoopCg snoopCg;
  topCompletionCg completionCg;
  topReadDataCg readDataCg;

  `uvm_component_utils(topCoverage)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    issueCg = new();
    snoopCg = new();
    completionCg = new();
    readDataCg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (CHI_CFG.atomicEn)
      atomicCg = new();
    if (CHI_CFG.dvmEn)
      dvmCg = new();
    if (CHI_CFG.stashEn)
      stashCg = new();
    if (CHI_CFG.exclEn)
      exclCg = new();
    if (CHI_CFG.mpamEn)
      mpamCg = new();
    if (CHI_CFG.pbhaEn)
      pbhaCg = new();
    if (CHI_CFG.mteEn)
      mteCg = new();
  endfunction

  function bit chiIsAtomicOp(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR,
      REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN,
      REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_LOAD_UMIN,
      REQ_ATOMIC_STORE_ADD, REQ_ATOMIC_STORE_CLR, REQ_ATOMIC_STORE_EOR,
      REQ_ATOMIC_STORE_SET, REQ_ATOMIC_STORE_SMAX, REQ_ATOMIC_STORE_SMIN,
      REQ_ATOMIC_STORE_UMAX, REQ_ATOMIC_STORE_UMIN,
      REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function void chiSampleReq(
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiReqFlitT flit
  );
    bit sampleHere;
    if (flit.opcode == REQ_LCRD_RETURN)
      return;
    sampleHere = (nodeClassIsRequester(nodeClass) && isTx)
      || (!nodeClassIsRequester(nodeClass) && !isTx);
    if (!sampleHere)
      return;
    if (chiIsAtomicOp(flit.opcode)) begin
      if (atomicCg != null)
        atomicCg.sample(flit.opcode);
    end else
      issueCg.sample(flit.opcode, nodeClass);
    if ((dvmCg != null) && (flit.opcode == REQ_DVM_OP))
      dvmCg.sample(flit.opcode);
    if ((stashCg != null) && (flit.opcode == REQ_STASH_ONCE_SHARED))
      stashCg.sample(flit.opcode);
    if ((exclCg != null) && flit.excl)
      exclCg.sample(flit.excl);
    if ((mpamCg != null) && (flit.mpam != '0))
      mpamCg.sample(1'b1);
    if ((pbhaCg != null) && (flit.pbha != '0))
      pbhaCg.sample(1'b1);
    if ((mteCg != null) && (flit.tagOp != '0))
      mteCg.sample(1'b1);
  endfunction

  // Snoops are sampled where they arrive, which is the only place they can
  // be seen: the testbench never asks for one.
  function void chiSampleSnp(
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiSnpFlitT flit
  );
    if (!nodeClassIsRequester(nodeClass) || isTx)
      return;
    if (flit.opcode == SNP_LCRD_RETURN)
      return;
    snoopCg.sample(flit.opcode, nodeClass);
  endfunction

  function void chiSampleRsp(
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiRspFlitT flit
  );
    if (!nodeClassIsRequester(nodeClass) || isTx)
      return;
    if (flit.opcode inside {RSP_LCRD_RETURN, RSP_SNP_RESP, RSP_SNP_RESP_FWDED,
                            RSP_COMP_ACK})
      return;
    completionCg.sample(flit.opcode, flit.respErr);
  endfunction

  function void chiSampleDat(
    input chiNodeClassE nodeClass,
    input bit isTx,
    input chiDatFlitT flit
  );
    if (!nodeClassIsRequester(nodeClass) || isTx)
      return;
    if (!(flit.opcode inside {DAT_COMP_DATA, DAT_DATA_SEP_RESP}))
      return;
    readDataCg.sample(flit.opcode, flit.respErr);
  endfunction
endclass
