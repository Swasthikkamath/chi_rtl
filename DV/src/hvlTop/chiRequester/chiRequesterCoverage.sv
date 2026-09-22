// Opcode and intent coverage for one requester. Bins for a disabled
// feature are a separate covergroup that is built only when the feature
// is on, so a disabled feature is absent from the model.
// [ASSUMPTION:15]
//
// The groups are package types, not embedded instances. An embedded
// covergroup is constructed with the class, so a disabled feature would
// still occupy the model. Optional groups are constructed in build_phase.

covergroup chiRequesterIssueCg with function sample(
  chiRequesterIntentE intent,
  chiReqOpcodeE opcode,
  chiNodeClassE nodeClass,
  chiCacheStateE state,
  logic [ORDER_W-1:0] order
);
  intentCp: coverpoint intent {
    bins readShared = {CHI_INTENT_READ_SHARED};
    bins readClean = {CHI_INTENT_READ_CLEAN};
    bins readOnce = {CHI_INTENT_READ_ONCE};
    bins readNoSnp = {CHI_INTENT_READ_NO_SNP};
    bins readUnique = {CHI_INTENT_READ_UNIQUE};
    bins cleanUnique = {CHI_INTENT_CLEAN_UNIQUE};
    bins makeUnique = {CHI_INTENT_MAKE_UNIQUE};
    bins evict = {CHI_INTENT_EVICT};
    bins writeBack = {CHI_INTENT_WRITE_BACK};
    bins writeClean = {CHI_INTENT_WRITE_CLEAN};
    bins writeUnique = {CHI_INTENT_WRITE_UNIQUE};
    bins writeNoSnp = {CHI_INTENT_WRITE_NO_SNP};
    bins writeUniqueZero = {CHI_INTENT_WRITE_UNIQUE_ZERO};
    bins writeNoSnpZero = {CHI_INTENT_WRITE_NO_SNP_ZERO};
    bins cleanShared = {CHI_INTENT_CLEAN_SHARED};
    bins cleanInvalid = {CHI_INTENT_CLEAN_INVALID};
    bins makeInvalid = {CHI_INTENT_MAKE_INVALID};
    bins prefetch = {CHI_INTENT_PREFETCH_TGT};
    bins pcrdReturn = {CHI_INTENT_PCRD_RETURN};
  }
  opcodeCp: coverpoint opcode {
    bins readShared = {REQ_READ_SHARED};
    bins readClean = {REQ_READ_CLEAN};
    bins readOnce = {REQ_READ_ONCE};
    bins readNoSnp = {REQ_READ_NO_SNP};
    bins readUnique = {REQ_READ_UNIQUE};
    bins cleanUnique = {REQ_CLEAN_UNIQUE};
    bins makeUnique = {REQ_MAKE_UNIQUE};
    bins evict = {REQ_EVICT};
    bins writeBack = {REQ_WRITE_BACK_FULL};
    bins writeClean = {REQ_WRITE_CLEAN_FULL};
    bins writeUniqueFull = {REQ_WRITE_UNIQUE_FULL};
    bins writeUniquePtl = {REQ_WRITE_UNIQUE_PTL};
    bins writeNoSnpFull = {REQ_WRITE_NO_SNP_FULL};
    bins writeNoSnpPtl = {REQ_WRITE_NO_SNP_PTL};
  }
  classCp: coverpoint nodeClass {
    bins rnf = {RN_F};
    bins rnd = {RN_D};
    bins rni = {RN_I};
  }
  stateCp: coverpoint state;
  orderCp: coverpoint order;
  intentClassCx: cross intentCp, classCp {
    ignore_bins rndCache = binsof(classCp) intersect {RN_D}
      && binsof(intentCp) intersect {
        CHI_INTENT_READ_SHARED, CHI_INTENT_READ_CLEAN, CHI_INTENT_READ_UNIQUE,
        CHI_INTENT_CLEAN_UNIQUE, CHI_INTENT_MAKE_UNIQUE, CHI_INTENT_EVICT,
        CHI_INTENT_WRITE_BACK, CHI_INTENT_WRITE_CLEAN, CHI_INTENT_PREFETCH_TGT
      };
    ignore_bins rniCache = binsof(classCp) intersect {RN_I}
      && binsof(intentCp) intersect {
        CHI_INTENT_READ_SHARED, CHI_INTENT_READ_CLEAN, CHI_INTENT_READ_ONCE,
        CHI_INTENT_READ_UNIQUE, CHI_INTENT_CLEAN_UNIQUE, CHI_INTENT_MAKE_UNIQUE,
        CHI_INTENT_EVICT, CHI_INTENT_WRITE_BACK, CHI_INTENT_WRITE_CLEAN,
        CHI_INTENT_WRITE_UNIQUE, CHI_INTENT_WRITE_UNIQUE_ZERO,
        CHI_INTENT_PREFETCH_TGT
      };
  }
  opcodeStateCx: cross opcodeCp, stateCp;
endgroup

covergroup chiRequesterAtomicCg with function sample(chiReqOpcodeE opcode);
  atomicCp: coverpoint opcode {
    bins loadAdd = {REQ_ATOMIC_LOAD_ADD};
    bins storeAdd = {REQ_ATOMIC_STORE_ADD};
    bins swap = {REQ_ATOMIC_SWAP};
    bins compare = {REQ_ATOMIC_COMPARE};
  }
endgroup

covergroup chiRequesterDvmCg with function sample(chiRequesterIntentE intent);
  dvmCp: coverpoint intent {
    bins dvm = {CHI_INTENT_DVM_OP};
  }
endgroup

covergroup chiRequesterStashCg with function sample(chiRequesterIntentE intent);
  stashCp: coverpoint intent {
    bins stash = {CHI_INTENT_STASH_ONCE};
  }
endgroup

covergroup chiRequesterExclCg with function sample(chiRequesterIntentE intent);
  exclCp: coverpoint intent {
    bins load = {CHI_INTENT_EXCLUSIVE_LOAD};
    bins store = {CHI_INTENT_EXCLUSIVE_STORE};
  }
endgroup

covergroup chiRequesterSnoopCg with function sample(
  chiSnpOpcodeE opcode,
  chiCacheStateE state
);
  snoopCp: coverpoint opcode {
    bins shared = {SNP_SHARED};
    bins clean = {SNP_CLEAN};
    bins once = {SNP_ONCE};
    bins snpUnique = {SNP_UNIQUE};
    bins makeInvalid = {SNP_MAKE_INVALID};
    bins cleanInvalid = {SNP_CLEAN_INVALID};
    bins cleanShared = {SNP_CLEAN_SHARED};
  }
  snoopStateCp: coverpoint state;
  snoopStateCx: cross snoopCp, snoopStateCp;
endgroup

class chiRequesterCoverage extends uvm_component;
  chiRequesterConfig cfg;
  chiRequesterIssueCg issueCg;
  chiRequesterAtomicCg atomicCg;
  chiRequesterDvmCg dvmCg;
  chiRequesterStashCg stashCg;
  chiRequesterExclCg exclCg;
  chiRequesterSnoopCg snoopCg;

  `uvm_component_utils(chiRequesterCoverage)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    issueCg = new();
    snoopCg = new();
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
  endfunction

  function void sampleIssue(chiRequesterTx item);
    if (!item.localOnly)
      issueCg.sample(item.intent, item.issuedOpcode, item.nodeClass,
        item.initialState, item.order);
    if (atomicCg != null && item.intent inside {
      CHI_INTENT_ATOMIC_LOAD, CHI_INTENT_ATOMIC_STORE,
      CHI_INTENT_ATOMIC_SWAP, CHI_INTENT_ATOMIC_COMPARE
    })
      atomicCg.sample(item.issuedOpcode);
    if (dvmCg != null && item.intent == CHI_INTENT_DVM_OP)
      dvmCg.sample(item.intent);
    if (stashCg != null && item.intent == CHI_INTENT_STASH_ONCE)
      stashCg.sample(item.intent);
    if (exclCg != null && item.intent inside {
      CHI_INTENT_EXCLUSIVE_LOAD, CHI_INTENT_EXCLUSIVE_STORE
    })
      exclCg.sample(item.intent);
  endfunction

  function void sampleSnoop(input chiSnpOpcodeE opcode, input chiCacheStateE state);
    if (opcode == SNP_DVM_OP)
      return;
    snoopCg.sample(opcode, state);
  endfunction
endclass
