//==============================================================================
// chiGlobalsPkg
//
// Why this package exists, and why it is shaped this way:
//
// 1. Single configuration source. Both tops need the same CHI configuration,
//    the same NodeID table, the same placement table and the same address
//    regions. If each side computed them, a sweep would silently desynchronise
//    the stimulus from the DUT parameterization. So exactly one function
//    resolves the configuration (CHI_CFG_DEFAULT, then +define+CHI_TB_*
//    overrides) and everything else in the testbench derives from it.
//
// 2. Testbench-owned protocol model. The flit structs, opcode encodings and
//    pack/unpack functions here are the testbench's own reading of the CHI
//    specification. The DUT's chi_pkg is deliberately NOT imported, so that a
//    disagreement between this model and the DUT shows up as a finding rather
//    than being defined away. Only chi_cfg_pkg is imported, because the top
//    module's CFG parameter has a type that lives there [TOP:CFG].
//
// 3. UVM-free. Both hdlTop and hvlTop import this package, and hdlTop must
//    elaborate with no test running, so this file contains nothing but
//    parameters, typedefs, structs and pure functions.
//
// 4. Widths are formulas, not literals. Each flit width is written as an
//    arithmetic function of the configuration fields, so a swept
//    configuration resizes the model instead of breaking it. The formulas are
//    fitted to the DUT's boundary bus widths, which is legitimate black-box
//    information: the flit buses are on the DUT's own interface. Field
//    ORDER inside a flit is not observable that way and remains this
//    package's own spec-derived reading. See OPEN QUESTIONS Q7 and Q22.
//
// [SPEC:IHI0050H B13 Flit definitions and link handling]
//==============================================================================

package chiGlobalsPkg;

  import chi_cfg_pkg::*;

  //----------------------------------------------------------------------------
  // 1. Configuration resolution
  //
  // Start from the DUT's own default so that an unswept run matches the
  // configuration the design was written for, then apply command-line
  // overrides. Only fields that the top module itself references are
  // overridable here, plus the four DAT-shaping fields recorded in
  // OPEN QUESTIONS Q15, which the flit model cannot be built without.
  //----------------------------------------------------------------------------

  function automatic chi_cfg_pkg::chi_cfg_t buildChiCfg();
    chi_cfg_pkg::chi_cfg_t cfg;
    cfg = chi_cfg_pkg::CHI_CFG_DEFAULT;                     // [TOP:CFG]
`ifdef CHI_TB_NUM_RNF
    cfg.numRnf = `CHI_TB_NUM_RNF;
`endif
`ifdef CHI_TB_NUM_RND
    cfg.numRnd = `CHI_TB_NUM_RND;
`endif
`ifdef CHI_TB_NUM_RNI
    cfg.numRni = `CHI_TB_NUM_RNI;
`endif
`ifdef CHI_TB_NUM_SNF
    cfg.numSnf = `CHI_TB_NUM_SNF;
`endif
`ifdef CHI_TB_NUM_SNI
    cfg.numSni = `CHI_TB_NUM_SNI;
`endif
`ifdef CHI_TB_NUM_HNF
    cfg.numHnf = `CHI_TB_NUM_HNF;
`endif
`ifdef CHI_TB_NUM_HNI
    cfg.numHni = `CHI_TB_NUM_HNI;
`endif
`ifdef CHI_TB_NUM_MN
    cfg.numMn = `CHI_TB_NUM_MN;
`endif
`ifdef CHI_TB_ADDR_W
    cfg.addrW = `CHI_TB_ADDR_W;
`endif
`ifdef CHI_TB_DATA_W
    cfg.dataW = `CHI_TB_DATA_W;
`endif
`ifdef CHI_TB_NODEID_W
    cfg.nodeIdW = `CHI_TB_NODEID_W;
`endif
`ifdef CHI_TB_TXNID_W
    cfg.txnIdW = `CHI_TB_TXNID_W;
`endif
`ifdef CHI_TB_LPID_W
    cfg.lpidW = `CHI_TB_LPID_W;
`endif
`ifdef CHI_TB_CCID_W
    cfg.ccidW = `CHI_TB_CCID_W;
`endif
`ifdef CHI_TB_GROUPID_W
    cfg.groupIdW = `CHI_TB_GROUPID_W;
`endif
`ifdef CHI_TB_RSVDC_W
    cfg.rsvdcW = `CHI_TB_RSVDC_W;
`endif
`ifdef CHI_TB_MPAM_W
    cfg.mpamW = `CHI_TB_MPAM_W;
`endif
`ifdef CHI_TB_MPAM_EN
    cfg.mpamEn = `CHI_TB_MPAM_EN;
`endif
`ifdef CHI_TB_MEC_EN
    cfg.mecEn = `CHI_TB_MEC_EN;
`endif
`ifdef CHI_TB_CDA_EN
    cfg.cdaEn = `CHI_TB_CDA_EN;
`endif
`ifdef CHI_TB_DCT_EN
    cfg.dctEn = `CHI_TB_DCT_EN;
`endif
`ifdef CHI_TB_DMT_EN
    cfg.dmtEn = `CHI_TB_DMT_EN;
`endif
`ifdef CHI_TB_DWT_EN
    cfg.dwtEn = `CHI_TB_DWT_EN;
`endif
`ifdef CHI_TB_ATOMIC_EN
    cfg.atomicEn = `CHI_TB_ATOMIC_EN;
`endif
`ifdef CHI_TB_STASH_EN
    cfg.stashEn = `CHI_TB_STASH_EN;
`endif
`ifdef CHI_TB_DVM_EN
    cfg.dvmEn = `CHI_TB_DVM_EN;
`endif
`ifdef CHI_TB_EXCL_EN
    cfg.exclEn = `CHI_TB_EXCL_EN;
`endif
`ifdef CHI_TB_LCRD_DEPTH
    cfg.lcrdDepth = `CHI_TB_LCRD_DEPTH;
`endif
`ifdef CHI_TB_POS_ENTRIES
    cfg.posEntries = `CHI_TB_POS_ENTRIES;
`endif
`ifdef CHI_TB_EXCL_MONITORS
    cfg.exclMonitors = `CHI_TB_EXCL_MONITORS;
`endif
`ifdef CHI_TB_INTERLEAVE_GRANULE
    cfg.interleaveGranule = `CHI_TB_INTERLEAVE_GRANULE;
`endif
`ifdef CHI_TB_SNP_FILTER_ENTRIES
    cfg.snpFilterEntries = `CHI_TB_SNP_FILTER_ENTRIES;
`endif
`ifdef CHI_TB_SNP_FILTER_WAYS
    cfg.snpFilterWays = `CHI_TB_SNP_FILTER_WAYS;
`endif
`ifdef CHI_TB_TOPOLOGY
    cfg.topology = `CHI_TB_TOPOLOGY;
`endif
`ifdef CHI_TB_MESH_X
    cfg.meshX = `CHI_TB_MESH_X;
`endif
`ifdef CHI_TB_MESH_Y
    cfg.meshY = `CHI_TB_MESH_Y;
`endif
`ifdef CHI_TB_DEV_PORTS_PER_XP
    cfg.numDevPortsPerXp = `CHI_TB_DEV_PORTS_PER_XP;
`endif
`ifdef CHI_TB_CFG_ACCESS
    cfg.cfgAccess = `CHI_TB_CFG_ACCESS;
`endif
    // DAT-shaping fields. These are chi_cfg_t members that the top module does
    // not reference, so INPUT ISOLATION would exclude them, but DataCheck and
    // Poison change the DAT flit width and the model cannot be built without
    // them. Each read is isolated here so that a single edit retargets it.
    // See OPEN QUESTIONS Q15.
`ifdef CHI_TB_DATA_CHECK_EN
    cfg.dataCheckEn = `CHI_TB_DATA_CHECK_EN;
`endif
`ifdef CHI_TB_POISON_EN
    cfg.poisonEn = `CHI_TB_POISON_EN;
`endif
`ifdef CHI_TB_PARITY_EN
    cfg.parityEn = `CHI_TB_PARITY_EN;
`endif
`ifdef CHI_TB_MTE_EN
    cfg.mteEn = `CHI_TB_MTE_EN;
`endif
`ifdef CHI_TB_PBHA_EN
    cfg.pbhaEn = `CHI_TB_PBHA_EN;
`endif
    return cfg;
  endfunction

  localparam chi_cfg_pkg::chi_cfg_t CHI_CFG = buildChiCfg();

  //----------------------------------------------------------------------------
  // 2. Derived counts, node ordinals and interface array sizes
  //
  // The node ordinal order and the OFF_* offsets mirror the top module exactly
  // [TOP:OFF_RNF..OFF_MN], because linkUp, linkParityError and linkCreditError
  // are indexed by ordinal and the scoreboard has to index them the same way.
  // The *_IF sizes carry the top module's max(count,1) sentinel so that a
  // configured-out node class still has a one-element interface array with no
  // agent behind it [TOP:ports].
  //----------------------------------------------------------------------------

  localparam int unsigned NUM_RNF = CHI_CFG.numRnf;
  localparam int unsigned NUM_RND = CHI_CFG.numRnd;
  localparam int unsigned NUM_RNI = CHI_CFG.numRni;
  localparam int unsigned NUM_SNF = CHI_CFG.numSnf;
  localparam int unsigned NUM_SNI = CHI_CFG.numSni;
  localparam int unsigned NUM_HNF = CHI_CFG.numHnf;
  localparam int unsigned NUM_HNI = CHI_CFG.numHni;
  localparam int unsigned NUM_MN  = CHI_CFG.numMn;

  localparam int unsigned NUM_NODES =
    NUM_RNF + NUM_RND + NUM_RNI + NUM_SNF + NUM_SNI + NUM_HNF + NUM_HNI + NUM_MN;

  localparam int unsigned NUM_RNF_IF = (NUM_RNF > 0) ? NUM_RNF : 1;
  localparam int unsigned NUM_RND_IF = (NUM_RND > 0) ? NUM_RND : 1;
  localparam int unsigned NUM_RNI_IF = (NUM_RNI > 0) ? NUM_RNI : 1;
  localparam int unsigned NUM_SNF_IF = (NUM_SNF > 0) ? NUM_SNF : 1;
  localparam int unsigned NUM_SNI_IF = (NUM_SNI > 0) ? NUM_SNI : 1;

  localparam int unsigned OFF_RNF = 0;
  localparam int unsigned OFF_RND = OFF_RNF + NUM_RNF;
  localparam int unsigned OFF_RNI = OFF_RND + NUM_RND;
  localparam int unsigned OFF_SNF = OFF_RNI + NUM_RNI;
  localparam int unsigned OFF_SNI = OFF_SNF + NUM_SNF;
  localparam int unsigned OFF_HNF = OFF_SNI + NUM_SNI;
  localparam int unsigned OFF_HNI = OFF_HNF + NUM_HNF;
  localparam int unsigned OFF_MN  = OFF_HNI + NUM_HNI;

  // Agent index spaces. Requester agents are numbered across RN-F, RN-D and
  // RN-I in ordinal order, which makes the requester agent index identical to
  // the node ordinal because OFF_RND and OFF_RNI follow RN-F contiguously.
  // Subordinate agents are numbered across SN-F then SN-I.
  localparam int unsigned NUM_REQUESTER_AGENTS = NUM_RNF + NUM_RND + NUM_RNI;
  localparam int unsigned NUM_SUBORDINATE_AGENTS = NUM_SNF + NUM_SNI;

  typedef enum bit [2:0] {
    RN_F = 3'd0,
    RN_D = 3'd1,
    RN_I = 3'd2,
    SN_F = 3'd3,
    SN_I = 3'd4
  } chiNodeClassE;

  function automatic chiNodeClassE nodeClassOfOrdinal(input int unsigned ordinal);
    if (ordinal < OFF_RND) return RN_F;
    if (ordinal < OFF_RNI) return RN_D;
    if (ordinal < OFF_SNF) return RN_I;
    if (ordinal < OFF_SNI) return SN_F;
    return SN_I;
  endfunction

  function automatic int unsigned requesterAgentOrdinal(input int unsigned agentIndex);
    return agentIndex;
  endfunction

  function automatic int unsigned subordinateAgentOrdinal(input int unsigned agentIndex);
    return OFF_SNF + agentIndex;
  endfunction

  function automatic bit nodeClassIsRequester(input chiNodeClassE nodeClass);
    return (nodeClass == RN_F) || (nodeClass == RN_D) || (nodeClass == RN_I);
  endfunction

  // Class-dependent behaviour, taken from the spec rather than from any
  // per-instance configuration, so that an agent config object can derive it
  // from the class alone.
  // [SPEC:IHI0050H B1.3 Node types]
  function automatic bit nodeClassHasCache(input chiNodeClassE nodeClass);
    return (nodeClass == RN_F);
  endfunction

  function automatic bit nodeClassHasSnoopChannel(input chiNodeClassE nodeClass);
    // RN-F is coherently snooped. RN-D and RN-I have no coherent snoop, but
    // the DUT wires the SNP channel on all three requester classes and the MN
    // DVM-snoops every Requester, so all three must credit and answer SNP.
    // [TOP:CHI_CONNECT_PORT rnd/rni with IS_REQUESTER=1] See OPEN QUESTIONS Q13, Q14.
    return nodeClassIsRequester(nodeClass);
  endfunction

  function automatic bit nodeClassUsesSysCo(input chiNodeClassE nodeClass);
    // System coherency entry/exit is an RN-F property.
    // [SPEC:IHI0050H B13.4 System coherency interface] See OPEN QUESTIONS Q4.
    return (nodeClass == RN_F);
  endfunction

  //----------------------------------------------------------------------------
  // 3. NodeID and placement tables
  //
  // The testbench builds its own NodeID table so that every SrcID it drives and
  // every SrcID it receives is a value it computed, not one it has to discover.
  // The DUT accepts a NodeID only when the routing fields inside it agree with
  // the placement passed alongside it [TOP:chi_cfg_check], so the encoder and
  // the placement builder must be two views of one assignment. The field layout
  // is {meshY, meshX, devicePort, deviceId} with deviceId in the least
  // significant bits; it was confirmed against the DUT's own default table
  // rather than assumed. See OPEN QUESTIONS Q5 and Q22.
  //----------------------------------------------------------------------------

  function automatic int unsigned chiClog2Min1(input int unsigned value);
    int unsigned bits;
    bits = $clog2(value);
    return (bits < 1) ? 1 : bits;
  endfunction

  localparam int unsigned MESH_Y_W = chiClog2Min1(CHI_CFG.meshY);
  localparam int unsigned MESH_X_W = chiClog2Min1(CHI_CFG.meshX);
  localparam int unsigned DEV_PORT_W = chiClog2Min1(CHI_CFG.numDevPortsPerXp);
  localparam int unsigned ROUTE_W = MESH_Y_W + MESH_X_W + DEV_PORT_W;
  localparam int unsigned DEVICE_ID_W =
    (CHI_CFG.nodeIdW > ROUTE_W) ? (CHI_CFG.nodeIdW - ROUTE_W) : 0;

  localparam int unsigned NODE_ID_W = CHI_CFG.nodeIdW;
  localparam int unsigned NODE_ID_SLOT_W = chi_cfg_pkg::CHI_NODEID_SLOT_W;
  localparam int unsigned MAX_NODE_ID_W = chi_cfg_pkg::CHI_MAX_NODEID_W;

  typedef logic [MAX_NODE_ID_W-1:0] chiNodeIdT;
  typedef chiNodeIdT chiNodeIdArrayT [NUM_NODES-1:0];
  typedef chi_cfg_pkg::chi_mesh_placement_t chiPlacementArrayT [NUM_NODES-1:0];

  function automatic chiNodeIdT chiEncodeNodeId(
      input int unsigned meshY,
      input int unsigned meshX,
      input int unsigned devicePort,
      input int unsigned deviceId
  );
    chiNodeIdT value;
    value = '0;
    value |= chiNodeIdT'(deviceId);
    value |= chiNodeIdT'(devicePort) << DEVICE_ID_W;
    value |= chiNodeIdT'(meshX) << (DEVICE_ID_W + DEV_PORT_W);
    value |= chiNodeIdT'(meshY) << (DEVICE_ID_W + DEV_PORT_W + MESH_X_W);
    return value;
  endfunction

  // One coordinate per ordinal, device port varying fastest so that the
  // assignment is a bijection for any mesh geometry that satisfies the DUT's
  // own capacity check meshX*meshY*numDevPortsPerXp >= NUM_NODES.
  function automatic int unsigned placementDevicePort(input int unsigned ordinal);
    return ordinal % CHI_CFG.numDevPortsPerXp;
  endfunction

  function automatic int unsigned placementMeshX(input int unsigned ordinal);
    return (ordinal / CHI_CFG.numDevPortsPerXp) % CHI_CFG.meshX;
  endfunction

  function automatic int unsigned placementMeshY(input int unsigned ordinal);
    return (ordinal / (CHI_CFG.numDevPortsPerXp * CHI_CFG.meshX)) % CHI_CFG.meshY;
  endfunction

  // Device IDs start at 1 so that no node owns NodeID 0. The DUT routes a
  // request whose address matches no valid region to target NodeID 0 and
  // leaves the mapper's unmapped-error output unconnected, so reserving 0
  // keeps that case distinguishable from a delivery to a real node instead of
  // quietly landing on whichever node happened to be ordinal 0.
  // [TOP:chi_sam.unmappedError not connected] See OPEN QUESTIONS Q11.
  function automatic chiNodeIdArrayT buildNodeIds();
    chiNodeIdArrayT values;
    for (int unsigned i = 0; i < NUM_NODES; i++)
      values[i] = chiEncodeNodeId(placementMeshY(i), placementMeshX(i),
                                  placementDevicePort(i), i + 1);
    return values;
  endfunction

  function automatic chiPlacementArrayT buildPlacements();
    chiPlacementArrayT values;
    for (int unsigned i = 0; i < NUM_NODES; i++) begin
      values[i].valid      = 1'b1;
      values[i].nodeClass  = chi_cfg_pkg::nodeClassForOrdinal(CHI_CFG, i);
      values[i].nodeIndex  = chi_cfg_pkg::nodeIndexForOrdinal(CHI_CFG, i);
      values[i].meshX      = placementMeshX(i);
      values[i].meshY      = placementMeshY(i);
      values[i].devicePort = placementDevicePort(i);
    end
    return values;
  endfunction

  localparam chiNodeIdArrayT NODE_IDS = buildNodeIds();
  localparam chiPlacementArrayT PLACEMENTS = buildPlacements();

  function automatic chiNodeIdT nodeIdOfOrdinal(input int unsigned ordinal);
    return NODE_IDS[ordinal];
  endfunction

  // Reverse lookup, used by the monitor and the scoreboard to name the source
  // of an observed flit without consulting the DUT.
  function automatic int unsigned ordinalOfNodeId(input chiNodeIdT nodeId);
    for (int unsigned i = 0; i < NUM_NODES; i++)
      if (NODE_IDS[i] == nodeId) return i;
    return NUM_NODES;   // not a configured node
  endfunction

  function automatic bit isConfiguredNodeId(input chiNodeIdT nodeId);
    return ordinalOfNodeId(nodeId) < NUM_NODES;
  endfunction

  //----------------------------------------------------------------------------
  // 4. Address regions
  //
  // The testbench passes an explicit region table rather than letting the DUT
  // build its default one, so that the stimulus knows which window is coherent
  // and hashed across HN-Fs, which is direct to HN-I, and which is the
  // configuration MMIO window. The three patterns below are the ones the top
  // module itself writes [TOP:makeRegionBase/Limit/Target/Attributes], so no
  // new attribute encoding is invented here. Bit 0 of the attributes is the
  // region valid bit and bit 1 is secureOnly [ASSUMPTION:10].
  //----------------------------------------------------------------------------

  localparam int unsigned ADDR_W = CHI_CFG.addrW;

  // Matches the top module's NUM_REGIONS default [TOP:NUM_REGIONS].
`ifdef CHI_TB_NUM_REGIONS
  localparam int unsigned NUM_REGIONS = `CHI_TB_NUM_REGIONS;
`else
  localparam int unsigned NUM_REGIONS = 4;
`endif

  typedef logic [ADDR_W-1:0] chiAddrT;
  typedef chiAddrT chiRegionAddrArrayT [NUM_REGIONS-1:0];
  typedef logic [NODE_ID_SLOT_W-1:0] chiRegionTargetArrayT [NUM_REGIONS-1:0];
  typedef logic [3:0] chiRegionAttrArrayT [NUM_REGIONS-1:0];

  // Top 4 KiB of the space, exactly as the top module's CFG_MMIO_BASE default
  // computes it [TOP:CFG_MMIO_BASE].
  localparam chiAddrT CFG_MMIO_BASE = {ADDR_W{1'b1}} - chiAddrT'(12'hfff);

  localparam chiAddrT COHERENT_REGION_BASE = '0;
  localparam chiAddrT COHERENT_REGION_LIMIT = {1'b0, {(ADDR_W-1){1'b1}}};
  localparam chiAddrT DIRECT_REGION_BASE = {1'b1, {(ADDR_W-1){1'b0}}};
  localparam chiAddrT DIRECT_REGION_LIMIT = CFG_MMIO_BASE - chiAddrT'(1);

  localparam logic [3:0] REGION_ATTR_HNF_HASH =
    {2'(chi_cfg_pkg::SAM_REGION_HNF_HASH), 1'b0, 1'b1};
  localparam logic [3:0] REGION_ATTR_DIRECT =
    {2'(chi_cfg_pkg::SAM_REGION_DIRECT), 1'b0, 1'b1};
  localparam logic [3:0] REGION_ATTR_MMIO =
    {2'(chi_cfg_pkg::SAM_REGION_MMIO), 1'b0, 1'b1};
  localparam logic [3:0] REGION_ATTR_INVALID = 4'h0;

  function automatic chiRegionAddrArrayT buildRegionBase();
    chiRegionAddrArrayT values;
    values = '{default:'0};
    if (NUM_REGIONS > 1) values[1] = DIRECT_REGION_BASE;
    if (NUM_REGIONS > 2) values[2] = CFG_MMIO_BASE;
    return values;
  endfunction

  function automatic chiRegionAddrArrayT buildRegionLimit();
    chiRegionAddrArrayT values;
    values = '{default:'0};
    if (NUM_HNF > 0) values[0] = COHERENT_REGION_LIMIT;
    if (NUM_REGIONS > 1) values[1] = DIRECT_REGION_LIMIT;
    if (NUM_REGIONS > 2) values[2] = {ADDR_W{1'b1}};
    return values;
  endfunction

  function automatic chiRegionTargetArrayT buildRegionTarget();
    chiRegionTargetArrayT values;
    values = '{default:'0};
    if (NUM_HNI > 0) begin
      if (NUM_REGIONS > 1) values[1] = NODE_ID_SLOT_W'(NODE_IDS[OFF_HNI]);
      if (NUM_REGIONS > 2) values[2] = NODE_ID_SLOT_W'(NODE_IDS[OFF_HNI]);
    end
    return values;
  endfunction

  function automatic chiRegionAttrArrayT buildRegionAttributes();
    chiRegionAttrArrayT values;
    values = '{default:REGION_ATTR_INVALID};
    if (NUM_HNF > 0) values[0] = REGION_ATTR_HNF_HASH;
    if (NUM_HNI > 0) begin
      if (NUM_REGIONS > 1) values[1] = REGION_ATTR_DIRECT;
      if (NUM_REGIONS > 2) values[2] = REGION_ATTR_MMIO;
    end
    return values;
  endfunction

  localparam chiRegionAddrArrayT REGION_BASE = buildRegionBase();
  localparam chiRegionAddrArrayT REGION_LIMIT = buildRegionLimit();
  localparam chiRegionTargetArrayT REGION_TARGET = buildRegionTarget();
  localparam chiRegionAttrArrayT REGION_ATTRIBUTES = buildRegionAttributes();

  // Stimulus windows. Kept well inside their regions so that no test can walk
  // off the end of a region, and away from address 0 so that an accidentally
  // zeroed address field is obvious. The DUT leaves the address mapper's
  // unmapped-error output unconnected, so no test may target an unmapped
  // address [TOP:chi_sam.unmappedError not connected]. See OPEN QUESTIONS Q11.
  localparam chiAddrT COHERENT_WINDOW_BASE = chiAddrT'(64'h0000_0000_0010_0000);
  localparam chiAddrT DIRECT_WINDOW_BASE = DIRECT_REGION_BASE + chiAddrT'(64'h0010_0000);
  localparam int unsigned CACHE_LINE_BYTES = 64;    // [SPEC:IHI0050H B2.2 Cache line size]
  localparam int unsigned COHERENT_WINDOW_LINES = 256;

  function automatic chiAddrT coherentLineAddr(input int unsigned lineIndex);
    return COHERENT_WINDOW_BASE + chiAddrT'((lineIndex % COHERENT_WINDOW_LINES) * CACHE_LINE_BYTES);
  endfunction

  function automatic chiAddrT directLineAddr(input int unsigned lineIndex);
    return DIRECT_WINDOW_BASE + chiAddrT'((lineIndex % COHERENT_WINDOW_LINES) * CACHE_LINE_BYTES);
  endfunction

  function automatic chiAddrT lineAlign(input chiAddrT addr);
    return addr & ~chiAddrT'(CACHE_LINE_BYTES - 1);
  endfunction

  //----------------------------------------------------------------------------
  // 5. Flit widths
  //
  // Each width is the sum of the fields the model carries. The constant term of
  // each formula is the total of the fixed-width fields listed in section 6,
  // and the variable terms follow the configuration. The formulas reproduce the
  // DUT's boundary bus widths for the default configuration (REQ 153, RSP 79,
  // SNP 106, DAT 437), and every BFM re-checks its own channel against
  // $bits() on the interface at time 0, so a swept configuration that moves
  // them apart is reported rather than silently mispacked.
  // [SPEC:IHI0050H B13.9 Flit field summary] See OPEN QUESTIONS Q7.
  //----------------------------------------------------------------------------

  localparam int unsigned DATA_W = CHI_CFG.dataW;
  localparam int unsigned TXN_ID_W = chi_cfg_pkg::CHI_MAX_TXNID_W;
  localparam int unsigned LP_ID_W = chi_cfg_pkg::CHI_MAX_LPID_W;
  localparam int unsigned CC_ID_W = chi_cfg_pkg::CHI_MAX_CCID_W;
  localparam int unsigned GROUP_ID_W = chi_cfg_pkg::CHI_MAX_GROUPID_W;
  localparam int unsigned RSVDC_W = CHI_CFG.rsvdcW;
  localparam int unsigned MPAM_W = CHI_CFG.mpamEn ? CHI_CFG.mpamW : 0;
  localparam int unsigned MEC_ID_W = chi_cfg_pkg::CHI_MECID_W;
  localparam int unsigned STREAM_ID_W = chi_cfg_pkg::CHI_STREAMID_W;
  localparam int unsigned PBHA_W = chi_cfg_pkg::CHI_PBHA_W;

  // Fields the top module does not reference. See OPEN QUESTIONS Q15.
  localparam bit DATA_CHECK_EN = CHI_CFG.dataCheckEn;
  localparam bit POISON_EN = CHI_CFG.poisonEn;
  localparam bit PARITY_EN = CHI_CFG.parityEn;
  localparam bit MTE_EN = CHI_CFG.mteEn;
  localparam bit PBHA_EN = CHI_CFG.pbhaEn;
  localparam bit MEC_EN = CHI_CFG.mecEn;
  localparam bit CDA_EN = CHI_CFG.cdaEn;

  localparam int unsigned BE_W = DATA_W / 8;
  localparam int unsigned DATA_CHECK_W = DATA_CHECK_EN ? (DATA_W / 8) : 0;
  localparam int unsigned POISON_W = POISON_EN ? (DATA_W / 64) : 0;
  localparam int unsigned TAG_W = DATA_W / 32;          // 4 bits per 16 bytes
  localparam int unsigned TAG_UPDATE_W = DATA_W / 128;  // 1 bit per 16 bytes
  localparam int unsigned DAT_PACKETS_PER_LINE = (CACHE_LINE_BYTES * 8) / DATA_W;
  localparam int unsigned DATA_ID_STEP = DATA_W / 128;

  localparam int unsigned REQ_FLIT_W =
      72 + (3 * NODE_ID_W) + ADDR_W + RSVDC_W + MPAM_W
    + (PBHA_EN ? PBHA_W : 0)
    + (CDA_EN ? (STREAM_ID_W + 1) : 0)
    + (MEC_EN ? MEC_ID_W : 0);

  localparam int unsigned RSP_FLIT_W = 57 + (2 * NODE_ID_W);

  localparam int unsigned SNP_FLIT_W =
      39 + (2 * NODE_ID_W) + (ADDR_W - 3) + MPAM_W + (MEC_EN ? MEC_ID_W : 0);

  localparam int unsigned DAT_FLIT_W =
      70 + (3 * NODE_ID_W) + RSVDC_W + DATA_W + BE_W + DATA_CHECK_W + POISON_W
    + TAG_W + TAG_UPDATE_W + (MEC_EN ? MEC_ID_W : 0);

  localparam int unsigned FLIT_MAX_W =
    (REQ_FLIT_W > RSP_FLIT_W)
      ? ((REQ_FLIT_W > SNP_FLIT_W)
          ? ((REQ_FLIT_W > DAT_FLIT_W) ? REQ_FLIT_W : DAT_FLIT_W)
          : ((SNP_FLIT_W > DAT_FLIT_W) ? SNP_FLIT_W : DAT_FLIT_W))
      : ((RSP_FLIT_W > SNP_FLIT_W)
          ? ((RSP_FLIT_W > DAT_FLIT_W) ? RSP_FLIT_W : DAT_FLIT_W)
          : ((SNP_FLIT_W > DAT_FLIT_W) ? SNP_FLIT_W : DAT_FLIT_W));

  typedef logic [FLIT_MAX_W-1:0] chiRawFlitT;
  typedef logic [TXN_ID_W-1:0] chiTxnIdT;
  typedef logic [DATA_W-1:0] chiDataT;
  typedef logic [BE_W-1:0] chiByteEnableT;

  //----------------------------------------------------------------------------
  // 6. Flit field placement
  //
  // Bit 0 of every channel is the least significant bit of QoS [ASSUMPTION:7],
  // and fields follow in the spec's field-summary order. Offsets are derived by
  // cumulative addition so that inserting or resizing one field cannot leave a
  // stale offset behind. Variable-width fields that the DUT pads to their
  // architectural maximum (TxnID, LPID, CCID, GroupID) are padded here too, so
  // that a configuration which narrows them does not move every field above
  // them.
  //
  // Field ORDER is not measurable at the boundary and is the one part of this
  // model still carrying real risk. See OPEN QUESTIONS Q7.
  //----------------------------------------------------------------------------

  localparam int unsigned QOS_W = 4;
  localparam int unsigned REQ_OPCODE_W = 7;
  localparam int unsigned RSP_OPCODE_W = 5;
  localparam int unsigned SNP_OPCODE_W = 5;
  localparam int unsigned DAT_OPCODE_W = 4;
  localparam int unsigned SIZE_W = 3;
  localparam int unsigned PAS_W = 2;          // {NSE, NS} [SPEC:IHI0050H B2 PAS]
  localparam int unsigned ORDER_W = 2;
  localparam int unsigned P_CRD_TYPE_W = 4;
  localparam int unsigned MEM_ATTR_W = 4;
  localparam int unsigned RESP_ERR_W = 2;
  localparam int unsigned RESP_W = 3;
  localparam int unsigned FWD_STATE_W = 3;
  localparam int unsigned C_BUSY_W = 3;
  localparam int unsigned DATA_SOURCE_W = 3;
  localparam int unsigned DATA_ID_W = 2;
  localparam int unsigned TAG_OP_W = 2;

  // REQ
  localparam int unsigned REQ_OFF_QOS = 0;
  localparam int unsigned REQ_OFF_TGT_ID = REQ_OFF_QOS + QOS_W;
  localparam int unsigned REQ_OFF_SRC_ID = REQ_OFF_TGT_ID + NODE_ID_W;
  localparam int unsigned REQ_OFF_TXN_ID = REQ_OFF_SRC_ID + NODE_ID_W;
  localparam int unsigned REQ_OFF_RETURN_NID = REQ_OFF_TXN_ID + TXN_ID_W;
  localparam int unsigned REQ_OFF_STASH_NID_VALID = REQ_OFF_RETURN_NID + NODE_ID_W;
  localparam int unsigned REQ_OFF_RETURN_TXN_ID = REQ_OFF_STASH_NID_VALID + 1;
  localparam int unsigned REQ_OFF_GROUP_ID = REQ_OFF_RETURN_TXN_ID + TXN_ID_W;
  localparam int unsigned REQ_OFF_OPCODE = REQ_OFF_GROUP_ID + GROUP_ID_W;
  localparam int unsigned REQ_OFF_SIZE = REQ_OFF_OPCODE + REQ_OPCODE_W;
  localparam int unsigned REQ_OFF_ADDR = REQ_OFF_SIZE + SIZE_W;
  localparam int unsigned REQ_OFF_PAS = REQ_OFF_ADDR + ADDR_W;
  localparam int unsigned REQ_OFF_LIKELY_SHARED = REQ_OFF_PAS + PAS_W;
  localparam int unsigned REQ_OFF_ALLOW_RETRY = REQ_OFF_LIKELY_SHARED + 1;
  localparam int unsigned REQ_OFF_ORDER = REQ_OFF_ALLOW_RETRY + 1;
  localparam int unsigned REQ_OFF_P_CRD_TYPE = REQ_OFF_ORDER + ORDER_W;
  localparam int unsigned REQ_OFF_MEM_ATTR = REQ_OFF_P_CRD_TYPE + P_CRD_TYPE_W;
  localparam int unsigned REQ_OFF_SNP_ATTR = REQ_OFF_MEM_ATTR + MEM_ATTR_W;
  localparam int unsigned REQ_OFF_LP_ID = REQ_OFF_SNP_ATTR + 1;
  localparam int unsigned REQ_OFF_EXCL = REQ_OFF_LP_ID + LP_ID_W;
  localparam int unsigned REQ_OFF_EXP_COMP_ACK = REQ_OFF_EXCL + 1;
  localparam int unsigned REQ_OFF_TAG_OP = REQ_OFF_EXP_COMP_ACK + 1;
  localparam int unsigned REQ_OFF_TRACE_TAG = REQ_OFF_TAG_OP + TAG_OP_W;
  localparam int unsigned REQ_OFF_MPAM = REQ_OFF_TRACE_TAG + 1;
  localparam int unsigned REQ_OFF_PBHA = REQ_OFF_MPAM + MPAM_W;
  localparam int unsigned REQ_OFF_MEC_STREAM_ID =
    REQ_OFF_PBHA + (PBHA_EN ? PBHA_W : 0);
  localparam int unsigned REQ_OFF_SEC_SID1 =
    REQ_OFF_MEC_STREAM_ID + (MEC_EN ? MEC_ID_W : 0) + (CDA_EN ? STREAM_ID_W : 0);
  localparam int unsigned REQ_OFF_RSVDC = REQ_OFF_SEC_SID1 + (CDA_EN ? 1 : 0);
  localparam int unsigned REQ_MODEL_W = REQ_OFF_RSVDC + RSVDC_W;

  // RSP
  localparam int unsigned RSP_OFF_QOS = 0;
  localparam int unsigned RSP_OFF_TGT_ID = RSP_OFF_QOS + QOS_W;
  localparam int unsigned RSP_OFF_SRC_ID = RSP_OFF_TGT_ID + NODE_ID_W;
  localparam int unsigned RSP_OFF_TXN_ID = RSP_OFF_SRC_ID + NODE_ID_W;
  localparam int unsigned RSP_OFF_OPCODE = RSP_OFF_TXN_ID + TXN_ID_W;
  localparam int unsigned RSP_OFF_RESP_ERR = RSP_OFF_OPCODE + RSP_OPCODE_W;
  localparam int unsigned RSP_OFF_RESP = RSP_OFF_RESP_ERR + RESP_ERR_W;
  localparam int unsigned RSP_OFF_FWD_STATE = RSP_OFF_RESP + RESP_W;
  localparam int unsigned RSP_OFF_DATA_PULL = RSP_OFF_FWD_STATE + FWD_STATE_W;
  localparam int unsigned RSP_OFF_C_BUSY = RSP_OFF_DATA_PULL + 1;
  localparam int unsigned RSP_OFF_DBID = RSP_OFF_C_BUSY + C_BUSY_W;
  localparam int unsigned RSP_OFF_P_CRD_TYPE = RSP_OFF_DBID + TXN_ID_W;
  localparam int unsigned RSP_OFF_TAG_OP = RSP_OFF_P_CRD_TYPE + P_CRD_TYPE_W;
  localparam int unsigned RSP_OFF_TRACE_TAG = RSP_OFF_TAG_OP + TAG_OP_W;
  localparam int unsigned RSP_MODEL_W = RSP_OFF_TRACE_TAG + 1;

  // SNP
  localparam int unsigned SNP_ADDR_W = ADDR_W - 3;
  localparam int unsigned SNP_OFF_QOS = 0;
  localparam int unsigned SNP_OFF_SRC_ID = SNP_OFF_QOS + QOS_W;
  localparam int unsigned SNP_OFF_TXN_ID = SNP_OFF_SRC_ID + NODE_ID_W;
  localparam int unsigned SNP_OFF_FWD_NID = SNP_OFF_TXN_ID + TXN_ID_W;
  localparam int unsigned SNP_OFF_FWD_TXN_ID = SNP_OFF_FWD_NID + NODE_ID_W;
  localparam int unsigned SNP_OFF_STASH_LPID_VALID = SNP_OFF_FWD_TXN_ID + TXN_ID_W;
  localparam int unsigned SNP_OFF_OPCODE = SNP_OFF_STASH_LPID_VALID + 1;
  localparam int unsigned SNP_OFF_ADDR = SNP_OFF_OPCODE + SNP_OPCODE_W;
  localparam int unsigned SNP_OFF_PAS = SNP_OFF_ADDR + SNP_ADDR_W;
  localparam int unsigned SNP_OFF_DO_NOT_GO_TO_SD = SNP_OFF_PAS + PAS_W;
  localparam int unsigned SNP_OFF_RET_TO_SRC = SNP_OFF_DO_NOT_GO_TO_SD + 1;
  localparam int unsigned SNP_OFF_TRACE_TAG = SNP_OFF_RET_TO_SRC + 1;
  localparam int unsigned SNP_OFF_MPAM = SNP_OFF_TRACE_TAG + 1;
  localparam int unsigned SNP_OFF_MEC_ID = SNP_OFF_MPAM + MPAM_W;
  localparam int unsigned SNP_MODEL_W = SNP_OFF_MEC_ID + (MEC_EN ? MEC_ID_W : 0);

  // DAT
  localparam int unsigned DAT_OFF_QOS = 0;
  localparam int unsigned DAT_OFF_TGT_ID = DAT_OFF_QOS + QOS_W;
  localparam int unsigned DAT_OFF_SRC_ID = DAT_OFF_TGT_ID + NODE_ID_W;
  localparam int unsigned DAT_OFF_TXN_ID = DAT_OFF_SRC_ID + NODE_ID_W;
  localparam int unsigned DAT_OFF_HOME_NID = DAT_OFF_TXN_ID + TXN_ID_W;
  localparam int unsigned DAT_OFF_OPCODE = DAT_OFF_HOME_NID + NODE_ID_W;
  localparam int unsigned DAT_OFF_RESP_ERR = DAT_OFF_OPCODE + DAT_OPCODE_W;
  localparam int unsigned DAT_OFF_RESP = DAT_OFF_RESP_ERR + RESP_ERR_W;
  localparam int unsigned DAT_OFF_DATA_SOURCE = DAT_OFF_RESP + RESP_W;
  localparam int unsigned DAT_OFF_DATA_PULL = DAT_OFF_DATA_SOURCE + DATA_SOURCE_W;
  localparam int unsigned DAT_OFF_C_BUSY = DAT_OFF_DATA_PULL + 1;
  localparam int unsigned DAT_OFF_DBID = DAT_OFF_C_BUSY + C_BUSY_W;
  localparam int unsigned DAT_OFF_CC_ID = DAT_OFF_DBID + TXN_ID_W;
  localparam int unsigned DAT_OFF_DATA_ID = DAT_OFF_CC_ID + CC_ID_W;
  localparam int unsigned DAT_OFF_TAG_OP = DAT_OFF_DATA_ID + DATA_ID_W;
  localparam int unsigned DAT_OFF_TRACE_TAG = DAT_OFF_TAG_OP + TAG_OP_W;
  localparam int unsigned DAT_OFF_TAG = DAT_OFF_TRACE_TAG + 1;
  localparam int unsigned DAT_OFF_TAG_UPDATE = DAT_OFF_TAG + TAG_W;
  localparam int unsigned DAT_OFF_POISON = DAT_OFF_TAG_UPDATE + TAG_UPDATE_W;
  localparam int unsigned DAT_OFF_DATA_CHECK = DAT_OFF_POISON + POISON_W;
  localparam int unsigned DAT_OFF_BE = DAT_OFF_DATA_CHECK + DATA_CHECK_W;
  localparam int unsigned DAT_OFF_DATA = DAT_OFF_BE + BE_W;
  localparam int unsigned DAT_OFF_MEC_ID = DAT_OFF_DATA + DATA_W;
  localparam int unsigned DAT_OFF_RSVDC = DAT_OFF_MEC_ID + (MEC_EN ? MEC_ID_W : 0);
  localparam int unsigned DAT_MODEL_W = DAT_OFF_RSVDC + RSVDC_W;

  // How many bits of each channel this model does not account for. A non-zero
  // entry is a finding against OPEN QUESTIONS Q7, reported by hdlTop at time 0,
  // never silently ignored.
  localparam int unsigned REQ_MODEL_DELTA = REQ_FLIT_W - REQ_MODEL_W;
  localparam int unsigned RSP_MODEL_DELTA = RSP_FLIT_W - RSP_MODEL_W;
  localparam int unsigned SNP_MODEL_DELTA = SNP_FLIT_W - SNP_MODEL_W;
  localparam int unsigned DAT_MODEL_DELTA = DAT_FLIT_W - DAT_MODEL_W;

  //----------------------------------------------------------------------------
  // 7. Opcodes and response encodings
  //
  // Every encoding below is this package's own reading of the specification and
  // is the single place any of them appears. Opcode 0 on each channel is that
  // channel's L-Credit return, which is what lets the link layer drain credits
  // with an all-zero flit and no dependence on field placement at all.
  // [SPEC:IHI0050H B13.8 Channel opcode encodings] See OPEN QUESTIONS Q19.
  //----------------------------------------------------------------------------

  typedef enum logic [REQ_OPCODE_W-1:0] {
    REQ_LCRD_RETURN          = 7'h00,
    REQ_READ_SHARED          = 7'h01,
    REQ_READ_CLEAN           = 7'h02,
    REQ_READ_ONCE            = 7'h03,
    REQ_READ_NO_SNP          = 7'h04,
    REQ_P_CRD_RETURN         = 7'h05,
    REQ_READ_UNIQUE          = 7'h07,
    REQ_CLEAN_SHARED         = 7'h08,
    REQ_CLEAN_INVALID        = 7'h09,
    REQ_MAKE_INVALID         = 7'h0A,
    REQ_CLEAN_UNIQUE         = 7'h0B,
    REQ_MAKE_UNIQUE          = 7'h0C,
    REQ_EVICT                = 7'h0D,
    REQ_READ_NO_SNP_SEP      = 7'h11,
    REQ_CLEAN_SHARED_PERSIST_SEP = 7'h13,
    REQ_DVM_OP               = 7'h14,
    REQ_WRITE_EVICT_FULL     = 7'h15,
    REQ_WRITE_CLEAN_PTL      = 7'h16,
    REQ_WRITE_CLEAN_FULL     = 7'h17,
    REQ_WRITE_UNIQUE_PTL     = 7'h18,
    REQ_WRITE_UNIQUE_FULL    = 7'h19,
    REQ_WRITE_BACK_PTL       = 7'h1A,
    REQ_WRITE_BACK_FULL      = 7'h1B,
    REQ_WRITE_NO_SNP_PTL     = 7'h1C,
    REQ_WRITE_NO_SNP_FULL    = 7'h1D,
    REQ_WRITE_UNIQUE_FULL_STASH = 7'h20,
    REQ_WRITE_UNIQUE_PTL_STASH  = 7'h21,
    REQ_STASH_ONCE_SHARED    = 7'h22,
    REQ_STASH_ONCE_UNIQUE    = 7'h23,
    REQ_READ_ONCE_CLEAN_INVALID = 7'h24,
    REQ_READ_ONCE_MAKE_INVALID  = 7'h25,
    REQ_READ_NOT_SHARED_DIRTY   = 7'h26,
    REQ_CLEAN_SHARED_PERSIST = 7'h27,
    REQ_ATOMIC_STORE_ADD     = 7'h28,
    REQ_ATOMIC_STORE_CLR     = 7'h29,
    REQ_ATOMIC_STORE_EOR     = 7'h2A,
    REQ_ATOMIC_STORE_SET     = 7'h2B,
    REQ_ATOMIC_STORE_SMAX    = 7'h2C,
    REQ_ATOMIC_STORE_SMIN    = 7'h2D,
    REQ_ATOMIC_STORE_UMAX    = 7'h2E,
    REQ_ATOMIC_STORE_UMIN    = 7'h2F,
    REQ_ATOMIC_LOAD_ADD      = 7'h30,
    REQ_ATOMIC_LOAD_CLR      = 7'h31,
    REQ_ATOMIC_LOAD_EOR      = 7'h32,
    REQ_ATOMIC_LOAD_SET      = 7'h33,
    REQ_ATOMIC_LOAD_SMAX     = 7'h34,
    REQ_ATOMIC_LOAD_SMIN     = 7'h35,
    REQ_ATOMIC_LOAD_UMAX     = 7'h36,
    REQ_ATOMIC_LOAD_UMIN     = 7'h37,
    REQ_ATOMIC_SWAP          = 7'h38,
    REQ_ATOMIC_COMPARE       = 7'h39,
    REQ_PREFETCH_TGT         = 7'h3A,
    REQ_MAKE_READ_UNIQUE     = 7'h41,
    REQ_WRITE_EVICT_OR_EVICT = 7'h42,
    REQ_WRITE_UNIQUE_ZERO    = 7'h43,
    REQ_WRITE_NO_SNP_ZERO    = 7'h44,
    REQ_STASH_ONCE_SEP_SHARED = 7'h47,
    REQ_STASH_ONCE_SEP_UNIQUE = 7'h48,
    REQ_READ_PREFER_UNIQUE   = 7'h4C
  } chiReqOpcodeE;

  typedef enum logic [RSP_OPCODE_W-1:0] {
    RSP_LCRD_RETURN     = 5'h00,
    RSP_SNP_RESP        = 5'h01,
    RSP_COMP_ACK        = 5'h02,
    RSP_RETRY_ACK       = 5'h03,
    RSP_COMP            = 5'h04,
    RSP_COMP_DBID_RESP  = 5'h05,
    RSP_DBID_RESP       = 5'h06,
    RSP_P_CRD_GRANT     = 5'h07,
    RSP_READ_RECEIPT    = 5'h08,
    RSP_SNP_RESP_FWDED  = 5'h09,
    RSP_TAG_MATCH       = 5'h0A,
    RSP_RESP_SEP_DATA   = 5'h0B,
    RSP_PERSIST         = 5'h0C,
    RSP_COMP_PERSIST    = 5'h0D,
    RSP_DBID_RESP_ORD   = 5'h0E,
    RSP_STASH_DONE      = 5'h10,
    RSP_COMP_STASH_DONE = 5'h11,
    RSP_COMP_CMO        = 5'h14
  } chiRspOpcodeE;

  typedef enum logic [SNP_OPCODE_W-1:0] {
    SNP_LCRD_RETURN            = 5'h00,
    SNP_SHARED                 = 5'h01,
    SNP_CLEAN                  = 5'h02,
    SNP_ONCE                   = 5'h03,
    SNP_NOT_SHARED_DIRTY       = 5'h04,
    SNP_UNIQUE_STASH           = 5'h05,
    SNP_MAKE_INVALID_STASH     = 5'h06,
    SNP_UNIQUE                 = 5'h07,
    SNP_CLEAN_SHARED           = 5'h08,
    SNP_CLEAN_INVALID          = 5'h09,
    SNP_MAKE_INVALID           = 5'h0A,
    SNP_STASH_UNIQUE           = 5'h0B,
    SNP_STASH_SHARED           = 5'h0C,
    SNP_DVM_OP                 = 5'h0D,
    SNP_QUERY                  = 5'h0E,
    SNP_SHARED_FWD             = 5'h11,
    SNP_CLEAN_FWD              = 5'h12,
    SNP_ONCE_FWD               = 5'h13,
    SNP_NOT_SHARED_DIRTY_FWD   = 5'h14,
    SNP_PREFER_UNIQUE          = 5'h15,
    SNP_PREFER_UNIQUE_FWD      = 5'h16,
    SNP_UNIQUE_FWD             = 5'h17
  } chiSnpOpcodeE;

  typedef enum logic [DAT_OPCODE_W-1:0] {
    DAT_LCRD_RETURN     = 4'h0,
    DAT_SNP_RESP_DATA   = 4'h1,
    DAT_COPY_BACK_WR_DATA = 4'h2,
    DAT_NON_COPY_BACK_WR_DATA = 4'h3,
    DAT_COMP_DATA       = 4'h4,
    DAT_SNP_RESP_DATA_PTL = 4'h5,
    DAT_SNP_RESP_DATA_FWDED = 4'h6,
    DAT_WRITE_DATA_CANCEL = 4'h7,
    DAT_DATA_SEP_RESP   = 4'hB,
    DAT_NCB_WR_DATA_COMP_ACK = 4'hC
  } chiDatOpcodeE;

  // Cache state encoding carried in Resp[2:0] of a data or snoop response. The
  // UC and UD states share encoding 3'b010; which one a receiver should infer
  // depends on the opcode class, so only one label is defined and the
  // interpretation is done by the cache model.
  // [SPEC:IHI0050H B4.8 Response field encodings]
  typedef enum logic [RESP_W-1:0] {
    RESP_I     = 3'b000,
    RESP_SC    = 3'b001,
    RESP_UC_UD = 3'b010,
    RESP_SD    = 3'b011,
    RESP_I_PD  = 3'b100,
    RESP_SC_PD = 3'b101,
    RESP_UC_PD = 3'b110,
    RESP_SD_PD = 3'b111
  } chiRespE;

  typedef enum logic [RESP_ERR_W-1:0] {
    RESP_ERR_OK   = 2'b00,
    RESP_ERR_EXOK = 2'b01,
    RESP_ERR_DERR = 2'b10,
    RESP_ERR_NDERR = 2'b11
  } chiRespErrE;

  // Cache state held by the testbench's own cache model. Kept separate from the
  // wire encoding above because UCE and the partial-dirty states are model
  // states, not wire values. [SPEC:IHI0050H B2.4 Cache state model]
  typedef enum bit [2:0] {
    CACHE_I   = 3'd0,
    CACHE_SC  = 3'd1,
    CACHE_UC  = 3'd2,
    CACHE_UD  = 3'd3,
    CACHE_SD  = 3'd4,
    CACHE_UCE = 3'd5
  } chiCacheStateE;

  //----------------------------------------------------------------------------
  // 8. Link layer types
  //----------------------------------------------------------------------------

  typedef enum bit [1:0] {
    CHI_CH_REQ = 2'd0,
    CHI_CH_RSP = 2'd1,
    CHI_CH_SNP = 2'd2,
    CHI_CH_DAT = 2'd3
  } chiChannelE;

  // TX is node to interconnect and RX is interconnect to node, on every port
  // class, matching the interface's own pin naming [ASSUMPTION:1].
  typedef enum bit [0:0] {
    CHI_DIR_TX = 1'd0,
    CHI_DIR_RX = 1'd1
  } chiDirE;

  // [SPEC:IHI0050H B13.5 Link activation and deactivation]
  typedef enum bit [1:0] {
    LINK_STOP       = 2'd0,
    LINK_ACTIVATE   = 2'd1,
    LINK_RUN        = 2'd2,
    LINK_DEACTIVATE = 2'd3
  } chiLinkStateE;

  // The DUT advertises max(lcrdDepth,2) credits per receive channel and raises
  // linkCreditError if it is ever given more than its transmitter depth, so
  // this is an upper bound the testbench must respect, not a convention.
  // [ASSUMPTION:9]
  localparam int unsigned LCRD_DEPTH =
    (CHI_CFG.lcrdDepth > 2) ? CHI_CFG.lcrdDepth : 2;

  // One observed flit or credit event, as the monitor BFM hands it to its
  // proxy. Unpacked so that a task can return it by value.
  typedef struct {
    int unsigned  nodeOrdinal;
    chiNodeClassE nodeClass;
    chiChannelE   channel;
    chiDirE       direction;
    bit           lcrdReturn;
    chiRawFlitT   payload;
    time          sampleTime;
  } chiFlitSampleT;

  typedef struct {
    int unsigned  nodeOrdinal;
    bit           linkUp;
    bit           parityError;
    bit           creditError;
    chiLinkStateE txState;
    chiLinkStateE rxState;
    bit           sysCoReq;
    bit           sysCoAck;
    time          sampleTime;
  } chiLinkSampleT;

  //----------------------------------------------------------------------------
  // 9. Pack and unpack
  //
  // The structs below are the testbench's working form of a flit. They are
  // unpacked so that a field can be left alone when an opcode does not use it,
  // and the pack functions place them at the offsets from section 6.
  //----------------------------------------------------------------------------

  typedef struct {
    logic [QOS_W-1:0]        qos;
    chiNodeIdT               tgtId;
    chiNodeIdT               srcId;
    chiTxnIdT                txnId;
    chiNodeIdT               returnNid;
    bit                      stashNidValid;
    chiTxnIdT                returnTxnId;
    logic [GROUP_ID_W-1:0]   groupId;
    chiReqOpcodeE            opcode;
    logic [SIZE_W-1:0]       size;
    chiAddrT                 addr;
    logic [PAS_W-1:0]        pas;
    bit                      likelyShared;
    bit                      allowRetry;
    logic [ORDER_W-1:0]      order;
    logic [P_CRD_TYPE_W-1:0] pCrdType;
    logic [MEM_ATTR_W-1:0]   memAttr;
    bit                      snpAttr;
    logic [LP_ID_W-1:0]      lpId;
    bit                      excl;
    bit                      expCompAck;
    logic [TAG_OP_W-1:0]     tagOp;
    bit                      traceTag;
    logic [15:0]             mpam;
    logic [PBHA_W-1:0]       pbha;
    logic [31:0]             mecStreamId;
    bit                      secSid1;
    logic [31:0]             rsvdc;
  } chiReqFlitT;

  typedef struct {
    logic [QOS_W-1:0]        qos;
    chiNodeIdT               tgtId;
    chiNodeIdT               srcId;
    chiTxnIdT                txnId;
    chiRspOpcodeE            opcode;
    chiRespErrE              respErr;
    logic [RESP_W-1:0]       resp;
    logic [FWD_STATE_W-1:0]  fwdState;
    bit                      dataPull;
    logic [C_BUSY_W-1:0]     cBusy;
    chiTxnIdT                dbId;
    logic [P_CRD_TYPE_W-1:0] pCrdType;
    logic [TAG_OP_W-1:0]     tagOp;
    bit                      traceTag;
  } chiRspFlitT;

  typedef struct {
    logic [QOS_W-1:0]        qos;
    chiNodeIdT               srcId;
    chiTxnIdT                txnId;
    chiNodeIdT               fwdNid;
    chiTxnIdT                fwdTxnId;
    bit                      stashLpIdValid;
    chiSnpOpcodeE            opcode;
    logic [ADDR_W-1:0]       addr;          // line address, bit 2:0 always zero
    logic [PAS_W-1:0]        pas;
    bit                      doNotGoToSd;
    bit                      retToSrc;
    bit                      traceTag;
    logic [15:0]             mpam;
    logic [31:0]             mecId;
  } chiSnpFlitT;

  typedef struct {
    logic [QOS_W-1:0]         qos;
    chiNodeIdT                tgtId;
    chiNodeIdT                srcId;
    chiTxnIdT                 txnId;
    chiNodeIdT                homeNid;
    chiDatOpcodeE             opcode;
    chiRespErrE               respErr;
    logic [RESP_W-1:0]        resp;
    logic [DATA_SOURCE_W-1:0] dataSource;
    bit                       dataPull;
    logic [C_BUSY_W-1:0]      cBusy;
    chiTxnIdT                 dbId;
    logic [CC_ID_W-1:0]       ccId;
    logic [DATA_ID_W-1:0]     dataId;
    logic [TAG_OP_W-1:0]      tagOp;
    bit                       traceTag;
    logic [15:0]              tag;
    logic [3:0]               tagUpdate;
    logic [7:0]               poison;
    logic [63:0]              dataCheck;
    chiByteEnableT            be;
    chiDataT                  data;
    logic [31:0]              mecId;
    logic [31:0]              rsvdc;
  } chiDatFlitT;

  function automatic chiRawFlitT packReq(input chiReqFlitT flit);
    chiRawFlitT raw;
    raw = '0;
    raw[REQ_OFF_QOS            +: QOS_W]        = flit.qos;
    raw[REQ_OFF_TGT_ID         +: NODE_ID_W]    = flit.tgtId[NODE_ID_W-1:0];
    raw[REQ_OFF_SRC_ID         +: NODE_ID_W]    = flit.srcId[NODE_ID_W-1:0];
    raw[REQ_OFF_TXN_ID         +: TXN_ID_W]     = flit.txnId;
    raw[REQ_OFF_RETURN_NID     +: NODE_ID_W]    = flit.returnNid[NODE_ID_W-1:0];
    raw[REQ_OFF_STASH_NID_VALID]                = flit.stashNidValid;
    raw[REQ_OFF_RETURN_TXN_ID  +: TXN_ID_W]     = flit.returnTxnId;
    raw[REQ_OFF_GROUP_ID       +: GROUP_ID_W]   = flit.groupId;
    raw[REQ_OFF_OPCODE         +: REQ_OPCODE_W] = flit.opcode;
    raw[REQ_OFF_SIZE           +: SIZE_W]       = flit.size;
    raw[REQ_OFF_ADDR           +: ADDR_W]       = flit.addr;
    raw[REQ_OFF_PAS            +: PAS_W]        = flit.pas;
    raw[REQ_OFF_LIKELY_SHARED]                  = flit.likelyShared;
    raw[REQ_OFF_ALLOW_RETRY]                    = flit.allowRetry;
    raw[REQ_OFF_ORDER          +: ORDER_W]      = flit.order;
    raw[REQ_OFF_P_CRD_TYPE     +: P_CRD_TYPE_W] = flit.pCrdType;
    raw[REQ_OFF_MEM_ATTR       +: MEM_ATTR_W]   = flit.memAttr;
    raw[REQ_OFF_SNP_ATTR]                       = flit.snpAttr;
    raw[REQ_OFF_LP_ID          +: LP_ID_W]      = flit.lpId;
    raw[REQ_OFF_EXCL]                           = flit.excl;
    raw[REQ_OFF_EXP_COMP_ACK]                   = flit.expCompAck;
    raw[REQ_OFF_TAG_OP         +: TAG_OP_W]     = flit.tagOp;
    raw[REQ_OFF_TRACE_TAG]                      = flit.traceTag;
    for (int unsigned i = 0; i < MPAM_W; i++)
      raw[REQ_OFF_MPAM + i] = flit.mpam[i];
    for (int unsigned i = 0; i < (PBHA_EN ? PBHA_W : 0); i++)
      raw[REQ_OFF_PBHA + i] = flit.pbha[i];
    for (int unsigned i = 0; i < (MEC_EN ? MEC_ID_W : 0); i++)
      raw[REQ_OFF_MEC_STREAM_ID + i] = flit.mecStreamId[i];
    for (int unsigned i = 0; i < (CDA_EN ? STREAM_ID_W : 0); i++)
      raw[REQ_OFF_MEC_STREAM_ID + i] = flit.mecStreamId[i];
    if (CDA_EN)
      raw[REQ_OFF_SEC_SID1] = flit.secSid1;
    for (int unsigned i = 0; i < RSVDC_W; i++)
      raw[REQ_OFF_RSVDC + i] = flit.rsvdc[i];
    return raw;
  endfunction

  function automatic chiReqFlitT unpackReq(input chiRawFlitT raw);
    chiReqFlitT flit;
    flit = '{default:'0, opcode:REQ_LCRD_RETURN};
    flit.qos           = raw[REQ_OFF_QOS +: QOS_W];
    flit.tgtId         = chiNodeIdT'(raw[REQ_OFF_TGT_ID +: NODE_ID_W]);
    flit.srcId         = chiNodeIdT'(raw[REQ_OFF_SRC_ID +: NODE_ID_W]);
    flit.txnId         = raw[REQ_OFF_TXN_ID +: TXN_ID_W];
    flit.returnNid     = chiNodeIdT'(raw[REQ_OFF_RETURN_NID +: NODE_ID_W]);
    flit.stashNidValid = raw[REQ_OFF_STASH_NID_VALID];
    flit.returnTxnId   = raw[REQ_OFF_RETURN_TXN_ID +: TXN_ID_W];
    flit.groupId       = raw[REQ_OFF_GROUP_ID +: GROUP_ID_W];
    flit.opcode        = chiReqOpcodeE'(raw[REQ_OFF_OPCODE +: REQ_OPCODE_W]);
    flit.size          = raw[REQ_OFF_SIZE +: SIZE_W];
    flit.addr          = raw[REQ_OFF_ADDR +: ADDR_W];
    flit.pas           = raw[REQ_OFF_PAS +: PAS_W];
    flit.likelyShared  = raw[REQ_OFF_LIKELY_SHARED];
    flit.allowRetry    = raw[REQ_OFF_ALLOW_RETRY];
    flit.order         = raw[REQ_OFF_ORDER +: ORDER_W];
    flit.pCrdType      = raw[REQ_OFF_P_CRD_TYPE +: P_CRD_TYPE_W];
    flit.memAttr       = raw[REQ_OFF_MEM_ATTR +: MEM_ATTR_W];
    flit.snpAttr       = raw[REQ_OFF_SNP_ATTR];
    flit.lpId          = raw[REQ_OFF_LP_ID +: LP_ID_W];
    flit.excl          = raw[REQ_OFF_EXCL];
    flit.expCompAck    = raw[REQ_OFF_EXP_COMP_ACK];
    flit.tagOp         = raw[REQ_OFF_TAG_OP +: TAG_OP_W];
    flit.traceTag      = raw[REQ_OFF_TRACE_TAG];
    for (int unsigned i = 0; i < MPAM_W; i++)
      flit.mpam[i] = raw[REQ_OFF_MPAM + i];
    for (int unsigned i = 0; i < (PBHA_EN ? PBHA_W : 0); i++)
      flit.pbha[i] = raw[REQ_OFF_PBHA + i];
    for (int unsigned i = 0; i < (MEC_EN ? MEC_ID_W : 0); i++)
      flit.mecStreamId[i] = raw[REQ_OFF_MEC_STREAM_ID + i];
    for (int unsigned i = 0; i < (CDA_EN ? STREAM_ID_W : 0); i++)
      flit.mecStreamId[i] = raw[REQ_OFF_MEC_STREAM_ID + i];
    if (CDA_EN)
      flit.secSid1 = raw[REQ_OFF_SEC_SID1];
    for (int unsigned i = 0; i < RSVDC_W; i++)
      flit.rsvdc[i] = raw[REQ_OFF_RSVDC + i];
    return flit;
  endfunction

  function automatic chiRawFlitT packRsp(input chiRspFlitT flit);
    chiRawFlitT raw;
    raw = '0;
    raw[RSP_OFF_QOS        +: QOS_W]        = flit.qos;
    raw[RSP_OFF_TGT_ID     +: NODE_ID_W]    = flit.tgtId[NODE_ID_W-1:0];
    raw[RSP_OFF_SRC_ID     +: NODE_ID_W]    = flit.srcId[NODE_ID_W-1:0];
    raw[RSP_OFF_TXN_ID     +: TXN_ID_W]     = flit.txnId;
    raw[RSP_OFF_OPCODE     +: RSP_OPCODE_W] = flit.opcode;
    raw[RSP_OFF_RESP_ERR   +: RESP_ERR_W]   = flit.respErr;
    raw[RSP_OFF_RESP       +: RESP_W]       = flit.resp;
    raw[RSP_OFF_FWD_STATE  +: FWD_STATE_W]  = flit.fwdState;
    raw[RSP_OFF_DATA_PULL]                  = flit.dataPull;
    raw[RSP_OFF_C_BUSY     +: C_BUSY_W]     = flit.cBusy;
    raw[RSP_OFF_DBID       +: TXN_ID_W]     = flit.dbId;
    raw[RSP_OFF_P_CRD_TYPE +: P_CRD_TYPE_W] = flit.pCrdType;
    raw[RSP_OFF_TAG_OP     +: TAG_OP_W]     = flit.tagOp;
    raw[RSP_OFF_TRACE_TAG]                  = flit.traceTag;
    return raw;
  endfunction

  function automatic chiRspFlitT unpackRsp(input chiRawFlitT raw);
    chiRspFlitT flit;
    flit = '{default:'0, opcode:RSP_LCRD_RETURN, respErr:RESP_ERR_OK};
    flit.qos      = raw[RSP_OFF_QOS +: QOS_W];
    flit.tgtId    = chiNodeIdT'(raw[RSP_OFF_TGT_ID +: NODE_ID_W]);
    flit.srcId    = chiNodeIdT'(raw[RSP_OFF_SRC_ID +: NODE_ID_W]);
    flit.txnId    = raw[RSP_OFF_TXN_ID +: TXN_ID_W];
    flit.opcode   = chiRspOpcodeE'(raw[RSP_OFF_OPCODE +: RSP_OPCODE_W]);
    flit.respErr  = chiRespErrE'(raw[RSP_OFF_RESP_ERR +: RESP_ERR_W]);
    flit.resp     = raw[RSP_OFF_RESP +: RESP_W];
    flit.fwdState = raw[RSP_OFF_FWD_STATE +: FWD_STATE_W];
    flit.dataPull = raw[RSP_OFF_DATA_PULL];
    flit.cBusy    = raw[RSP_OFF_C_BUSY +: C_BUSY_W];
    flit.dbId     = raw[RSP_OFF_DBID +: TXN_ID_W];
    flit.pCrdType = raw[RSP_OFF_P_CRD_TYPE +: P_CRD_TYPE_W];
    flit.tagOp    = raw[RSP_OFF_TAG_OP +: TAG_OP_W];
    flit.traceTag = raw[RSP_OFF_TRACE_TAG];
    return flit;
  endfunction

  function automatic chiRawFlitT packSnp(input chiSnpFlitT flit);
    chiRawFlitT raw;
    raw = '0;
    raw[SNP_OFF_QOS      +: QOS_W]        = flit.qos;
    raw[SNP_OFF_SRC_ID   +: NODE_ID_W]    = flit.srcId[NODE_ID_W-1:0];
    raw[SNP_OFF_TXN_ID   +: TXN_ID_W]     = flit.txnId;
    raw[SNP_OFF_FWD_NID  +: NODE_ID_W]    = flit.fwdNid[NODE_ID_W-1:0];
    raw[SNP_OFF_FWD_TXN_ID +: TXN_ID_W]   = flit.fwdTxnId;
    raw[SNP_OFF_STASH_LPID_VALID]         = flit.stashLpIdValid;
    raw[SNP_OFF_OPCODE   +: SNP_OPCODE_W] = flit.opcode;
    raw[SNP_OFF_ADDR     +: SNP_ADDR_W]   = flit.addr[ADDR_W-1:3];
    raw[SNP_OFF_PAS      +: PAS_W]        = flit.pas;
    raw[SNP_OFF_DO_NOT_GO_TO_SD]          = flit.doNotGoToSd;
    raw[SNP_OFF_RET_TO_SRC]               = flit.retToSrc;
    raw[SNP_OFF_TRACE_TAG]                = flit.traceTag;
    for (int unsigned i = 0; i < MPAM_W; i++)
      raw[SNP_OFF_MPAM + i] = flit.mpam[i];
    for (int unsigned i = 0; i < (MEC_EN ? MEC_ID_W : 0); i++)
      raw[SNP_OFF_MEC_ID + i] = flit.mecId[i];
    return raw;
  endfunction

  function automatic chiSnpFlitT unpackSnp(input chiRawFlitT raw);
    chiSnpFlitT flit;
    flit = '{default:'0, opcode:SNP_LCRD_RETURN};
    flit.qos            = raw[SNP_OFF_QOS +: QOS_W];
    flit.srcId          = chiNodeIdT'(raw[SNP_OFF_SRC_ID +: NODE_ID_W]);
    flit.txnId          = raw[SNP_OFF_TXN_ID +: TXN_ID_W];
    flit.fwdNid         = chiNodeIdT'(raw[SNP_OFF_FWD_NID +: NODE_ID_W]);
    flit.fwdTxnId       = raw[SNP_OFF_FWD_TXN_ID +: TXN_ID_W];
    flit.stashLpIdValid = raw[SNP_OFF_STASH_LPID_VALID];
    flit.opcode         = chiSnpOpcodeE'(raw[SNP_OFF_OPCODE +: SNP_OPCODE_W]);
    flit.addr           = chiAddrT'({raw[SNP_OFF_ADDR +: SNP_ADDR_W], 3'b000});
    flit.pas            = raw[SNP_OFF_PAS +: PAS_W];
    flit.doNotGoToSd    = raw[SNP_OFF_DO_NOT_GO_TO_SD];
    flit.retToSrc       = raw[SNP_OFF_RET_TO_SRC];
    flit.traceTag       = raw[SNP_OFF_TRACE_TAG];
    for (int unsigned i = 0; i < MPAM_W; i++)
      flit.mpam[i] = raw[SNP_OFF_MPAM + i];
    for (int unsigned i = 0; i < (MEC_EN ? MEC_ID_W : 0); i++)
      flit.mecId[i] = raw[SNP_OFF_MEC_ID + i];
    return flit;
  endfunction

  function automatic chiRawFlitT packDat(input chiDatFlitT flit);
    chiRawFlitT raw;
    raw = '0;
    raw[DAT_OFF_QOS         +: QOS_W]         = flit.qos;
    raw[DAT_OFF_TGT_ID      +: NODE_ID_W]     = flit.tgtId[NODE_ID_W-1:0];
    raw[DAT_OFF_SRC_ID      +: NODE_ID_W]     = flit.srcId[NODE_ID_W-1:0];
    raw[DAT_OFF_TXN_ID      +: TXN_ID_W]      = flit.txnId;
    raw[DAT_OFF_HOME_NID    +: NODE_ID_W]     = flit.homeNid[NODE_ID_W-1:0];
    raw[DAT_OFF_OPCODE      +: DAT_OPCODE_W]  = flit.opcode;
    raw[DAT_OFF_RESP_ERR    +: RESP_ERR_W]    = flit.respErr;
    raw[DAT_OFF_RESP        +: RESP_W]        = flit.resp;
    raw[DAT_OFF_DATA_SOURCE +: DATA_SOURCE_W] = flit.dataSource;
    raw[DAT_OFF_DATA_PULL]                    = flit.dataPull;
    raw[DAT_OFF_C_BUSY      +: C_BUSY_W]      = flit.cBusy;
    raw[DAT_OFF_DBID        +: TXN_ID_W]      = flit.dbId;
    raw[DAT_OFF_CC_ID       +: CC_ID_W]       = flit.ccId;
    raw[DAT_OFF_DATA_ID     +: DATA_ID_W]     = flit.dataId;
    raw[DAT_OFF_TAG_OP      +: TAG_OP_W]      = flit.tagOp;
    raw[DAT_OFF_TRACE_TAG]                    = flit.traceTag;
    for (int unsigned i = 0; i < TAG_W; i++)
      raw[DAT_OFF_TAG + i] = flit.tag[i];
    for (int unsigned i = 0; i < TAG_UPDATE_W; i++)
      raw[DAT_OFF_TAG_UPDATE + i] = flit.tagUpdate[i];
    for (int unsigned i = 0; i < POISON_W; i++)
      raw[DAT_OFF_POISON + i] = flit.poison[i];
    for (int unsigned i = 0; i < DATA_CHECK_W; i++)
      raw[DAT_OFF_DATA_CHECK + i] = flit.dataCheck[i];
    raw[DAT_OFF_BE   +: BE_W]   = flit.be;
    raw[DAT_OFF_DATA +: DATA_W] = flit.data;
    for (int unsigned i = 0; i < (MEC_EN ? MEC_ID_W : 0); i++)
      raw[DAT_OFF_MEC_ID + i] = flit.mecId[i];
    for (int unsigned i = 0; i < RSVDC_W; i++)
      raw[DAT_OFF_RSVDC + i] = flit.rsvdc[i];
    return raw;
  endfunction

  function automatic chiDatFlitT unpackDat(input chiRawFlitT raw);
    chiDatFlitT flit;
    flit = '{default:'0, opcode:DAT_LCRD_RETURN, respErr:RESP_ERR_OK};
    flit.qos        = raw[DAT_OFF_QOS +: QOS_W];
    flit.tgtId      = chiNodeIdT'(raw[DAT_OFF_TGT_ID +: NODE_ID_W]);
    flit.srcId      = chiNodeIdT'(raw[DAT_OFF_SRC_ID +: NODE_ID_W]);
    flit.txnId      = raw[DAT_OFF_TXN_ID +: TXN_ID_W];
    flit.homeNid    = chiNodeIdT'(raw[DAT_OFF_HOME_NID +: NODE_ID_W]);
    flit.opcode     = chiDatOpcodeE'(raw[DAT_OFF_OPCODE +: DAT_OPCODE_W]);
    flit.respErr    = chiRespErrE'(raw[DAT_OFF_RESP_ERR +: RESP_ERR_W]);
    flit.resp       = raw[DAT_OFF_RESP +: RESP_W];
    flit.dataSource = raw[DAT_OFF_DATA_SOURCE +: DATA_SOURCE_W];
    flit.dataPull   = raw[DAT_OFF_DATA_PULL];
    flit.cBusy      = raw[DAT_OFF_C_BUSY +: C_BUSY_W];
    flit.dbId       = raw[DAT_OFF_DBID +: TXN_ID_W];
    flit.ccId       = raw[DAT_OFF_CC_ID +: CC_ID_W];
    flit.dataId     = raw[DAT_OFF_DATA_ID +: DATA_ID_W];
    flit.tagOp      = raw[DAT_OFF_TAG_OP +: TAG_OP_W];
    flit.traceTag   = raw[DAT_OFF_TRACE_TAG];
    for (int unsigned i = 0; i < TAG_W; i++)
      flit.tag[i] = raw[DAT_OFF_TAG + i];
    for (int unsigned i = 0; i < TAG_UPDATE_W; i++)
      flit.tagUpdate[i] = raw[DAT_OFF_TAG_UPDATE + i];
    for (int unsigned i = 0; i < POISON_W; i++)
      flit.poison[i] = raw[DAT_OFF_POISON + i];
    for (int unsigned i = 0; i < DATA_CHECK_W; i++)
      flit.dataCheck[i] = raw[DAT_OFF_DATA_CHECK + i];
    flit.be   = raw[DAT_OFF_BE +: BE_W];
    flit.data = raw[DAT_OFF_DATA +: DATA_W];
    for (int unsigned i = 0; i < (MEC_EN ? MEC_ID_W : 0); i++)
      flit.mecId[i] = raw[DAT_OFF_MEC_ID + i];
    for (int unsigned i = 0; i < RSVDC_W; i++)
      flit.rsvdc[i] = raw[DAT_OFF_RSVDC + i];
    return flit;
  endfunction

  // An all-zero flit is that channel's L-Credit return on every channel,
  // because opcode 0 is *LCrdReturn and no other field is meaningful for it.
  // This is what lets the link layer drain credits before the field placement
  // in section 6 has been confirmed.
  // [SPEC:IHI0050H B13.7 L-Credit return]
  function automatic chiRawFlitT lcrdReturnFlit();
    return '0;
  endfunction

  function automatic bit isLcrdReturn(input chiChannelE channel,
                                      input chiRawFlitT raw);
    case (channel)
      CHI_CH_REQ: return raw[REQ_OFF_OPCODE +: REQ_OPCODE_W] == REQ_LCRD_RETURN;
      CHI_CH_RSP: return raw[RSP_OFF_OPCODE +: RSP_OPCODE_W] == RSP_LCRD_RETURN;
      CHI_CH_SNP: return raw[SNP_OFF_OPCODE +: SNP_OPCODE_W] == SNP_LCRD_RETURN;
      default:    return raw[DAT_OFF_OPCODE +: DAT_OPCODE_W] == DAT_LCRD_RETURN;
    endcase
  endfunction

  function automatic int unsigned flitWidthOfChannel(input chiChannelE channel);
    case (channel)
      CHI_CH_REQ: return REQ_FLIT_W;
      CHI_CH_RSP: return RSP_FLIT_W;
      CHI_CH_SNP: return SNP_FLIT_W;
      default:    return DAT_FLIT_W;
    endcase
  endfunction

  //----------------------------------------------------------------------------
  // 10. Flit parity
  //
  // The DUT checks TX<x>FLITCHK per byte with even parity, which differs from
  // my reading of the specification. Both the compliant and the observed
  // conventions are provided so that a directed test can drive either and the
  // difference can be reported rather than argued about.
  // [SPEC:IHI0050H B13.6 Flit protection] See OPEN QUESTIONS Q17.
  //----------------------------------------------------------------------------

  localparam int unsigned CHK_MAX_W = (FLIT_MAX_W + 7) / 8;

  function automatic logic [CHK_MAX_W-1:0] flitCheckEven(
      input chiRawFlitT raw, input int unsigned flitWidth);
    logic [CHK_MAX_W-1:0] chk;
    logic parity;
    chk = '0;
    for (int unsigned byteIndex = 0; byteIndex < ((flitWidth + 7) / 8); byteIndex++) begin
      parity = 1'b0;
      for (int unsigned bitIndex = 0; bitIndex < 8; bitIndex++)
        if (((byteIndex * 8) + bitIndex) < flitWidth)
          parity ^= raw[(byteIndex * 8) + bitIndex];
      chk[byteIndex] = parity;
    end
    return chk;
  endfunction

  function automatic logic [CHK_MAX_W-1:0] flitCheckOdd(
      input chiRawFlitT raw, input int unsigned flitWidth);
    logic [CHK_MAX_W-1:0] chk;
    chk = ~flitCheckEven(raw, flitWidth);
    for (int unsigned byteIndex = ((flitWidth + 7) / 8); byteIndex < CHK_MAX_W; byteIndex++)
      chk[byteIndex] = 1'b0;
    return chk;
  endfunction

  //----------------------------------------------------------------------------
  // 11. Memory initialisation pattern
  //
  // Deterministic and address-derived so that the Subordinate memory model and
  // the scoreboard's independent memory model agree on the value of a location
  // that has never been written, without either seeding the other.
  //----------------------------------------------------------------------------

  function automatic logic [63:0] chiMemInitData(input chiAddrT addr);
    logic [63:0] value;
    value = {addr[31:0] ^ 32'hA5A5_5A5A, addr[31:0] + 32'h1234_5678};
    value[2:0] = 3'b0;
    value[2:0] = addr[5:3];
    return value;
  endfunction

  function automatic string nodeClassName(input chiNodeClassE nodeClass);
    case (nodeClass)
      RN_F: return "RN-F";
      RN_D: return "RN-D";
      RN_I: return "RN-I";
      SN_F: return "SN-F";
      default: return "SN-I";
    endcase
  endfunction

  function automatic string channelName(input chiChannelE channel);
    case (channel)
      CHI_CH_REQ: return "REQ";
      CHI_CH_RSP: return "RSP";
      CHI_CH_SNP: return "SNP";
      default: return "DAT";
    endcase
  endfunction

  //----------------------------------------------------------------------------
  // 12. config_db key contract
  //
  // Both tops build their keys from these functions so that a typo cannot make
  // one side publish a key the other never looks up. Every get failure on the
  // HVL side raises uvm_fatal naming the key it asked for.
  //----------------------------------------------------------------------------

  function automatic string clkRstBfmKey();
    return "chiClkRstBfm";
  endfunction

  function automatic string requesterDriverBfmKey(input int unsigned ordinal);
    return $sformatf("chiRequesterDriverBfm[%0d]", ordinal);
  endfunction

  function automatic string subordinateDriverBfmKey(input int unsigned ordinal);
    return $sformatf("chiSubordinateDriverBfm[%0d]", ordinal);
  endfunction

  function automatic string monitorBfmKey(input int unsigned ordinal);
    return $sformatf("chiMonitorBfm[%0d]", ordinal);
  endfunction

endpackage : chiGlobalsPkg
