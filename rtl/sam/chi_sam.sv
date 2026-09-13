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
  // [0] valid, [1] secure-only, [3:2] chi_sam_region_kind_e.
  parameter logic [3:0]
    REGION_ATTRIBUTES [NUM_REGIONS-1:0] = '{default:'0}
) (
  input  logic clk,
  input  logic resetn,
  input  logic [CFG.addrW-1:0] address,
  input  logic nonSecure,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] targetNodeId,
  output logic [3:0] matchedAttributes,
  output logic unmappedError,

  input logic regionUpdate,
  input logic [chi_pkg::clog2Min1(NUM_REGIONS)-1:0] regionUpdateIndex,
  input logic [CFG.addrW-1:0] regionUpdateBase,
  input logic [CFG.addrW-1:0] regionUpdateLimit,
  input logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] regionUpdateTarget,
  input logic [3:0] regionUpdateAttributes
);
  logic [CFG.addrW-1:0] activeBase [NUM_REGIONS-1:0];
  logic [CFG.addrW-1:0] activeLimit [NUM_REGIONS-1:0];
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] activeTarget [NUM_REGIONS-1:0];
  logic [3:0] activeAttributes [NUM_REGIONS-1:0];
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] hashedTarget;
  logic addressMatched;

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
    targetNodeId = '0;
    matchedAttributes = '0;
    unmappedError = 1'b1;
    addressMatched = 1'b0;

    // Ascending table order gives deterministic first-match priority.  A
    // security rejection does not fall through to a lower-priority overlap.
    for (int unsigned region = 0; region < NUM_REGIONS; region++) begin
      if (!addressMatched
          && activeAttributes[region][0]
          && (address >= activeBase[region])
          && (address <= activeLimit[region])) begin
        addressMatched = 1'b1;
        matchedAttributes = activeAttributes[region];
        if (!(nonSecure && activeAttributes[region][1])) begin
          unmappedError = 1'b0;
          if (HASH_TO_HNF
              && (activeAttributes[region][3:2]
                  == chi_cfg_pkg::SAM_REGION_HNF_HASH))
            targetNodeId = hashedTarget;
          else
            targetNodeId = activeTarget[region];
        end
      end
    end
  end
endmodule
