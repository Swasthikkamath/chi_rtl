// Physical Address Space assertions (IHI 0050H B2.8.2, Table B13.47).
//
// chi_sam_pas_sva, bound to every chi_sam:
//   SAM_PAS_REFUSAL_KEEPS_REGION  a request refused for its PAS is not
//       passed to a lower-priority region: the target stays the first
//       matching region's Home, so that Home completes it with NDERR.
//   SAM_ACCEPTED_PAS_ALLOWED  an accepted request's PAS is one the first
//       matching region and the configuration allow.
//
// chi_hnf_pas_sva, bound to chi_hnf_top:
//   SNOOP_PAS_PRESERVED  a snoop carries the PAS of the location its owner
//       holds.
//   DOWNSTREAM_PAS_PRESERVED  a request to the SN-F carries the PAS of the
//       location its owner holds.
//
// chi_sf_pas_sva, bound to chi_snoop_filter:
//   SF_ONE_WAY_PER_LOCATION  an update never leaves two valid ways for one
//       {line, PAS}.
//
// Covers: a PAS refusal, an alias of another PAS evicted for a
// physical-aliasing CMO, a forwarded CleanInvalidPoPA, a refused request
// completed by the HN-F.
module chi_sam_pas_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_REGIONS = 1,
  parameter bit HASH_TO_HNF = 1'b1
) (
  input logic clk,
  input logic resetn,
  input logic [CFG.addrW-1:0] address,
  input chi_pkg::chi_pas_e pas,
  input logic [NUM_REGIONS-1:0][CFG.addrW-1:0] activeBase,
  input logic [NUM_REGIONS-1:0][CFG.addrW-1:0] activeLimit,
  input logic [NUM_REGIONS-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] activeTarget,
  input logic [NUM_REGIONS-1:0][chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] activeAttributes,
  input logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] hashedTarget,
  input logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] targetNodeId,
  input logic unmappedError,
  input logic pasError
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  logic matched;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] firstTarget;
  logic [7:0] firstAllowed;

  always_comb begin
    matched = 1'b0;
    firstTarget = '0;
    firstAllowed = '0;
    for (int unsigned region = 0; region < NUM_REGIONS; region++)
      if (!matched && activeAttributes[region][0]
          && (address >= activeBase[region])
          && (address <= activeLimit[region])) begin
        matched = 1'b1;
        firstAllowed = samAllowedPas(activeAttributes[region])
                       & pasLegalMask(CFG);
        firstTarget = (HASH_TO_HNF
                       && (activeAttributes[region][3:2] == SAM_REGION_HNF_HASH))
                      ? hashedTarget : activeTarget[region];
      end
  end

  SAM_PAS_REFUSAL_KEEPS_REGION: assert property (
    @(posedge clk) disable iff (!resetn)
    pasError |-> matched && !unmappedError && (targetNodeId == firstTarget));

  SAM_ACCEPTED_PAS_ALLOWED: assert property (
    @(posedge clk) disable iff (!resetn)
    !unmappedError && !pasError |-> firstAllowed[pas]);

  SAM_PAS_REFUSED: cover property (
    @(posedge clk) disable iff (!resetn)
    pasError);
endmodule

module chi_hnf_pas_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_OWNERS = 1,
  parameter int unsigned KEY_W = 1,
  parameter int unsigned LINE_W = 1
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_OWNERS-1:0][KEY_W-1:0] ownerKey,
  input logic snpOutValid,
  input chi_pkg::chi_noc_flit_t snpOutFlit,
  input logic reqOutValid,
  input chi_pkg::chi_noc_flit_t reqOutFlit,
  input logic sfAliasEvict,
  input logic sfUpdateReady,
  input logic posAllocValid,
  input chi_pkg::chi_noc_flit_t reqInFlit
);
  import chi_pkg::*;

  chi_snp_flit_t snoop;
  chi_req_flit_t downstream;

  always_comb begin
    snoop = unpackSnpFlit(CFG, snpOutFlit.payload[CHI_MAX_SNP_FLIT_W-1:0]);
    downstream = unpackReqFlit(CFG, reqOutFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
  end

  SNOOP_PAS_PRESERVED: assert property (
    @(posedge clk) disable iff (!resetn)
    snpOutValid && (int'(snoop.txnId) < NUM_OWNERS)
      |-> (snoop.pas == chi_pas_e'(ownerKey[snoop.txnId][KEY_W-1:LINE_W])));

  DOWNSTREAM_PAS_PRESERVED: assert property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid && (downstream.opcode != REQ_PCRD_RETURN)
    && (int'(downstream.txnId) < NUM_OWNERS)
      |-> (downstream.pas
           == chi_pas_e'(ownerKey[downstream.txnId][KEY_W-1:LINE_W])));

  PAS_ALIAS_EVICTED: cover property (
    @(posedge clk) disable iff (!resetn)
    sfAliasEvict && sfUpdateReady);

  POPA_FORWARDED: cover property (
    @(posedge clk) disable iff (!resetn)
    reqOutValid && (downstream.opcode == REQ_CLEAN_INVALID_POPA));

  REFUSED_REQUEST_ALLOCATED: cover property (
    @(posedge clk) disable iff (!resetn)
    posAllocValid && (reqInFlit.decodeErr != NOC_ERR_NONE));
endmodule

module chi_sf_pas_sva (
  input logic clk,
  input logic resetn,
  input logic updateValid,
  input logic updateReady,
  input logic writeWay,
  input logic removeLocation,
  input logic updateDuplicate
);
  SF_ONE_WAY_PER_LOCATION: assert property (
    @(posedge clk) disable iff (!resetn)
    updateValid && updateReady && writeWay && !removeLocation
      |-> !updateDuplicate);
endmodule

bind chi_sam chi_sam_pas_sva #(
  .CFG(CFG),
  .NUM_REGIONS(NUM_REGIONS),
  .HASH_TO_HNF(HASH_TO_HNF)
) chi_sam_pas_assertions (
  .clk(clk),
  .resetn(resetn),
  .address(address),
  .pas(pas),
  .activeBase(activeBasePacked),
  .activeLimit(activeLimitPacked),
  .activeTarget(activeTargetPacked),
  .activeAttributes(activeAttributesPacked),
  .hashedTarget(hashedTarget),
  .targetNodeId(targetNodeId),
  .unmappedError(unmappedError),
  .pasError(pasError)
);

bind chi_hnf_top chi_hnf_pas_sva #(
  .CFG(CFG),
  .NUM_OWNERS(NUM_OWNERS),
  .KEY_W(KEY_W),
  .LINE_W(LINE_W)
) chi_hnf_pas_assertions (
  .clk(clk),
  .resetn(resetn),
  .ownerKey(ownerKey),
  .snpOutValid(snpOutValid),
  .snpOutFlit(snpOutFlit),
  .reqOutValid(reqOutValid),
  .reqOutFlit(reqOutFlit),
  .sfAliasEvict(sfAliasEvict),
  .sfUpdateReady(sfUpdateReady),
  .posAllocValid(posAllocValid),
  .reqInFlit(reqInFlit)
);

bind chi_snoop_filter chi_sf_pas_sva chi_sf_pas_assertions (
  .clk(clk),
  .resetn(resetn),
  .updateValid(updateValid),
  .updateReady(updateReady),
  .writeWay(writeWay),
  .removeLocation(removeLocation),
  .updateDuplicate(updateDuplicate)
);
