// Cache stashing decode for a Home Node (IHI 0050H B7).
//
// Two request forms are decoded. A write with stash hint
// (WriteUniqueFullStash, WriteUniquePtlStash) carries the data with the hint,
// so the Home snoops the stash target with SnpUniqueStash or
// SnpMakeInvalidStash while the peers receive the ordinary invalidating
// snoop. An independent stash request (StashOnce*, StashOnceSep*) carries no
// data, so the Home only hints the target with SnpStashUnique or
// SnpStashShared. A stash target that answers with Data Pull turns the hint
// into an implied read that the Home performs on the target's behalf
// (IHI 0050H B7.1.1).
//
// Stashing is only a hint: every output here may be ignored without breaking
// the protocol, and a request whose StashNIDValid is deasserted has no target
// to snoop at all (IHI 0050H B7.4.2).
module chi_stash_ctrl #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_RNF = (CFG.numRnf > 0) ? CFG.numRnf : 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    RNF_NODE_IDS [NUM_RNF] = '{default:'0}
) (
  input  chi_pkg::chi_req_opcode_e requestOpcode,
  input  logic requestStashNidValid,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requestStashNid,
  input  logic [chi_cfg_pkg::CHI_RTNTXNID_SLOT_W-1:0] requestStashLpidSlot,
  input  logic homeHasLatestCopy,
  output logic isStash,
  output logic isIndependentStash,
  output logic isSeparateStashDone,
  output logic isUniqueStash,
  output logic targetValid,
  output logic [NUM_RNF-1:0] targetMask,
  output chi_pkg::chi_snp_opcode_e targetSnoopOpcode,
  output logic stashLpidValid,
  output logic [chi_cfg_pkg::CHI_MAX_LPID_W-1:0] stashLpid,
  output chi_pkg::chi_req_opcode_e dataPullOpcode,
  output chi_pkg::chi_resp_e dataPullResp
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  // The 12-bit ReturnTxnID slot carries {6'b0, StashLPIDValid, StashLPID} in
  // a stash request (IHI 0050H Table B13.6).
  localparam int unsigned STASH_LPID_VALID_BIT = CHI_MAX_LPID_W;

  logic writeStash;
  logic fullLineStash;

  always_comb begin
    writeStash = CFG.stashEn
                 && ((requestOpcode == REQ_WRITE_UNIQUE_FULL_STASH)
                     || (requestOpcode == REQ_WRITE_UNIQUE_PTL_STASH));
    fullLineStash = (requestOpcode == REQ_WRITE_UNIQUE_FULL_STASH);
    isIndependentStash = CFG.stashEn
                         && (requestOpcode inside {
                           REQ_STASH_ONCE_SHARED, REQ_STASH_ONCE_UNIQUE,
                           REQ_STASH_ONCE_SEP_SHARED, REQ_STASH_ONCE_SEP_UNIQUE
                         });
    isStash = writeStash || isIndependentStash;
    isSeparateStashDone = CFG.stashEn
                          && (requestOpcode inside {
                            REQ_STASH_ONCE_SEP_SHARED,
                            REQ_STASH_ONCE_SEP_UNIQUE
                          });
    // A write with stash hint always installs a writeable copy.
    isUniqueStash = writeStash
                    || (requestOpcode == REQ_STASH_ONCE_UNIQUE)
                    || (requestOpcode == REQ_STASH_ONCE_SEP_UNIQUE);

    stashLpidValid = isStash && requestStashLpidSlot[STASH_LPID_VALID_BIT];
    stashLpid = requestStashLpidSlot[CHI_MAX_LPID_W-1:0];

    targetMask = '0;
    for (int unsigned i = 0; i < NUM_RNF; i++)
      if (requestStashNid == RNF_NODE_IDS[i])
        targetMask[i] = 1'b1;
    targetValid = isStash && requestStashNidValid && (targetMask != '0);
    if (!targetValid)
      targetMask = '0;

    // SnpMakeInvalidStash replaces SnpUniqueStash when the Home already holds
    // the line, because the target's copy is then redundant (IHI 0050H B7.2).
    if (writeStash)
      targetSnoopOpcode = (fullLineStash || homeHasLatestCopy)
                          ? SNP_MAKE_INVALID_STASH : SNP_UNIQUE_STASH;
    else
      targetSnoopOpcode = isUniqueStash ? SNP_STASH_UNIQUE : SNP_STASH_SHARED;

    // Table B7.2 fixes the read implied by a Data Pull response.
    dataPullOpcode = isUniqueStash ? REQ_READ_UNIQUE
                                   : REQ_READ_NOT_SHARED_DIRTY;
    dataPullResp = isUniqueStash ? RESP_UC_UD : RESP_SC;
  end
endmodule
