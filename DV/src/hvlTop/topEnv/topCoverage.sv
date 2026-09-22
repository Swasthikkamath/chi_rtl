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

class topCoverage extends uvm_component;
  topIssueCg issueCg;
  topAtomicCg atomicCg;
  topDvmCg dvmCg;
  topStashCg stashCg;
  topExclCg exclCg;
  topMpamCg mpamCg;
  topPbhaCg pbhaCg;
  topMteCg mteCg;

  `uvm_component_utils(topCoverage)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    issueCg = new();
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
endclass
