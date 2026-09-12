package chi_cfg_pkg;
  localparam int unsigned CHI_MIN_NODEID_W = 7;
  localparam int unsigned CHI_MAX_NODEID_W = 11;
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
    // These counts are integration metadata. One interface instance represents
    // one physical CHI interface; later top-level RTL can create arrays/replicas.
    int unsigned        numIfPerNode;
    int unsigned        replChannels;
    chi_topology_e      topology;
    int unsigned        meshX;
    int unsigned        meshY;
    int unsigned        numDevPortsPerXp;
    int unsigned        snpFilterEntries;
    int unsigned        snpFilterWays;
    int unsigned        posEntries;
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
    logic               dctEn;
    logic               dmtEn;
    logic               dwtEn;
    logic               atomicEn;
    logic               dvmEn;
    logic               stashEn;
    logic               exclEn;
    chi_cfg_access_e    cfgAccess;
  } chi_cfg_t;

  localparam chi_cfg_t CHI_CFG_DEFAULT = '{
    numRnf: 4, numRnd: 0, numRni: 1,
    numSnf: 2, numSni: 1, numHnf: 4, numHni: 1, numMn: 1,
    dataW: 256, addrW: 48, nodeIdW: 11, txnIdW: 12,
    lpidW: 5, rsvdcW: 0, ccidW: 2, groupIdW: 8,
    numIfPerNode: 1, replChannels: 1,
    topology: MESH_2D, meshX: 3, meshY: 3, numDevPortsPerXp: 2,
    snpFilterEntries: 1024, snpFilterWays: 4,
    posEntries: 32, lcrdDepth: 8, exclMonitors: 32,
    interleaveGranule: 64, hnHashShift: 6,
    dataCheckEn: 1'b1, poisonEn: 1'b1, parityEn: 1'b0,
    mpamEn: 1'b0, mteEn: 1'b0, mecEn: 1'b0,
    dctEn: 1'b1, dmtEn: 1'b1, dwtEn: 1'b1,
    atomicEn: 1'b1, dvmEn: 1'b1, stashEn: 1'b1, exclEn: 1'b1,
    cfgAccess: CFG_PARAM_ONLY
  };

  typedef struct packed {
    logic [CHI_MAX_ADDR_W-1:0] baseAddr;
    logic [CHI_MAX_ADDR_W-1:0] limitAddr;
    logic [CHI_MAX_NODEID_W-1:0] targetNodeId;
    chi_sam_region_kind_e      kind;
    logic                      secureOnly;
    logic                      valid;
  } chi_sam_region_t;

  typedef struct packed {
    chi_node_class_e nodeClass;
    logic [7:0]      nodeIndex;
    logic [7:0]      meshX;
    logic [7:0]      meshY;
    logic [7:0]      devicePort;
    logic            valid;
  } chi_mesh_placement_t;

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
endpackage
