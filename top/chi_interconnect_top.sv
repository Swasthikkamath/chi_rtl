module chi_interconnect_top #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned AGE_LIMIT = 16,
  parameter int unsigned NUM_REGIONS = 4,
  parameter int unsigned NUM_NODES =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni
    + CFG.numHnf + CFG.numHni + CFG.numMn,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    NODE_IDS [NUM_NODES-1:0] = '{default:'1},
  parameter bit USE_DEFAULT_PLACEMENTS = 1'b1,
  parameter chi_cfg_pkg::chi_mesh_placement_t
    PLACEMENTS [NUM_NODES-1:0] = '{default:'0},
  parameter logic [CFG.addrW-1:0] CFG_MMIO_BASE =
    {CFG.addrW{1'b1}} - CFG.addrW'(12'hfff),
  parameter bit USE_DEFAULT_REGIONS = 1'b1,
  parameter logic [CFG.addrW-1:0]
    REGION_BASE [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [CFG.addrW-1:0]
    REGION_LIMIT [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]
    REGION_TARGET [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [3:0]
    REGION_ATTRIBUTES [NUM_REGIONS-1:0] = '{default:'0}
) (
  input logic clk,
  input logic resetn,
  chi_if rnf [(CFG.numRnf > 0 ? CFG.numRnf : 1)-1:0],
  chi_if rnd [(CFG.numRnd > 0 ? CFG.numRnd : 1)-1:0],
  chi_if rni [(CFG.numRni > 0 ? CFG.numRni : 1)-1:0],
  chi_if snf [(CFG.numSnf > 0 ? CFG.numSnf : 1)-1:0],
  chi_if sni [(CFG.numSni > 0 ? CFG.numSni : 1)-1:0],
  input  logic [11:0] PADDR,
  input  logic PSEL,
  input  logic PENABLE,
  input  logic PWRITE,
  input  logic [31:0] PWDATA,
  input  logic [3:0] PSTRB,
  input  logic [2:0] PPROT,
  output logic [31:0] PRDATA,
  output logic PREADY,
  output logic PSLVERR
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_REQ =
    CFG.numRnf + CFG.numRnd + CFG.numRni;
  localparam int unsigned NUM_REQ_E = (NUM_REQ > 0) ? NUM_REQ : 1;
  localparam int unsigned NUM_DVM = (NUM_REQ > 0) ? NUM_REQ : 1;
  localparam int unsigned NUM_HNF_E = (CFG.numHnf > 0) ? CFG.numHnf : 1;
  localparam int unsigned NUM_SNF_E = (CFG.numSnf > 0) ? CFG.numSnf : 1;
  localparam int unsigned NUM_HNI_E = (CFG.numHni > 0) ? CFG.numHni : 1;
  localparam int unsigned OFF_RNF = 0;
  localparam int unsigned OFF_RND = OFF_RNF + CFG.numRnf;
  localparam int unsigned OFF_RNI = OFF_RND + CFG.numRnd;
  localparam int unsigned OFF_SNF = OFF_RNI + CFG.numRni;
  localparam int unsigned OFF_SNI = OFF_SNF + CFG.numSnf;
  localparam int unsigned OFF_HNF = OFF_SNI + CFG.numSni;
  localparam int unsigned OFF_HNI = OFF_HNF + CFG.numHnf;
  localparam int unsigned OFF_MN  = OFF_HNI + CFG.numHni;

  typedef logic [CHI_MAX_NODEID_W-1:0] node_id_array_t [NUM_NODES-1:0];
  typedef logic [CHI_MAX_NODEID_W-1:0] hnf_id_array_t [NUM_HNF_E-1:0];
  typedef logic [CHI_MAX_NODEID_W-1:0] snf_id_array_t [NUM_SNF_E];
  typedef logic [CHI_MAX_NODEID_W-1:0]
    rnf_id_array_t [(CFG.numRnf > 0 ? CFG.numRnf : 1)-1:0];
  typedef logic [CHI_MAX_NODEID_W-1:0] dvm_id_array_t [NUM_DVM-1:0];
  typedef logic [CFG.addrW-1:0] region_addr_array_t [NUM_REGIONS-1:0];
  typedef logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] region_target_array_t [NUM_REGIONS-1:0];
  typedef logic [3:0] region_attr_array_t [NUM_REGIONS-1:0];

  function automatic node_id_array_t makeNodeIds();
    node_id_array_t values;
    for (int unsigned i = 0; i < NUM_NODES; i++) begin
      if (NODE_IDS[i] == {CHI_MAX_NODEID_W{1'b1}})
        values[i] = defaultNodeId(CFG, i);
      else
        values[i] = NODE_IDS[i];
    end
    return values;
  endfunction

  function automatic chi_mesh_placement_t effectivePlacement(
    input int unsigned ordinal
  );
    if (USE_DEFAULT_PLACEMENTS)
      return defaultMeshPlacement(ordinal);
    return PLACEMENTS[ordinal];
  endfunction

  function automatic hnf_id_array_t makeHnfIds(input node_id_array_t ids);
    hnf_id_array_t values;
    for (int unsigned i = 0; i < NUM_HNF_E; i++)
      values[i] = (i < CFG.numHnf) ? ids[OFF_HNF+i] : '0;
    return values;
  endfunction

  function automatic snf_id_array_t makeSnfIds(input node_id_array_t ids);
    snf_id_array_t values;
    for (int unsigned i = 0; i < NUM_SNF_E; i++)
      values[i] = (i < CFG.numSnf) ? ids[OFF_SNF+i] : '0;
    return values;
  endfunction

  function automatic rnf_id_array_t makeRnfIds(input node_id_array_t ids);
    rnf_id_array_t values;
    for (int unsigned i = 0;
         i < (CFG.numRnf > 0 ? CFG.numRnf : 1); i++)
      values[i] = (i < CFG.numRnf) ? ids[OFF_RNF+i] : '0;
    return values;
  endfunction

  function automatic dvm_id_array_t makeDvmIds(input node_id_array_t ids);
    dvm_id_array_t values;
    for (int unsigned i = 0; i < NUM_DVM; i++)
      values[i] = (i < NUM_REQ) ? ids[i] : '0;
    return values;
  endfunction

  function automatic region_addr_array_t makeRegionBase();
    region_addr_array_t values;
    values = REGION_BASE;
    if (USE_DEFAULT_REGIONS) begin
      values = '{default:'0};
      if (NUM_REGIONS > 1)
        values[1] = {1'b1, {(CFG.addrW-1){1'b0}}};
      if (NUM_REGIONS > 2)
        values[2] = CFG_MMIO_BASE;
    end
    return values;
  endfunction

  function automatic region_addr_array_t makeRegionLimit();
    region_addr_array_t values;
    values = REGION_LIMIT;
    if (USE_DEFAULT_REGIONS) begin
      values = '{default:'0};
      values[0] = {1'b0, {(CFG.addrW-1){1'b1}}};
      if (NUM_REGIONS > 1)
        values[1] = CFG_MMIO_BASE - 1'b1;
      if (NUM_REGIONS > 2)
        values[2] = {CFG.addrW{1'b1}};
    end
    return values;
  endfunction

  function automatic region_target_array_t makeRegionTarget(
    input node_id_array_t ids
  );
    region_target_array_t values;
    values = REGION_TARGET;
    if (USE_DEFAULT_REGIONS) begin
      values = '{default:'0};
      if ((NUM_REGIONS > 1) && (CFG.numHni > 0))
        values[1] = ids[OFF_HNI];
      if ((NUM_REGIONS > 2) && (CFG.numHni > 0))
        values[2] = ids[OFF_HNI];
    end
    return values;
  endfunction

  function automatic region_attr_array_t makeRegionAttributes();
    region_attr_array_t values;
    values = REGION_ATTRIBUTES;
    if (USE_DEFAULT_REGIONS) begin
      values = '{default:'0};
      values[0] = {SAM_REGION_HNF_HASH, 1'b0, 1'b1};
      if (NUM_REGIONS > 1)
        values[1] = {SAM_REGION_DIRECT, 1'b0, 1'b1};
      if (NUM_REGIONS > 2)
        values[2] = {SAM_REGION_MMIO, 1'b0, 1'b1};
    end
    return values;
  endfunction

  function automatic chi_noc_flit_t reqToNoc(
    input logic [CHI_MAX_REQ_FLIT_W-1:0] payload,
    input logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] samTarget
  );
    chi_noc_flit_t value;
    chi_req_flit_t request;
    request = unpackReqFlit(CFG, payload);
    request.tgtId = samTarget;
    value = '0;
    value.channel = CHI_CHANNEL_REQ;
    value.qos = request.qos;
    value.targetNodeId = samTarget;
    value.payload[CHI_MAX_REQ_FLIT_W-1:0] = packReqFlit(CFG, request);
    return value;
  endfunction

  function automatic chi_noc_flit_t rspToNoc(
    input logic [CHI_MAX_RSP_FLIT_W-1:0] payload
  );
    chi_noc_flit_t value;
    chi_rsp_flit_t response;
    response = unpackRspFlit(CFG, payload);
    value = '0;
    value.channel = CHI_CHANNEL_RSP;
    value.qos = response.qos;
    value.targetNodeId = response.tgtId;
    value.payload[CHI_MAX_RSP_FLIT_W-1:0] = payload;
    return value;
  endfunction

  function automatic chi_noc_flit_t datToNoc(
    input logic [CHI_MAX_DAT_FLIT_W-1:0] payload
  );
    chi_noc_flit_t value;
    chi_dat_flit_t dataFlit;
    dataFlit = unpackDatFlit(CFG, payload);
    value = '0;
    value.channel = CHI_CHANNEL_DAT;
    value.qos = dataFlit.qos;
    value.targetNodeId = dataFlit.tgtId;
    value.payload[CHI_MAX_DAT_FLIT_W-1:0] = payload;
    return value;
  endfunction

  localparam node_id_array_t EFFECTIVE_NODE_IDS = makeNodeIds();
  localparam hnf_id_array_t HNF_NODE_IDS = makeHnfIds(EFFECTIVE_NODE_IDS);
  localparam snf_id_array_t SNF_NODE_IDS = makeSnfIds(EFFECTIVE_NODE_IDS);
  localparam rnf_id_array_t RNF_NODE_IDS = makeRnfIds(EFFECTIVE_NODE_IDS);
  localparam dvm_id_array_t DVM_NODE_IDS = makeDvmIds(EFFECTIVE_NODE_IDS);
  localparam region_addr_array_t EFFECTIVE_REGION_BASE = makeRegionBase();
  localparam region_addr_array_t EFFECTIVE_REGION_LIMIT = makeRegionLimit();
  localparam region_target_array_t EFFECTIVE_REGION_TARGET =
    makeRegionTarget(EFFECTIVE_NODE_IDS);
  localparam region_attr_array_t EFFECTIVE_REGION_ATTRIBUTES =
    makeRegionAttributes();
  localparam chi_default_placement_array_t DEFAULT_PLACEMENTS = '{
    0: defaultMeshPlacement(0), 1: defaultMeshPlacement(1),
    2: defaultMeshPlacement(2), 3: defaultMeshPlacement(3),
    4: defaultMeshPlacement(4), 5: defaultMeshPlacement(5),
    6: defaultMeshPlacement(6), 7: defaultMeshPlacement(7),
    8: defaultMeshPlacement(8), 9: defaultMeshPlacement(9),
    10: defaultMeshPlacement(10), 11: defaultMeshPlacement(11),
    12: defaultMeshPlacement(12), 13: defaultMeshPlacement(13)
  };

  logic [NUM_NODES-1:0] reqInValid;
  logic [NUM_NODES-1:0] reqInReady;
  chi_noc_flit_t reqInFlit [NUM_NODES-1:0];
  logic [NUM_NODES-1:0] reqOutValid;
  logic [NUM_NODES-1:0] reqOutReady;
  chi_noc_flit_t reqOutFlit [NUM_NODES-1:0];
  logic [NUM_NODES-1:0] rspInValid;
  logic [NUM_NODES-1:0] rspInReady;
  chi_noc_flit_t rspInFlit [NUM_NODES-1:0];
  logic [NUM_NODES-1:0] rspOutValid;
  logic [NUM_NODES-1:0] rspOutReady;
  chi_noc_flit_t rspOutFlit [NUM_NODES-1:0];
  logic [NUM_NODES-1:0] snpInValid;
  logic [NUM_NODES-1:0] snpInReady;
  chi_noc_flit_t snpInFlit [NUM_NODES-1:0];
  logic [NUM_NODES-1:0] snpOutValid;
  logic [NUM_NODES-1:0] snpOutReady;
  chi_noc_flit_t snpOutFlit [NUM_NODES-1:0];
  logic [NUM_NODES-1:0] datInValid;
  logic [NUM_NODES-1:0] datInReady;
  chi_noc_flit_t datInFlit [NUM_NODES-1:0];
  logic [NUM_NODES-1:0] datOutValid;
  logic [NUM_NODES-1:0] datOutReady;
  chi_noc_flit_t datOutFlit [NUM_NODES-1:0];

  logic [NUM_REQ_E-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requesterSamTarget;
  logic [NUM_REQ_E-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requesterRouteTarget;
  logic [NUM_REQ_E-1:0][chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] requesterPrefetchTarget;
  logic [NUM_REQ_E-1:0][3:0] requesterSamAttributes;
  logic [NUM_REQ_E-1:0] requesterSamError;
  chi_req_flit_t requesterReq [NUM_REQ_E-1:0];
  logic [CHI_MAX_REQ_FLIT_W-1:0] requesterRawReq [NUM_REQ_E-1:0];

  logic apbRegionUpdate;
  logic [clog2Min1(NUM_REGIONS)-1:0] apbRegionUpdateIndex;
  logic [CFG.addrW-1:0] apbRegionUpdateBase;
  logic [CFG.addrW-1:0] apbRegionUpdateLimit;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] apbRegionUpdateTarget;
  logic [3:0] apbRegionUpdateAttributes;
  logic selectedRegionUpdate;
  logic [clog2Min1(NUM_REGIONS)-1:0] selectedRegionUpdateIndex;
  logic [CFG.addrW-1:0] selectedRegionUpdateBase;
  logic [CFG.addrW-1:0] selectedRegionUpdateLimit;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] selectedRegionUpdateTarget;
  logic [3:0] selectedRegionUpdateAttributes;
  logic [NUM_HNI_E-1:0] mmioRegionUpdate;
  logic [clog2Min1(NUM_REGIONS)-1:0]
    mmioRegionUpdateIndex [NUM_HNI_E-1:0];
  logic [CFG.addrW-1:0] mmioRegionUpdateBase [NUM_HNI_E-1:0];
  logic [CFG.addrW-1:0] mmioRegionUpdateLimit [NUM_HNI_E-1:0];
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] mmioRegionUpdateTarget [NUM_HNI_E-1:0];
  logic [3:0] mmioRegionUpdateAttributes [NUM_HNI_E-1:0];
  logic [NUM_HNI_E-1:0] hniIdle;
  logic [(CFG.numHnf > 0 ? CFG.numHnf : 1)-1:0] hnfIdle;
  logic [(CFG.numMn > 0 ? CFG.numMn : 1)-1:0] mnIdle;
  logic trafficQuiescent;

  generate
    begin : chi_cfg_check
      initial begin
        chi_mesh_placement_t placement;
        if (!((CFG.dataW == 128) || (CFG.dataW == 256)
              || (CFG.dataW == 512)))
          $fatal(1, "DATA width must be 128, 256, or 512");
        if ((CFG.addrW < CHI_MIN_ADDR_W) || (CFG.addrW > CHI_MAX_ADDR_W)
            || (CFG.nodeIdW < CHI_MIN_NODEID_W)
            || (CFG.nodeIdW > CHI_MAX_NODEID_W)
            || (CFG.txnIdW < CHI_MIN_TXNID_W)
            || (CFG.txnIdW > CHI_MAX_TXNID_W)
            || (CFG.lpidW < CHI_MIN_LPID_W)
            || (CFG.lpidW > CHI_MAX_LPID_W)
            || (CFG.ccidW < CHI_MIN_CCID_W)
            || (CFG.ccidW > CHI_MAX_CCID_W)
            || (CFG.groupIdW < CHI_MIN_GROUPID_W)
            || (CFG.groupIdW > CHI_MAX_GROUPID_W))
          $fatal(1, "CHI field width is outside its supported range");
        if (!((CFG.rsvdcW == 0) || (CFG.rsvdcW == 4)
              || (CFG.rsvdcW == 8) || (CFG.rsvdcW == 12)
              || (CFG.rsvdcW == 16) || (CFG.rsvdcW == 24)
              || (CFG.rsvdcW == 32)))
          $fatal(1, "Unsupported RSVDC width");
        if ((CFG.numIfPerNode != 1) || (CFG.replChannels != 1))
          $fatal(1, "Only one interface and one channel replica are supported");
        if (!((CFG.mpamW == 0) || (CFG.mpamW == CHI_MPAM_SHORT_W)
              || (CFG.mpamW == CHI_MPAM_W)))
          $fatal(1, "MPAM width must be 0, 12, or 15");
        if (CFG.mpamEn && (CFG.mpamW == 0))
          $fatal(1, "Enabling MPAM requires a 12-bit or 15-bit MPAM bus");
        // MECID and StreamID share one REQ field of width Max(E,R), so only
        // one of the two extensions can be carried on a given interface.
        if (CFG.mecEn && CFG.cdaEn)
          $fatal(1, "MEC and RME-CDA cannot share the REQ MECID/StreamID field");
        // The packed widths must stay inside the Issue H flit totals, which
        // catches any pack/unpack field list that drifts from B13.9.
        if ((reqFlitWidth(CFG) < (93 + CFG.addrW))
            || (reqFlitWidth(CFG) > (120 + CFG.addrW + CHI_MAX_RSVDC_W
                                     + CHI_MPAM_W + CHI_PBHA_W + 1
                                     + CHI_STREAMID_W)))
          $fatal(1, "REQ flit width is outside the Issue H range");
        if ((rspFlitWidth(CFG) < 71) || (rspFlitWidth(CFG) > 89))
          $fatal(1, "RSP flit width is outside the Issue H range");
        if ((snpFlitWidth(CFG) < (53 + CFG.addrW - 3))
            || (snpFlitWidth(CFG) > (71 + CFG.addrW - 3
                                     + CHI_MPAM_W + CHI_MECID_W)))
          $fatal(1, "SNP flit width is outside the Issue H range");
        if (datFlitWidth(CFG) < (240 + ((CFG.dataW - 128) * 149) / 128))
          $fatal(1, "DAT flit width is below the Issue H minimum");
        if ((CFG.posEntries == 0) || (CFG.lcrdDepth < 2)
            || (CFG.exclMonitors == 0) || (CFG.interleaveGranule == 0)
            || (NUM_REGIONS == 0)
            || (AGE_LIMIT == 0))
          $fatal(1, "Depth and region parameters must be positive, with at least two L-Credits per channel");
        if ((CFG.snpFilterEntries == 0) || (CFG.snpFilterWays == 0)
            || (CFG.snpFilterWays > CFG.snpFilterEntries)
            || ((CFG.snpFilterEntries % CFG.snpFilterWays) != 0))
          $fatal(1, "Invalid snoop-filter geometry");
        if ((CFG.interleaveGranule < 64)
            || ((CFG.interleaveGranule & (CFG.interleaveGranule - 1)) != 0))
          $fatal(1, "Interleave granule must be a power of two at least 64");
        if ((CFG.numHnf > 0) && (CFG.numSnf == 0))
          $fatal(1, "HN-F endpoints require an SN-F endpoint");
        if ((CFG.numHni > 0) && (CFG.numSni == 0))
          $fatal(1, "HN-I endpoints require an SN-I endpoint");
        if (CFG.atomicEn && ((CFG.numHnf + CFG.numHni) == 0))
          $fatal(1, "Atomic support requires a Home Node");
        if (CFG.dctEn && ((CFG.numRnf == 0) || (CFG.numHnf == 0)))
          $fatal(1, "DCT requires RN-F and HN-F endpoints");
        if ((CFG.dmtEn || CFG.dwtEn)
            && (((CFG.numHnf + CFG.numHni) == 0) || (CFG.numSnf == 0)))
          $fatal(1, "DMT/DWT require a Home Node and SN-F");
        if (CFG.stashEn && ((CFG.numRnf == 0) || (CFG.numHnf == 0)))
          $fatal(1, "Stash requires RN-F and HN-F endpoints");
        if (CFG.dvmEn && ((CFG.numMn == 0) || (NUM_REQ == 0)))
          $fatal(1, "DVM requires an MN and a Request Node");
        if (CFG.exclEn
            && (((CFG.numHnf + CFG.numHni) == 0)
                || (CFG.exclMonitors == 0)))
          $fatal(1, "Exclusive support requires a Home Node and monitors");
        if ((CFG.topology != CROSSBAR) && (CFG.topology != RING)
            && (CFG.topology != MESH_2D))
          $fatal(1, "Unsupported topology");
        if (NUM_NODES != (CFG.numRnf + CFG.numRnd + CFG.numRni
                          + CFG.numSnf + CFG.numSni + CFG.numHnf
                          + CFG.numHni + CFG.numMn))
          $fatal(1, "NUM_NODES must equal the sum of configured nodes");
        if (USE_DEFAULT_PLACEMENTS && (NUM_NODES != 14))
          $fatal(1, "Default placements are defined only for 14 nodes");
        if ((CFG.topology == MESH_2D)
            && ((CFG.meshX == 0) || (CFG.meshY == 0)
                || (CFG.numDevPortsPerXp == 0)
                || (deviceIdWidth(CFG) <= 0)
                || ((CFG.meshX * CFG.meshY * CFG.numDevPortsPerXp)
                    < NUM_NODES)))
          $fatal(1, "Invalid or undersized mesh dimensions");
        if ((CFG.cfgAccess == CFG_CHI_MMIO) && (CFG.numHni == 0))
          $fatal(1, "CHI-MMIO configuration requires HN-I");
        if ((CFG.cfgAccess != CFG_PARAM_ONLY) && (CFG.cfgAccess != CFG_APB)
            && (CFG.cfgAccess != CFG_CHI_MMIO))
          $fatal(1, "Unsupported configuration access mode");
        if ((CFG.cfgAccess == CFG_CHI_MMIO)
            && (CFG_MMIO_BASE[11:0] != 12'b0))
          $fatal(1, "CHI-MMIO configuration base must be 4-KiB aligned");
        if ((CFG.cfgAccess == CFG_APB) && (NUM_REGIONS == 0))
          $fatal(1, "APB configuration requires a region table");
        for (int unsigned i = 0; i < NUM_NODES; i++) begin
          placement = effectivePlacement(i);
          if (!placement.valid)
            $fatal(1, "Every node must have a placement");
          if ((placement.nodeClass != nodeClassForOrdinal(CFG, i))
              || (int'(placement.nodeIndex)
                  != nodeIndexForOrdinal(CFG, i)))
            $fatal(1, "Placement class/index does not match node ordinal");
          if ((int'(placement.meshX) >= CFG.meshX)
              || (int'(placement.meshY) >= CFG.meshY)
              || (int'(placement.devicePort)
                  >= CFG.numDevPortsPerXp))
            $fatal(1, "Node placement is out of range");
          if ((nodeIdMeshX(CFG, EFFECTIVE_NODE_IDS[i])
                != int'(placement.meshX))
              || (nodeIdMeshY(CFG, EFFECTIVE_NODE_IDS[i])
                != int'(placement.meshY))
              || (nodeIdDevicePort(CFG, EFFECTIVE_NODE_IDS[i])
                != int'(placement.devicePort)))
            $fatal(1, "NodeID routing fields do not match placement");
          for (int unsigned j = i + 1; j < NUM_NODES; j++) begin
            if (EFFECTIVE_NODE_IDS[i] == EFFECTIVE_NODE_IDS[j])
              $fatal(1, "NodeIDs must be unique");
            if ((placement.meshX == effectivePlacement(j).meshX)
                && (placement.meshY == effectivePlacement(j).meshY)
                && (placement.devicePort == effectivePlacement(j).devicePort))
              $fatal(1, "Node placements must not collide");
          end
        end
      end
    end
  endgenerate

  always_comb begin
    selectedRegionUpdate = apbRegionUpdate;
    selectedRegionUpdateIndex = apbRegionUpdateIndex;
    selectedRegionUpdateBase = apbRegionUpdateBase;
    selectedRegionUpdateLimit = apbRegionUpdateLimit;
    selectedRegionUpdateTarget = apbRegionUpdateTarget;
    selectedRegionUpdateAttributes = apbRegionUpdateAttributes;
    for (int unsigned i = 0; i < CFG.numHni; i++) begin
      if (mmioRegionUpdate[i]) begin
        selectedRegionUpdate = 1'b1;
        selectedRegionUpdateIndex = mmioRegionUpdateIndex[i];
        selectedRegionUpdateBase = mmioRegionUpdateBase[i];
        selectedRegionUpdateLimit = mmioRegionUpdateLimit[i];
        selectedRegionUpdateTarget = mmioRegionUpdateTarget[i];
        selectedRegionUpdateAttributes = mmioRegionUpdateAttributes[i];
      end
    end
    trafficQuiescent = !(|reqInValid) && !(|rspInValid)
                       && !(|snpInValid) && !(|datInValid);
    for (int unsigned i = 0; i < CFG.numHni; i++)
      trafficQuiescent &= hniIdle[i];
    for (int unsigned i = 0; i < CFG.numHnf; i++)
      trafficQuiescent &= hnfIdle[i];
    for (int unsigned i = 0; i < CFG.numMn; i++)
      trafficQuiescent &= mnIdle[i];
  end

  if (CFG.cfgAccess == CFG_APB) begin : apb_cfg
    chi_cfg_slave #(
      .CFG(CFG), .NUM_REGIONS(NUM_REGIONS),
      .REGION_BASE(EFFECTIVE_REGION_BASE),
      .REGION_LIMIT(EFFECTIVE_REGION_LIMIT),
      .REGION_TARGET(EFFECTIVE_REGION_TARGET),
      .REGION_ATTRIBUTES(EFFECTIVE_REGION_ATTRIBUTES)
    ) cfg_slave (
      .PCLK(clk), .PRESETn(resetn), .PADDR, .PSEL, .PENABLE, .PWRITE,
      .PWDATA, .PSTRB, .PPROT, .PRDATA, .PREADY, .PSLVERR,
      .trafficQuiescent, .regionUpdate(apbRegionUpdate),
      .regionUpdateIndex(apbRegionUpdateIndex),
      .regionUpdateBase(apbRegionUpdateBase),
      .regionUpdateLimit(apbRegionUpdateLimit),
      .regionUpdateTarget(apbRegionUpdateTarget),
      .regionUpdateAttributes(apbRegionUpdateAttributes)
    );
  end else begin : no_apb_cfg
    always_comb begin
      PRDATA = '0;
      PREADY = 1'b1;
      PSLVERR = PSEL && PENABLE;
      apbRegionUpdate = 1'b0;
      apbRegionUpdateIndex = '0;
      apbRegionUpdateBase = '0;
      apbRegionUpdateLimit = '0;
      apbRegionUpdateTarget = '0;
      apbRegionUpdateAttributes = '0;
    end
  end

  for (genvar i = 0; i < NUM_REQ; i++) begin : requester_sam
    // Decode and routing are separate blocks so that the mapper outputs do
    // not appear to feed the decode that produces the mapper inputs.
    always_comb begin
      requesterReq[i] = unpackReqFlit(CFG, requesterRawReq[i]);
    end

    always_comb begin
      requesterRouteTarget[i] = requesterSamTarget[i];
      if ((requesterReq[i].opcode == REQ_DVM_OP) && (CFG.numMn > 0))
        requesterRouteTarget[i] =
          EFFECTIVE_NODE_IDS[OFF_MN];
      // PrefetchTgt always goes straight to a Subordinate Node through its
      // own mapper (IHI 0050H B3.3.1).
      if ((requesterReq[i].opcode == REQ_PREFETCH_TGT) && (CFG.numSnf > 0))
        requesterRouteTarget[i] = requesterPrefetchTarget[i];
    end

    chi_prefetch_map #(
      .CFG(CFG), .NUM_SNF(NUM_SNF_E), .SNF_NODE_IDS(SNF_NODE_IDS)
    ) prefetch_map (
      .address(requesterReq[i].addr[CFG.addrW-1:0]),
      .targetNodeId(requesterPrefetchTarget[i])
    );

    chi_sam #(
      .CFG(CFG), .NUM_REGIONS(NUM_REGIONS), .HASH_TO_HNF(1'b1),
      .NUM_HNF(NUM_HNF_E), .HN_NODE_IDS(HNF_NODE_IDS),
      .REGION_BASE(EFFECTIVE_REGION_BASE),
      .REGION_LIMIT(EFFECTIVE_REGION_LIMIT),
      .REGION_TARGET(EFFECTIVE_REGION_TARGET),
      .REGION_ATTRIBUTES(EFFECTIVE_REGION_ATTRIBUTES)
    ) sam (
      .clk, .resetn, .address(requesterReq[i].addr[CFG.addrW-1:0]),
      .nonSecure(pasNonSecure(requesterReq[i].pas)),
      .targetNodeId(requesterSamTarget[i]),
      .matchedAttributes(requesterSamAttributes[i]),
      .unmappedError(requesterSamError[i]),
      .regionUpdate(selectedRegionUpdate),
      .regionUpdateIndex(selectedRegionUpdateIndex),
      .regionUpdateBase(selectedRegionUpdateBase),
      .regionUpdateLimit(selectedRegionUpdateLimit),
      .regionUpdateTarget(selectedRegionUpdateTarget),
      .regionUpdateAttributes(selectedRegionUpdateAttributes)
    );
  end

  // Every node port goes through a real CHI link layer: L-Credits, receive
  // buffering, flit parity, and the link activation handshake. A direction a
  // port never uses is drained so that a misrouted flit cannot stall the
  // fabric.
`define CHI_CONNECT_PORT(PORT, COUNT, OFFSET, IS_REQUESTER) \
  for (genvar i = 0; i < (COUNT > 0 ? COUNT : 1); i++) begin : PORT``_ports \
    logic portReqRxValid, portReqRxReady; \
    logic [reqFlitWidth(CFG)-1:0] portReqRxFlit; \
    logic portRspRxValid, portRspRxReady; \
    logic [rspFlitWidth(CFG)-1:0] portRspRxFlit; \
    logic portDatRxValid, portDatRxReady; \
    logic [datFlitWidth(CFG)-1:0] portDatRxFlit; \
    logic portReqTxValid, portReqTxReady; \
    logic [reqFlitWidth(CFG)-1:0] portReqTxFlit; \
    logic portRspTxValid, portRspTxReady; \
    logic [rspFlitWidth(CFG)-1:0] portRspTxFlit; \
    logic portSnpTxValid, portSnpTxReady; \
    logic [snpFlitWidth(CFG)-1:0] portSnpTxFlit; \
    logic portDatTxValid, portDatTxReady; \
    logic [datFlitWidth(CFG)-1:0] portDatTxFlit; \
    logic portLinkUp, portParityError, portCreditError; \
    chi_link_port #(.CFG(CFG), .REQUESTER_PORT(IS_REQUESTER)) link ( \
      .clk, .resetn, .chiPort(PORT[i]), \
      .reqRxValid(portReqRxValid), .reqRxReady(portReqRxReady), \
      .reqRxFlit(portReqRxFlit), .rspRxValid(portRspRxValid), \
      .rspRxReady(portRspRxReady), .rspRxFlit(portRspRxFlit), \
      .datRxValid(portDatRxValid), .datRxReady(portDatRxReady), \
      .datRxFlit(portDatRxFlit), .reqTxValid(portReqTxValid), \
      .reqTxReady(portReqTxReady), .reqTxFlit(portReqTxFlit), \
      .rspTxValid(portRspTxValid), .rspTxReady(portRspTxReady), \
      .rspTxFlit(portRspTxFlit), .snpTxValid(portSnpTxValid), \
      .snpTxReady(portSnpTxReady), .snpTxFlit(portSnpTxFlit), \
      .datTxValid(portDatTxValid), .datTxReady(portDatTxReady), \
      .datTxFlit(portDatTxFlit), .linkUp(portLinkUp), \
      .parityError(portParityError), .creditError(portCreditError) \
    ); \
    always_comb begin \
      portRspTxFlit = '0; portDatTxFlit = '0; \
      portReqTxFlit = '0; portSnpTxFlit = '0; \
      portRspTxValid = 1'b0; portDatTxValid = 1'b0; \
      portReqTxValid = 1'b0; portSnpTxValid = 1'b0; \
      portReqRxReady = 1'b0; portRspRxReady = 1'b0; portDatRxReady = 1'b0; \
      if (i < COUNT) begin \
        portReqRxReady = reqInReady[OFFSET+i]; \
        portRspRxReady = rspInReady[OFFSET+i]; \
        portDatRxReady = datInReady[OFFSET+i]; \
        portRspTxValid = rspOutValid[OFFSET+i]; \
        portRspTxFlit = rspOutFlit[OFFSET+i].payload[rspFlitWidth(CFG)-1:0]; \
        portDatTxValid = datOutValid[OFFSET+i]; \
        portDatTxFlit = datOutFlit[OFFSET+i].payload[datFlitWidth(CFG)-1:0]; \
        if (IS_REQUESTER) begin \
          portSnpTxValid = snpOutValid[OFFSET+i]; \
          portSnpTxFlit = snpOutFlit[OFFSET+i].payload[snpFlitWidth(CFG)-1:0]; \
        end else begin \
          portReqTxValid = reqOutValid[OFFSET+i]; \
          portReqTxFlit = reqOutFlit[OFFSET+i].payload[reqFlitWidth(CFG)-1:0]; \
        end \
      end \
    end \
    if (i < COUNT) begin : active \
      if (IS_REQUESTER) begin : requester_ingress \
        assign reqInValid[OFFSET+i] = portReqRxValid; \
        assign requesterRawReq[OFFSET+i] = \
          {{(CHI_MAX_REQ_FLIT_W-reqFlitWidth(CFG)){1'b0}}, portReqRxFlit}; \
        assign reqInFlit[OFFSET+i] = \
          reqToNoc(requesterRawReq[OFFSET+i], requesterRouteTarget[OFFSET+i]); \
        assign reqOutReady[OFFSET+i] = 1'b1; \
        assign snpOutReady[OFFSET+i] = portSnpTxReady; \
      end else begin : subordinate_ingress \
        assign reqInValid[OFFSET+i] = 1'b0; \
        assign reqInFlit[OFFSET+i] = '0; \
        assign reqOutReady[OFFSET+i] = portReqTxReady; \
        assign snpOutReady[OFFSET+i] = 1'b1; \
      end \
      assign rspInValid[OFFSET+i] = portRspRxValid; \
      assign rspInFlit[OFFSET+i] = \
        rspToNoc({{(CHI_MAX_RSP_FLIT_W-rspFlitWidth(CFG)){1'b0}}, \
                  portRspRxFlit}); \
      assign snpInValid[OFFSET+i] = 1'b0; \
      assign snpInFlit[OFFSET+i] = '0; \
      assign datInValid[OFFSET+i] = portDatRxValid; \
      assign datInFlit[OFFSET+i] = \
        datToNoc({{(CHI_MAX_DAT_FLIT_W-datFlitWidth(CFG)){1'b0}}, \
                  portDatRxFlit}); \
      assign rspOutReady[OFFSET+i] = portRspTxReady; \
      assign datOutReady[OFFSET+i] = portDatTxReady; \
    end \
  end

  `CHI_CONNECT_PORT(rnf, CFG.numRnf, OFF_RNF, 1'b1)
  `CHI_CONNECT_PORT(rnd, CFG.numRnd, OFF_RND, 1'b1)
  `CHI_CONNECT_PORT(rni, CFG.numRni, OFF_RNI, 1'b1)
  `CHI_CONNECT_PORT(snf, CFG.numSnf, OFF_SNF, 1'b0)
  `CHI_CONNECT_PORT(sni, CFG.numSni, OFF_SNI, 1'b0)
`undef CHI_CONNECT_PORT

  for (genvar i = 0; i < CFG.numHnf; i++) begin : hnf_nodes
    chi_hnf_top #(
      .CFG(CFG), .HN_NODE_ID(EFFECTIVE_NODE_IDS[OFF_HNF+i]),
      .SN_NODE_ID(EFFECTIVE_NODE_IDS[OFF_SNF+(i % CFG.numSnf)]),
      .NUM_RNF((CFG.numRnf > 0) ? CFG.numRnf : 1),
      .RNF_NODE_IDS(RNF_NODE_IDS)
    ) hnf (
      .clk, .resetn, .reqInValid(reqOutValid[OFF_HNF+i]),
      .reqInReady(reqOutReady[OFF_HNF+i]), .reqInFlit(reqOutFlit[OFF_HNF+i]),
      .rspInValid(rspOutValid[OFF_HNF+i]),
      .rspInReady(rspOutReady[OFF_HNF+i]), .rspInFlit(rspOutFlit[OFF_HNF+i]),
      .datInValid(datOutValid[OFF_HNF+i]),
      .datInReady(datOutReady[OFF_HNF+i]), .datInFlit(datOutFlit[OFF_HNF+i]),
      .reqOutValid(reqInValid[OFF_HNF+i]),
      .reqOutReady(reqInReady[OFF_HNF+i]), .reqOutFlit(reqInFlit[OFF_HNF+i]),
      .rspOutValid(rspInValid[OFF_HNF+i]),
      .rspOutReady(rspInReady[OFF_HNF+i]), .rspOutFlit(rspInFlit[OFF_HNF+i]),
      .snpOutValid(snpInValid[OFF_HNF+i]),
      .snpOutReady(snpInReady[OFF_HNF+i]), .snpOutFlit(snpInFlit[OFF_HNF+i]),
      .datOutValid(datInValid[OFF_HNF+i]),
      .datOutReady(datInReady[OFF_HNF+i]), .datOutFlit(datInFlit[OFF_HNF+i]),
      .idle(hnfIdle[i])
    );
  end

  for (genvar i = 0; i < CFG.numHni; i++) begin : hni_nodes
    chi_hni_top #(
      .CFG(CFG), .HN_NODE_ID(EFFECTIVE_NODE_IDS[OFF_HNI+i]),
      .NUM_REGIONS(NUM_REGIONS), .CFG_MMIO_BASE(CFG_MMIO_BASE),
      .REGION_BASE('{default:'0}), .REGION_LIMIT('{default:{CFG.addrW{1'b1}}}),
      .REGION_TARGET('{default:EFFECTIVE_NODE_IDS[OFF_SNI+(i % CFG.numSni)]}),
      .REGION_ATTRIBUTES('{default:{SAM_REGION_DIRECT,1'b0,1'b1}})
    ) hni (
      .clk, .resetn, .reqInValid(reqOutValid[OFF_HNI+i]),
      .reqInReady(reqOutReady[OFF_HNI+i]), .reqInFlit(reqOutFlit[OFF_HNI+i]),
      .rspInValid(rspOutValid[OFF_HNI+i]),
      .rspInReady(rspOutReady[OFF_HNI+i]), .rspInFlit(rspOutFlit[OFF_HNI+i]),
      .datInValid(datOutValid[OFF_HNI+i]),
      .datInReady(datOutReady[OFF_HNI+i]), .datInFlit(datOutFlit[OFF_HNI+i]),
      .reqOutValid(reqInValid[OFF_HNI+i]), .reqOutReady(reqInReady[OFF_HNI+i]),
      .reqOutFlit(reqInFlit[OFF_HNI+i]), .rspOutValid(rspInValid[OFF_HNI+i]),
      .rspOutReady(rspInReady[OFF_HNI+i]), .rspOutFlit(rspInFlit[OFF_HNI+i]),
      .datOutValid(datInValid[OFF_HNI+i]), .datOutReady(datInReady[OFF_HNI+i]),
      .datOutFlit(datInFlit[OFF_HNI+i]), .regionUpdate(selectedRegionUpdate),
      .regionUpdateIndex(selectedRegionUpdateIndex),
      .regionUpdateBase(selectedRegionUpdateBase),
      .regionUpdateLimit(selectedRegionUpdateLimit),
      .regionUpdateTarget(selectedRegionUpdateTarget),
      .regionUpdateAttributes(selectedRegionUpdateAttributes),
      .mmioRegionUpdate(mmioRegionUpdate[i]),
      .mmioRegionUpdateIndex(mmioRegionUpdateIndex[i]),
      .mmioRegionUpdateBase(mmioRegionUpdateBase[i]),
      .mmioRegionUpdateLimit(mmioRegionUpdateLimit[i]),
      .mmioRegionUpdateTarget(mmioRegionUpdateTarget[i]),
      .mmioRegionUpdateAttributes(mmioRegionUpdateAttributes[i]),
      .idle(hniIdle[i])
    );
    assign snpInValid[OFF_HNI+i] = 1'b0;
    assign snpInFlit[OFF_HNI+i] = '0;
    assign snpOutReady[OFF_HNI+i] = 1'b1;
  end

  for (genvar i = 0; i < CFG.numMn; i++) begin : mn_nodes
    chi_mn_dvm #(
      .CFG(CFG), .MN_NODE_ID(EFFECTIVE_NODE_IDS[OFF_MN+i]),
      .NUM_DVM_NODES(NUM_DVM), .DVM_NODE_IDS(DVM_NODE_IDS)
    ) mn (
      .clk, .resetn, .reqInValid(reqOutValid[OFF_MN+i]),
      .reqInReady(reqOutReady[OFF_MN+i]), .reqInFlit(reqOutFlit[OFF_MN+i]),
      .rspInValid(rspOutValid[OFF_MN+i]),
      .rspInReady(rspOutReady[OFF_MN+i]), .rspInFlit(rspOutFlit[OFF_MN+i]),
      .snpOutValid(snpInValid[OFF_MN+i]),
      .snpOutReady(snpInReady[OFF_MN+i]), .snpOutFlit(snpInFlit[OFF_MN+i]),
      .rspOutValid(rspInValid[OFF_MN+i]),
      .rspOutReady(rspInReady[OFF_MN+i]), .rspOutFlit(rspInFlit[OFF_MN+i]),
      .idle(mnIdle[i])
    );
    assign reqInValid[OFF_MN+i] = 1'b0;
    assign reqInFlit[OFF_MN+i] = '0;
    assign datInValid[OFF_MN+i] = 1'b0;
    assign datInFlit[OFF_MN+i] = '0;
    assign snpOutReady[OFF_MN+i] = 1'b1;
    assign datOutReady[OFF_MN+i] = 1'b1;
  end

  if (USE_DEFAULT_PLACEMENTS) begin : default_noc_placements
    chi_noc_top #(
      .CFG(CFG), .NUM_PORTS(NUM_NODES), .AGE_LIMIT(AGE_LIMIT),
      .NODE_IDS(EFFECTIVE_NODE_IDS), .PLACEMENTS(DEFAULT_PLACEMENTS)
    ) noc (
      .clk, .resetn, .reqInValid, .reqInReady, .reqInFlit,
      .reqOutValid, .reqOutReady, .reqOutFlit,
      .rspInValid, .rspInReady, .rspInFlit,
      .rspOutValid, .rspOutReady, .rspOutFlit,
      .snpInValid, .snpInReady, .snpInFlit,
      .snpOutValid, .snpOutReady, .snpOutFlit,
      .datInValid, .datInReady, .datInFlit,
      .datOutValid, .datOutReady, .datOutFlit
    );
  end else begin : override_noc_placements
    chi_noc_top #(
      .CFG(CFG), .NUM_PORTS(NUM_NODES), .AGE_LIMIT(AGE_LIMIT),
      .NODE_IDS(EFFECTIVE_NODE_IDS), .PLACEMENTS(PLACEMENTS)
    ) noc (
      .clk, .resetn, .reqInValid, .reqInReady, .reqInFlit,
      .reqOutValid, .reqOutReady, .reqOutFlit,
      .rspInValid, .rspInReady, .rspInFlit,
      .rspOutValid, .rspOutReady, .rspOutFlit,
      .snpInValid, .snpInReady, .snpInFlit,
      .snpOutValid, .snpOutReady, .snpOutFlit,
      .datInValid, .datInReady, .datInFlit,
      .datOutValid, .datOutReady, .datOutFlit
    );
  end
endmodule
