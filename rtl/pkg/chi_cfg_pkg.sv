package chi_cfg_pkg;
  localparam int unsigned CHI_MIN_NODEID_W = 7;
  localparam int unsigned CHI_MAX_NODEID_W = 16;
  localparam int unsigned CHI_MIN_ADDR_W   = 44;
  localparam int unsigned CHI_MAX_ADDR_W   = 52;
  localparam int unsigned CHI_MIN_TXNID_W  = 8;
  localparam int unsigned CHI_MAX_TXNID_W  = 12;
  localparam int unsigned CHI_MIN_LPID_W   = 1;
  localparam int unsigned CHI_MAX_LPID_W   = 5;
  localparam int unsigned CHI_MIN_CCID_W   = 1;
  localparam int unsigned CHI_MAX_CCID_W   = 2;
  localparam int unsigned CHI_MIN_GROUPID_W = 1;
  localparam int unsigned CHI_MAX_GROUPID_W = 8;
  localparam int unsigned CHI_MAX_RSVDC_W  = 32;
  localparam int unsigned CHI_MECID_W      = 16;
  localparam int unsigned CHI_MPAM_W       = 15;
  localparam int unsigned CHI_MPAM_SHORT_W = 12;

  // Issue H fixes these flit slot widths independently of the node-side
  // field widths a node chooses to use (IHI 0050H B13.9.1-B13.9.4).
  // Internal node-identifier buses carry the widest legal NodeID so that one
  // width applies to every flit slot, parameter table, and internal port.
  localparam int unsigned CHI_NODEID_SLOT_W   = CHI_MAX_NODEID_W;
  localparam int unsigned CHI_TXNID_FLIT_W    = 12;
  localparam int unsigned CHI_RTNTXNID_SLOT_W = 12;
  localparam int unsigned CHI_NUMREQ_SLOT_W   = 6;
  localparam int unsigned CHI_GROUPID_SLOT_W  = 8;
  localparam int unsigned CHI_PAS_W           = 3;
  localparam int unsigned CHI_CACHELINEID_W   = 6;
  localparam int unsigned CHI_PBHA_W          = 4;
  localparam int unsigned CHI_STREAMID_W      = 16;
  localparam int unsigned CHI_DATASOURCE_W    = 8;
  localparam int unsigned CHI_CCID_SLOT_W     = 2;
  localparam int unsigned CHI_DATAID_SLOT_W   = 2;
  localparam int unsigned CHI_RSP_DBID_SLOT_W = 12;
  localparam int unsigned CHI_DAT_DBID_SLOT_W = 16;

  // Request Retry supports up to 16 P-Credit types (IHI 0050H B2.10). The
  // Home Node partitions its credits by request category, so it uses four.
  localparam int unsigned CHI_MAX_CREDIT_TYPES = 16;
  localparam int unsigned CHI_CREDIT_TYPES     = 4;

  typedef enum logic [1:0] {
    CROSSBAR = 2'b00,
    RING     = 2'b01,
    MESH_2D  = 2'b10
  } chi_topology_e;

  typedef enum logic [1:0] {
    CFG_PARAM_ONLY = 2'b00,
    CFG_APB        = 2'b01,
    CFG_CHI_MMIO   = 2'b10
  } chi_cfg_access_e;

  typedef enum logic [3:0] {
    NODE_RNF = 4'd0,
    NODE_RND = 4'd1,
    NODE_RNI = 4'd2,
    NODE_SNF = 4'd3,
    NODE_SNI = 4'd4,
    NODE_HNF = 4'd5,
    NODE_HNI = 4'd6,
    NODE_MN  = 4'd7
  } chi_node_class_e;

  typedef enum logic [1:0] {
    SAM_REGION_HNF_HASH = 2'b00,
    SAM_REGION_DIRECT   = 2'b01,
    SAM_REGION_MMIO     = 2'b10
  } chi_sam_region_kind_e;

  // How each HN-F is paired with the SN-F that holds its memory: HN-F i to
  // SN-F i % numSnf, or an explicit table given by the HNF_TO_SNF top
  // parameter.
  typedef enum logic [0:0] {
    HNF_SNF_MAP_MODULO = 1'b0,
    HNF_SNF_MAP_TABLE  = 1'b1
  } chi_hnf_snf_map_e;

  // Run-time policy of one HN-F, written over APB and committed only while the
  // fabric is quiescent. Each enable is ANDed with the elaboration-time global
  // enable and with the capability of the node concerned, so a policy bit can
  // only narrow what the configuration permits.
  typedef struct packed {
    logic       reserved;
    logic       slcAllocStash;   // stash with no valid target may allocate
    logic       slcAllocEvict;   // clean eviction may allocate clean
    logic       slcAllocWrite;   // write and CopyBack data may allocate
    logic       slcAllocRead;    // read miss may allocate
    logic       dwtEn;
    logic       dmtEn;
    logic       dctEn;
  } chi_hnf_policy_t;

  localparam chi_hnf_policy_t CHI_HNF_POLICY_DEFAULT = '{
    reserved: 1'b0, slcAllocStash: 1'b1, slcAllocEvict: 1'b1,
    slcAllocWrite: 1'b1, slcAllocRead: 1'b1,
    dwtEn: 1'b1, dmtEn: 1'b1, dctEn: 1'b1
  };

  typedef struct packed {
    int unsigned        numRnf;
    int unsigned        numRnd;
    int unsigned        numRni;
    int unsigned        numSnf;
    int unsigned        numSni;
    int unsigned        numHnf;
    int unsigned        numHni;
    int unsigned        numMn;
    int unsigned        dataW;
    int unsigned        addrW;
    int unsigned        nodeIdW;
    int unsigned        txnIdW;
    int unsigned        lpidW;
    int unsigned        rsvdcW;
    int unsigned        ccidW;
    int unsigned        groupIdW;
    int unsigned        mpamW;
    // These counts are integration metadata. One interface instance represents
    // one physical CHI interface; later top-level RTL can create arrays/replicas.
    int unsigned        numIfPerNode;
    int unsigned        replChannels;
    chi_topology_e      topology;
    int unsigned        meshX;
    int unsigned        meshY;
    // Crosspoint count of a RING or CROSSBAR; a mesh uses meshX * meshY.
    int unsigned        numXp;
    int unsigned        numDevPortsPerXp;
    int unsigned        snpFilterEntries;
    int unsigned        snpFilterWays;
    int unsigned        posEntries;
    int unsigned        retryRecords;
    int unsigned        lcrdDepth;
    int unsigned        exclMonitors;
    int unsigned        interleaveGranule;
    int unsigned        hnHashShift;
    logic               dataCheckEn;
    logic               poisonEn;
    logic               parityEn;
    logic               mpamEn;
    logic               mteEn;
    logic               mecEn;
    logic               pbhaEn;
    logic               cdaEn;
    logic               multiReqEn;
    logic               dctEn;
    logic               dmtEn;
    logic               dwtEn;
    logic               atomicEn;
    logic               dvmEn;
    logic               stashEn;
    logic               exclEn;
    chi_cfg_access_e    cfgAccess;
    chi_hnf_snf_map_e   hnfSnfMap;
  } chi_cfg_t;

  localparam chi_cfg_t CHI_CFG_DEFAULT = '{
    numRnf: 4, numRnd: 0, numRni: 1,
    numSnf: 2, numSni: 1, numHnf: 4, numHni: 1, numMn: 1,
    dataW: 256, addrW: 48, nodeIdW: 11, txnIdW: 12,
    lpidW: 5, rsvdcW: 0, ccidW: 2, groupIdW: 8, mpamW: 0,
    numIfPerNode: 1, replChannels: 1,
    topology: MESH_2D, meshX: 3, meshY: 3, numXp: 4, numDevPortsPerXp: 2,
    snpFilterEntries: 1024, snpFilterWays: 4,
    posEntries: 32, retryRecords: 16, lcrdDepth: 8, exclMonitors: 32,
    interleaveGranule: 64, hnHashShift: 6,
    dataCheckEn: 1'b1, poisonEn: 1'b1, parityEn: 1'b0,
    mpamEn: 1'b0, mteEn: 1'b0, mecEn: 1'b0,
    pbhaEn: 1'b0, cdaEn: 1'b0, multiReqEn: 1'b0,
    dctEn: 1'b1, dmtEn: 1'b1, dwtEn: 1'b1,
    atomicEn: 1'b1, dvmEn: 1'b1, stashEn: 1'b1, exclEn: 1'b1,
    cfgAccess: CFG_PARAM_ONLY, hnfSnfMap: HNF_SNF_MAP_MODULO
  };

  typedef struct packed {
    logic [CHI_MAX_ADDR_W-1:0] baseAddr;
    logic [CHI_MAX_ADDR_W-1:0] limitAddr;
    logic [CHI_MAX_NODEID_W-1:0] targetNodeId;
    chi_sam_region_kind_e      kind;
    logic                      secureOnly;
    logic                      valid;
  } chi_sam_region_t;

  // Where one node attaches to the fabric. For MESH_2D, meshX and meshY are
  // the crosspoint coordinates. For RING and CROSSBAR, meshX is the crosspoint
  // index and meshY must be zero. The type keeps its historical name because
  // the PLACEMENTS top parameter is declared with it.
  typedef struct packed {
    chi_node_class_e nodeClass;
    logic [7:0]      nodeIndex;
    logic [7:0]      meshX;
    logic [7:0]      meshY;
    logic [7:0]      devicePort;
    logic            valid;
  } chi_mesh_placement_t;

  // The fixed placement the 14-node default population used before automatic
  // placement existed. It is kept so that existing integrations can still pass
  // it through PLACEMENTS; the product top no longer uses it.
  function automatic chi_mesh_placement_t defaultMeshPlacement(input int unsigned ordinal);
    chi_mesh_placement_t placement;
    placement = '0;
    placement.valid = 1'b1;
    case (ordinal)
      0:  begin placement.nodeClass = NODE_RNF; placement.nodeIndex = 0; placement.meshX = 0; placement.meshY = 0; placement.devicePort = 1; end
      1:  begin placement.nodeClass = NODE_RNF; placement.nodeIndex = 1; placement.meshX = 1; placement.meshY = 0; placement.devicePort = 1; end
      2:  begin placement.nodeClass = NODE_RNF; placement.nodeIndex = 2; placement.meshX = 0; placement.meshY = 1; placement.devicePort = 1; end
      3:  begin placement.nodeClass = NODE_RNF; placement.nodeIndex = 3; placement.meshX = 2; placement.meshY = 1; placement.devicePort = 1; end
      4:  begin placement.nodeClass = NODE_RNI; placement.nodeIndex = 0; placement.meshX = 2; placement.meshY = 0; placement.devicePort = 1; end
      5:  begin placement.nodeClass = NODE_SNF; placement.nodeIndex = 0; placement.meshX = 1; placement.meshY = 0; placement.devicePort = 0; end
      6:  begin placement.nodeClass = NODE_SNF; placement.nodeIndex = 1; placement.meshX = 2; placement.meshY = 1; placement.devicePort = 0; end
      7:  begin placement.nodeClass = NODE_SNI; placement.nodeIndex = 0; placement.meshX = 0; placement.meshY = 1; placement.devicePort = 0; end
      8:  begin placement.nodeClass = NODE_HNF; placement.nodeIndex = 0; placement.meshX = 0; placement.meshY = 0; placement.devicePort = 0; end
      9:  begin placement.nodeClass = NODE_HNF; placement.nodeIndex = 1; placement.meshX = 2; placement.meshY = 0; placement.devicePort = 0; end
      10: begin placement.nodeClass = NODE_HNF; placement.nodeIndex = 2; placement.meshX = 0; placement.meshY = 2; placement.devicePort = 0; end
      11: begin placement.nodeClass = NODE_HNF; placement.nodeIndex = 3; placement.meshX = 2; placement.meshY = 2; placement.devicePort = 0; end
      12: begin placement.nodeClass = NODE_HNI; placement.nodeIndex = 0; placement.meshX = 1; placement.meshY = 1; placement.devicePort = 1; end
      13: begin placement.nodeClass = NODE_MN;  placement.nodeIndex = 0; placement.meshX = 1; placement.meshY = 1; placement.devicePort = 0; end
      default: placement.valid = 1'b0;
    endcase
    return placement;
  endfunction

  typedef chi_mesh_placement_t chi_default_placement_array_t [13:0];

  function automatic chi_default_placement_array_t defaultMeshPlacements();
    chi_default_placement_array_t placements;
    for (int unsigned ordinal = 0; ordinal < 14; ordinal++)
      placements[ordinal] = defaultMeshPlacement(ordinal);
    return placements;
  endfunction

  function automatic chi_node_class_e nodeClassForOrdinal(
    input chi_cfg_t cfg,
    input int unsigned ordinal
  );
    int unsigned boundary;
    boundary = cfg.numRnf;
    if (ordinal < boundary) return NODE_RNF;
    boundary += cfg.numRnd;
    if (ordinal < boundary) return NODE_RND;
    boundary += cfg.numRni;
    if (ordinal < boundary) return NODE_RNI;
    boundary += cfg.numSnf;
    if (ordinal < boundary) return NODE_SNF;
    boundary += cfg.numSni;
    if (ordinal < boundary) return NODE_SNI;
    boundary += cfg.numHnf;
    if (ordinal < boundary) return NODE_HNF;
    boundary += cfg.numHni;
    if (ordinal < boundary) return NODE_HNI;
    return NODE_MN;
  endfunction

  function automatic int unsigned nodeIndexForOrdinal(
    input chi_cfg_t cfg,
    input int unsigned ordinal
  );
    int unsigned base;
    base = 0;
    if (ordinal < cfg.numRnf) return ordinal;
    base += cfg.numRnf;
    if (ordinal < (base + cfg.numRnd)) return ordinal - base;
    base += cfg.numRnd;
    if (ordinal < (base + cfg.numRni)) return ordinal - base;
    base += cfg.numRni;
    if (ordinal < (base + cfg.numSnf)) return ordinal - base;
    base += cfg.numSnf;
    if (ordinal < (base + cfg.numSni)) return ordinal - base;
    base += cfg.numSni;
    if (ordinal < (base + cfg.numHnf)) return ordinal - base;
    base += cfg.numHnf;
    if (ordinal < (base + cfg.numHni)) return ordinal - base;
    base += cfg.numHni;
    return ordinal - base;
  endfunction
endpackage
