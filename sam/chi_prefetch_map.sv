// Address to node identifier mapping for PrefetchTgt (IHI 0050H B3.3.1).
//
// PrefetchTgt uses a different address-to-node mapper from every other
// request and always targets a Subordinate Node, so two requests from the
// same Requester to the same address reach different nodes when one of them
// is a PrefetchTgt. This mapper therefore interleaves directly across the
// SN-F node identifiers instead of hashing to a Home Node.
module chi_prefetch_map #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_SNF = (CFG.numSnf > 0) ? CFG.numSnf : 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    SNF_NODE_IDS [NUM_SNF] = '{default:'0},
  parameter int unsigned INTERLEAVE_GRANULE = CFG.interleaveGranule
) (
  input  logic [CFG.addrW-1:0] address,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] targetNodeId
);
  function automatic int unsigned granuleShift(input int unsigned granule);
    int unsigned shift;
    shift = 0;
    while ((1 << shift) < granule)
      shift++;
    return shift;
  endfunction

  localparam int unsigned GRANULE_SHIFT = granuleShift(INTERLEAVE_GRANULE);

  logic [CFG.addrW-1:0] granuleNumber;
  int unsigned snfIndex;

  always_comb begin
    granuleNumber = address >> GRANULE_SHIFT;
    // Constant modulo is intentional so every positive NUM_SNF is supported.
    snfIndex = int'(granuleNumber % CFG.addrW'(NUM_SNF));
    targetNodeId = chi_cfg_pkg::CHI_NODEID_SLOT_W'(SNF_NODE_IDS[snfIndex]);
  end
endmodule
