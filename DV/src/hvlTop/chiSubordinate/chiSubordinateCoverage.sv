// Opcode coverage for one subordinate. Bins for atomics are a separate
// covergroup built only when atomicEn is set, so a disabled feature is
// absent from the model. The groups are package types: an embedded
// covergroup would be constructed with the class.
// [ASSUMPTION:15]
//
// Values outside the named bins are ignored, so an opcode this agent
// only completes to avoid a hang is not a hole.

covergroup chiSubordinateIssueCg with function sample(
  chiReqOpcodeE opcode,
  chiNodeClassE nodeClass
);
  opcodeCp: coverpoint opcode {
    option.auto_bin_max = 0;
    bins readNoSnp = {REQ_READ_NO_SNP};
    bins readNoSnpSep = {REQ_READ_NO_SNP_SEP};
    bins writeNoSnpFull = {REQ_WRITE_NO_SNP_FULL};
    bins writeNoSnpPtl = {REQ_WRITE_NO_SNP_PTL};
    bins writeNoSnpZero = {REQ_WRITE_NO_SNP_ZERO};
    bins writeUniqueFull = {REQ_WRITE_UNIQUE_FULL};
    bins writeUniquePtl = {REQ_WRITE_UNIQUE_PTL};
    bins writeUniqueZero = {REQ_WRITE_UNIQUE_ZERO};
    bins pcrdReturn = {REQ_P_CRD_RETURN};
    bins prefetchTgt = {REQ_PREFETCH_TGT};
    bins cleanShared = {REQ_CLEAN_SHARED};
    bins cleanInvalid = {REQ_CLEAN_INVALID};
    bins makeInvalid = {REQ_MAKE_INVALID};
  }
  classCp: coverpoint nodeClass {
    option.auto_bin_max = 0;
    bins snf = {SN_F};
    bins sni = {SN_I};
  }
  opcodeClassCx: cross opcodeCp, classCp {
    ignore_bins sniUnique = binsof(classCp) intersect {SN_I}
      && binsof(opcodeCp) intersect {
        REQ_WRITE_UNIQUE_FULL, REQ_WRITE_UNIQUE_PTL, REQ_WRITE_UNIQUE_ZERO,
        REQ_PREFETCH_TGT
      };
  }
endgroup

covergroup chiSubordinateAtomicCg with function sample(chiReqOpcodeE opcode);
  atomicCp: coverpoint opcode {
    option.auto_bin_max = 0;
    bins loadAdd = {REQ_ATOMIC_LOAD_ADD};
    bins storeAdd = {REQ_ATOMIC_STORE_ADD};
    bins swap = {REQ_ATOMIC_SWAP};
    bins compare = {REQ_ATOMIC_COMPARE};
  }
endgroup

class chiSubordinateCoverage extends uvm_component;
  chiSubordinateConfig cfg;
  chiSubordinateIssueCg issueCg;
  chiSubordinateAtomicCg atomicCg;

  `uvm_component_utils(chiSubordinateCoverage)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    issueCg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (CHI_CFG.atomicEn)
      atomicCg = new();
  endfunction

  function void sampleIssue(input chiReqOpcodeE opcode, input chiNodeClassE nodeClass);
    issueCg.sample(opcode, nodeClass);
  endfunction

  function void sampleAtomic(input chiReqOpcodeE opcode);
    if (atomicCg != null)
      atomicCg.sample(opcode);
  endfunction
endclass
