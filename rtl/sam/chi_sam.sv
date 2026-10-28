// System Address Map: ordered region table, first match wins.
//
// Each region names the PASs allowed to access it (IHI 0050H B2.8.2, Table
// B13.47). A request whose PAS the first matching region does not allow, or
// that the configuration does not support at all, is refused with pasError;
// the lookup does not fall through to a lower-priority region, and the target
// stays that region's Home so the Home can complete the request with NDERR
// (IHI 0050H B9.1.1). An address no region maps raises unmappedError and,
// when the SAM hashes, still names the HN-F the hash picks, so that Home can
// complete it.
module chi_sam #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_REGIONS = 4,
  parameter bit HASH_TO_HNF = 1'b1,
  parameter int unsigned NUM_HNF = CFG.numHnf,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    HN_NODE_IDS [NUM_HNF-1:0] = '{default:'0},
  parameter logic [CFG.addrW-1:0]
    REGION_BASE [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [CFG.addrW-1:0]
    REGION_LIMIT [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]
    REGION_TARGET [NUM_REGIONS-1:0] = '{default:'0},
  // See CHI_SAM_ATTR_W in chi_cfg_pkg.
  parameter logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0]
    REGION_ATTRIBUTES [NUM_REGIONS-1:0] = '{default:'0}
) (
  input  logic clk,
  input  logic resetn,
  input  logic [CFG.addrW-1:0] address,
  input  chi_pkg::chi_pas_e pas,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] targetNodeId,
  output logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] matchedAttributes,
  output logic unmappedError,
  output logic pasError,

  input logic regionUpdate,
  input logic [chi_pkg::clog2Min1(NUM_REGIONS)-1:0] regionUpdateIndex,
  input logic [CFG.addrW-1:0] regionUpdateBase,
  input logic [CFG.addrW-1:0] regionUpdateLimit,
  input logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] regionUpdateTarget,
  input logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] regionUpdateAttributes
);
  logic [CFG.addrW-1:0] activeBase [NUM_REGIONS-1:0];
  logic [CFG.addrW-1:0] activeLimit [NUM_REGIONS-1:0];
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] activeTarget [NUM_REGIONS-1:0];
  logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] activeAttributes [NUM_REGIONS-1:0];
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] hashedTarget;
  logic addressMatched;
  // Packed copies of the table for the bound assertions; binding an unpacked
  // array port is not portable across simulators.
  logic [NUM_REGIONS-1:0][CFG.addrW-1:0] activeBasePacked;
  logic [NUM_REGIONS-1:0][CFG.addrW-1:0] activeLimitPacked;
  logic [NUM_REGIONS-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] activeTargetPacked;
  logic [NUM_REGIONS-1:0][chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] activeAttributesPacked;

  always_comb begin
    for (int unsigned region = 0; region < NUM_REGIONS; region++) begin
      activeBasePacked[region] = activeBase[region];
      activeLimitPacked[region] = activeLimit[region];
      activeTargetPacked[region] = activeTarget[region];
      activeAttributesPacked[region] = activeAttributes[region];
    end
  end

  chi_hn_hash #(
    .CFG(CFG),
    .NUM_HNF(NUM_HNF),
    .HN_NODE_IDS(HN_NODE_IDS),
    .INTERLEAVE_GRANULE(CFG.interleaveGranule),
    .HN_HASH_SHIFT(CFG.hnHashShift)
  ) hash (
    .address(address),
    .targetNodeId(hashedTarget)
  );

  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned region = 0; region < NUM_REGIONS; region++) begin
        activeBase[region] <= REGION_BASE[region];
        activeLimit[region] <= REGION_LIMIT[region];
        activeTarget[region] <= REGION_TARGET[region];
        activeAttributes[region] <= REGION_ATTRIBUTES[region];
      end
    end else if (regionUpdate) begin
      activeBase[regionUpdateIndex] <= regionUpdateBase;
      activeLimit[regionUpdateIndex] <= regionUpdateLimit;
      activeTarget[regionUpdateIndex] <= regionUpdateTarget;
      activeAttributes[regionUpdateIndex] <= regionUpdateAttributes;
    end
  end

  always_comb begin
    logic [7:0] allowed;
    targetNodeId = HASH_TO_HNF ? hashedTarget : '0;
    matchedAttributes = '0;
    unmappedError = 1'b1;
    pasError = 1'b0;
    addressMatched = 1'b0;

    // Ascending table order gives deterministic first-match priority. A PAS
    // refusal does not fall through to a lower-priority overlap.
    for (int unsigned region = 0; region < NUM_REGIONS; region++) begin
      if (!addressMatched
          && activeAttributes[region][0]
          && (address >= activeBase[region])
          && (address <= activeLimit[region])) begin
        addressMatched = 1'b1;
        unmappedError = 1'b0;
        matchedAttributes = activeAttributes[region];
        allowed = chi_cfg_pkg::samAllowedPas(activeAttributes[region])
                  & chi_pkg::pasLegalMask(CFG);
        pasError = !allowed[pas];
        if (HASH_TO_HNF
            && (activeAttributes[region][3:2]
                == chi_cfg_pkg::SAM_REGION_HNF_HASH))
          targetNodeId = hashedTarget;
        else
          targetNodeId = activeTarget[region];
      end
    end
  end
endmodule
