module chi_hn_hash #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_HNF = CFG.numHnf,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    HN_NODE_IDS [NUM_HNF-1:0] = '{default:'0},
  parameter int unsigned INTERLEAVE_GRANULE = CFG.interleaveGranule,
  parameter int unsigned HN_HASH_SHIFT = CFG.hnHashShift
) (
  input  logic [CFG.addrW-1:0] address,
  output logic [CFG.nodeIdW-1:0] targetNodeId
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
  logic [CFG.addrW-1:0] hashValue;
  int unsigned hnfIndex;

  always_comb begin
    // Fold higher granule-number bits into the naturally striped low bits.
    // Constant modulo is intentional so every positive NUM_HNF is supported.
    granuleNumber = address >> GRANULE_SHIFT;
    hashValue = granuleNumber ^ (granuleNumber >> HN_HASH_SHIFT);
    hnfIndex = int'(hashValue % CFG.addrW'(NUM_HNF));
    targetNodeId = HN_NODE_IDS[hnfIndex][CFG.nodeIdW-1:0];
  end
endmodule
