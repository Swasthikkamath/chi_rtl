module chi_interconnect_top #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned AGE_LIMIT = 16,
  parameter int unsigned NUM_REGIONS = 4,
  parameter int unsigned NUM_NODES =
    CFG.numRnf + CFG.numRnd + CFG.numRni + CFG.numSnf + CFG.numSni
    + CFG.numHnf + CFG.numHni + CFG.numMn,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    NODE_IDS [NUM_NODES-1:0] = '{default:'1},
  // 1 places every node automatically for any population (autoPlacements in
  // chi_pkg); 0 takes PLACEMENTS as given, after validation.
  parameter bit USE_DEFAULT_PLACEMENTS = 1'b1,
  parameter chi_cfg_pkg::chi_mesh_placement_t
    PLACEMENTS [NUM_NODES-1:0] = '{default:'0},
  // A crossbar's link count grows with the square of its crosspoint count, so
  // elaboration refuses a CROSSBAR wider than this.
  parameter int unsigned XBAR_MAX_XP = 8,
  // SN-F index of each HN-F when CFG.hnfSnfMap is HNF_SNF_MAP_TABLE.
  parameter int unsigned
    HNF_TO_SNF [(CFG.numHnf > 0 ? CFG.numHnf : 1)-1:0] = '{default:0},
  // Per-node capabilities: SN-F i supports DMT or DWT, RN-F i can act as the
  // forwarding Snoopee of DCT (IHI 0050H B16.1.3, B16.1.5). A direct transfer
  // is used only when the global enable in CFG, the capability of the node
  // involved and the HN-F run-time policy all allow it.
  parameter logic [(CFG.numSnf > 0 ? CFG.numSnf : 1)-1:0] SNF_DMT_CAP = '1,
  parameter logic [(CFG.numSnf > 0 ? CFG.numSnf : 1)-1:0] SNF_DWT_CAP = '1,
  parameter logic [(CFG.numRnf > 0 ? CFG.numRnf : 1)-1:0] RNF_DCT_CAP = '1,
  // Exclusive-capable Logical Processors of each Requester (RN-F, RN-D, RN-I
  // in ordinal order), each at most 2**lpidW (IHI 0050H B6.2).
  parameter int unsigned
    RN_NUM_LP [((CFG.numRnf + CFG.numRnd + CFG.numRni) > 0)
               ? (CFG.numRnf + CFG.numRnd + CFG.numRni) : 1] = '{default:4},
  parameter logic [CFG.addrW-1:0] CFG_MMIO_BASE =
    {CFG.addrW{1'b1}} - CFG.addrW'(12'hfff),
  parameter bit USE_DEFAULT_REGIONS = 1'b1,
  parameter logic [CFG.addrW-1:0]
    REGION_BASE [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [CFG.addrW-1:0]
    REGION_LIMIT [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]
    REGION_TARGET [NUM_REGIONS-1:0] = '{default:'0},
  // See CHI_SAM_ATTR_W in chi_cfg_pkg: valid, kind and the allowed PASs.
  parameter logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0]
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
  // AMBA APB5 PNSE: with PPROT[1] = 0 it marks a Root access. Configuration
  // writes need Root with RME and Secure without it.
  input  logic PNSE = 1'b0,
  output logic [31:0] PRDATA,
  output logic PREADY,
  output logic PSLVERR,
  // Link status per node ordinal. Bits for the internal HN-F, HN-I and MN
  // endpoints read zero because those have no external link.
  output logic [NUM_NODES-1:0] linkUp,
  output logic [NUM_NODES-1:0] linkParityError,
  output logic [NUM_NODES-1:0] linkCreditError,
  // RAS interrupt of each HN-F and of the GPC's GPT cache, HIGH while an
  // uncorrected error is recorded (rasEn; design specification, 9.16).
  output logic [(CFG.numHnf > 0 ? CFG.numHnf : 1)-1:0] rasIrq,
  output logic gpcRasIrq
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned NUM_REQ =
    CFG.numRnf + CFG.numRnd + CFG.numRni;
  localparam int unsigned NUM_REQ_E = (NUM_REQ > 0) ? NUM_REQ : 1;
  localparam int unsigned NUM_DVM = (NUM_REQ > 0) ? NUM_REQ : 1;
  localparam int unsigned NUM_HNF_E = (CFG.numHnf > 0) ? CFG.numHnf : 1;
  localparam int unsigned NUM_SNF_E = (CFG.numSnf > 0) ? CFG.numSnf : 1;
  localparam int unsigned NUM_SNI_E = (CFG.numSni > 0) ? CFG.numSni : 1;
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
  typedef chi_mesh_placement_t placement_array_t [NUM_NODES-1:0];
  typedef logic [CHI_MAX_NODEID_W-1:0] hnf_id_array_t [NUM_HNF_E-1:0];
  typedef logic [CHI_MAX_NODEID_W-1:0] snf_id_array_t [NUM_SNF_E];
  typedef logic [CHI_MAX_NODEID_W-1:0] sni_id_array_t [NUM_SNI_E];
  // Ascending like the chi_hnf_top parameters they are passed to: an
  // unpacked array is assigned by position, so a descending source would
  // reverse the order and RN-F i would no longer be index i inside the Home.
  typedef logic [CHI_MAX_NODEID_W-1:0]
    rnf_id_array_t [(CFG.numRnf > 0 ? CFG.numRnf : 1)];
  typedef logic [CHI_MAX_NODEID_W-1:0] requester_id_array_t [NUM_DVM];
  // SnpDVMOp goes to RN-Fs and RN-Ds; an RN-I has no snoop channel
  // (IHI 0050H B8.2.1).
  localparam int unsigned NUM_DVM_TGT_E =
    ((CFG.numRnf + CFG.numRnd) > 0) ? (CFG.numRnf + CFG.numRnd) : 1;
  typedef logic [CHI_MAX_NODEID_W-1:0] dvm_target_array_t [NUM_DVM_TGT_E];
  typedef logic [CFG.addrW-1:0] region_addr_array_t [NUM_REGIONS-1:0];
  typedef logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] region_target_array_t [NUM_REGIONS-1:0];
  typedef logic [CHI_SAM_ATTR_W-1:0] region_attr_array_t [NUM_REGIONS-1:0];

  function automatic chi_hnf_snf_table_t makeHnfSnfTable();
    chi_hnf_snf_table_t values;
    for (int unsigned i = 0; i < CHI_MAX_HNF; i++)
      values[i] = '0;
    for (int unsigned i = 0; (i < CFG.numHnf) && (i < CHI_MAX_HNF); i++)
      values[i] = 8'(HNF_TO_SNF[i]);
    return values;
  endfunction

  localparam chi_hnf_snf_table_t HNF_SNF_TABLE = makeHnfSnfTable();
  localparam chi_placement_table_t AUTO_PLACEMENTS =
    autoPlacements(CFG, HNF_SNF_TABLE);

  function automatic placement_array_t makePlacements();
    placement_array_t values;
    for (int unsigned i = 0; i < NUM_NODES; i++) begin
      if (!USE_DEFAULT_PLACEMENTS)
        values[i] = PLACEMENTS[i];
      else if (i < CHI_MAX_NODES)
        values[i] = AUTO_PLACEMENTS[i];
      else
        values[i] = '0;
    end
    return values;
  endfunction

  localparam placement_array_t EFFECTIVE_PLACEMENTS = makePlacements();

  // An all-ones NODE_IDS entry asks for the NodeID that encodes the node's
  // placement, with the node ordinal in the deviceId field.
  function automatic node_id_array_t makeNodeIds();
    node_id_array_t values;
    for (int unsigned i = 0; i < NUM_NODES; i++) begin
      if (NODE_IDS[i] == {CHI_MAX_NODEID_W{1'b1}})
        values[i] = encodeXpNodeId(
          CFG, xpIndexOfPlacement(CFG, EFFECTIVE_PLACEMENTS[i]),
          int'(EFFECTIVE_PLACEMENTS[i].devicePort), i);
      else
        values[i] = NODE_IDS[i];
    end
    return values;
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

  function automatic sni_id_array_t makeSniIds(input node_id_array_t ids);
    sni_id_array_t values;
    for (int unsigned i = 0; i < NUM_SNI_E; i++)
      values[i] = (i < CFG.numSni) ? ids[OFF_SNI+i] : '0;
    return values;
  endfunction

  function automatic rnf_id_array_t makeRnfIds(input node_id_array_t ids);
    rnf_id_array_t values;
    for (int unsigned i = 0;
         i < (CFG.numRnf > 0 ? CFG.numRnf : 1); i++)
      values[i] = (i < CFG.numRnf) ? ids[OFF_RNF+i] : '0;
    return values;
  endfunction

  // Every Requester (RN-F, RN-D, RN-I), in ordinal order.
  function automatic requester_id_array_t makeRequesterIds(
    input node_id_array_t ids
  );
    requester_id_array_t values;
    for (int unsigned i = 0; i < NUM_DVM; i++)
      values[i] = (i < NUM_REQ) ? ids[i] : '0;
    return values;
  endfunction

  // The Homes a SAM region may target, for the commit checks of the region
  // editor and the CHI MMIO window.
  typedef logic [CHI_NODEID_SLOT_W-1:0] hnf_slot_array_t [NUM_HNF_E];
  typedef logic [CHI_NODEID_SLOT_W-1:0] hni_slot_array_t [NUM_HNI_E];
  function automatic hnf_slot_array_t makeHnfSlots(input node_id_array_t ids);
    hnf_slot_array_t values;
    for (int unsigned i = 0; i < NUM_HNF_E; i++)
      values[i] = (i < CFG.numHnf) ? CHI_NODEID_SLOT_W'(ids[OFF_HNF+i]) : '0;
    return values;
  endfunction
  function automatic hni_slot_array_t makeHniSlots(input node_id_array_t ids);
    hni_slot_array_t values;
    for (int unsigned i = 0; i < NUM_HNI_E; i++)
      values[i] = (i < CFG.numHni) ? CHI_NODEID_SLOT_W'(ids[OFF_HNI+i]) : '0;
    return values;
  endfunction

  function automatic dvm_target_array_t makeDvmTargets(input node_id_array_t ids);
    dvm_target_array_t values;
    for (int unsigned i = 0; i < NUM_DVM_TGT_E; i++)
      values[i] = (i < (CFG.numRnf + CFG.numRnd)) ? ids[OFF_RNF+i] : '0;
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

  localparam logic [7:0] MMIO_PAS_MASK =
    CFG.rmeEn ? (8'd1 << PAS_ROOT) : (8'd1 << PAS_SECURE);

  function automatic region_attr_array_t makeRegionAttributes();
    region_attr_array_t values;
    values = REGION_ATTRIBUTES;
    if (USE_DEFAULT_REGIONS) begin
      values = '{default:'0};
      // Memory and the HN-I range admit every PAS the configuration
      // supports; the configuration window admits only Root with RME and
      // only Secure without it.
      values[0] = samAttributes(SAM_REGION_HNF_HASH, pasLegalMask(CFG), 1'b1);
      if (NUM_REGIONS > 1)
        values[1] = samAttributes(SAM_REGION_DIRECT, pasLegalMask(CFG), 1'b1);
      if (NUM_REGIONS > 2)
        values[2] = samAttributes(SAM_REGION_MMIO, MMIO_PAS_MASK, 1'b1);
    end
    return values;
  endfunction

  function automatic chi_noc_flit_t reqToNoc(
    input logic [CHI_MAX_REQ_FLIT_W-1:0] payload,
    input logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] samTarget,
    input chi_noc_err_e decodeErr
  );
    chi_noc_flit_t value;
    chi_req_flit_t request;
    request = unpackReqFlit(CFG, payload);
    request.tgtId = samTarget;
    value = '0;
    value.channel = CHI_CHANNEL_REQ;
    value.qos = request.qos;
    value.targetNodeId = samTarget;
    value.decodeErr = decodeErr;
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
  localparam sni_id_array_t SNI_NODE_IDS = makeSniIds(EFFECTIVE_NODE_IDS);
  localparam rnf_id_array_t RNF_NODE_IDS = makeRnfIds(EFFECTIVE_NODE_IDS);
  localparam requester_id_array_t REQUESTER_NODE_IDS =
    makeRequesterIds(EFFECTIVE_NODE_IDS);
  localparam dvm_target_array_t DVM_TARGET_IDS = makeDvmTargets(EFFECTIVE_NODE_IDS);
  localparam hnf_slot_array_t HNF_SLOT_IDS = makeHnfSlots(EFFECTIVE_NODE_IDS);
  localparam hni_slot_array_t HNI_SLOT_IDS = makeHniSlots(EFFECTIVE_NODE_IDS);

  function automatic int unsigned totalLps();
    int unsigned total;
    total = 0;
    for (int unsigned r = 0; r < NUM_DVM; r++)
      total += RN_NUM_LP[r];
    return (total > 0) ? total : 1;
  endfunction
  localparam int unsigned TOTAL_LP = totalLps();
  localparam region_addr_array_t EFFECTIVE_REGION_BASE = makeRegionBase();
  localparam region_addr_array_t EFFECTIVE_REGION_LIMIT = makeRegionLimit();
  localparam region_target_array_t EFFECTIVE_REGION_TARGET =
    makeRegionTarget(EFFECTIVE_NODE_IDS);
  localparam region_attr_array_t EFFECTIVE_REGION_ATTRIBUTES =
    makeRegionAttributes();

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
  logic [NUM_REQ_E-1:0][CHI_SAM_ATTR_W-1:0] requesterSamAttributes;
  logic [NUM_REQ_E-1:0] requesterSamPasError;
  chi_noc_err_e [NUM_REQ_E-1:0] requesterDecodeErr;
  logic [NUM_REQ_E-1:0] requesterSamError;
  chi_req_flit_t requesterReq [NUM_REQ_E-1:0];
  logic [CHI_MAX_REQ_FLIT_W-1:0] requesterRawReq [NUM_REQ_E-1:0];

  logic apbRegionUpdate;
  logic [clog2Min1(NUM_REGIONS)-1:0] apbRegionUpdateIndex;
  logic [CFG.addrW-1:0] apbRegionUpdateBase;
  logic [CFG.addrW-1:0] apbRegionUpdateLimit;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] apbRegionUpdateTarget;
  logic [CHI_SAM_ATTR_W-1:0] apbRegionUpdateAttributes;
  logic selectedRegionUpdate;
  logic [clog2Min1(NUM_REGIONS)-1:0] selectedRegionUpdateIndex;
  logic [CFG.addrW-1:0] selectedRegionUpdateBase;
  logic [CFG.addrW-1:0] selectedRegionUpdateLimit;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] selectedRegionUpdateTarget;
  logic [CHI_SAM_ATTR_W-1:0] selectedRegionUpdateAttributes;
  logic [NUM_HNI_E-1:0] mmioRegionUpdate;
  logic [clog2Min1(NUM_REGIONS)-1:0]
    mmioRegionUpdateIndex [NUM_HNI_E-1:0];
  logic [CFG.addrW-1:0] mmioRegionUpdateBase [NUM_HNI_E-1:0];
  logic [CFG.addrW-1:0] mmioRegionUpdateLimit [NUM_HNI_E-1:0];
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] mmioRegionUpdateTarget [NUM_HNI_E-1:0];
  logic [CHI_SAM_ATTR_W-1:0] mmioRegionUpdateAttributes [NUM_HNI_E-1:0];
  // Every Home but HN-I i is idle: the CHI MMIO commit needs this.
  logic [NUM_HNI_E-1:0] hniOthersQuiescent;
  logic [NUM_HNI_E-1:0] hniIdle;
  logic [(CFG.numHnf > 0 ? CFG.numHnf : 1)-1:0] hnfIdle;
  logic [(CFG.numMn > 0 ? CFG.numMn : 1)-1:0] mnIdle;
  logic trafficQuiescent;
  // Run-time policy of each HN-F, from the APB policy block or its reset
  // value when there is no APB access.
  chi_hnf_policy_t hnfPolicy [NUM_HNF_E];
  logic [NUM_HNF_E-1:0] slcMaintStart;
  logic [NUM_HNF_E-1:0] slcMaintInvalidate;
  logic [NUM_HNF_E-1:0] slcMaintBusy;
  // Granule Protection Check: one check port per Home (every HN-F, then
  // every HN-I) and one GPT read port per HN-F.
  localparam int unsigned NUM_HOMES_E =
    ((CFG.numHnf + CFG.numHni) > 0) ? (CFG.numHnf + CFG.numHni) : 1;
  logic [NUM_HOMES_E-1:0] gpcCheckValid;
  logic [NUM_HOMES_E-1:0][CHI_MAX_ADDR_W-1:0] gpcCheckAddr;
  chi_pas_e [NUM_HOMES_E-1:0] gpcCheckPas;
  logic [NUM_HOMES_E-1:0][CHI_NODEID_SLOT_W-1:0] gpcCheckSrcId;
  logic [NUM_HOMES_E-1:0] gpcCheckDone;
  logic [NUM_HOMES_E-1:0] gpcCheckFail;
  logic [NUM_HNF_E-1:0] gptReadValid;
  logic [CHI_MAX_ADDR_W-1:0] gptReadAddr;
  logic [NUM_HNF_E-1:0] gptReadDone;
  logic [NUM_HNF_E-1:0][511:0] gptReadData;
  logic [NUM_HNF_E-1:0] gptReadError;
  logic apbGpcSelect;
  logic [31:0] apbGpcRdata;
  logic apbGpcReady;
  logic apbGpcError;
  logic gpcWalking;
  logic gpcEventFault;
  // GPT TLBIs decoded by the MNs.
  localparam int unsigned NUM_MN_E = (CFG.numMn > 0) ? CFG.numMn : 1;
  logic [NUM_MN_E-1:0] mnGptInvalidateAll;
  logic [NUM_MN_E-1:0] mnGptInvalidateByPa;
  logic [CHI_MAX_ADDR_W-1:0] mnGptInvalidateAddr [NUM_MN_E];
  logic dvmGptInvalidateAll;
  logic dvmGptInvalidateByPa;
  logic [CHI_MAX_ADDR_W-1:0] dvmGptInvalidateAddr;
  // APB register blocks. PADDR[11:8] selects a 256-byte block: 0 is the
  // region editor, 1 the HN-F policy registers.
  logic apbRegionSelect;
  logic apbPolicySelect;
  logic [31:0] apbRegionRdata;
  logic [31:0] apbPolicyRdata;
  logic apbRegionReady;
  logic apbPolicyReady;
  logic apbRegionError;
  logic apbPolicyError;
  logic fabricRouteError;
  logic fabricBusy;
  // System coherency (IHI 0050H B15): the RN-F and RN-D ports, RN-Fs first,
  // as Requester ordinals.
  localparam int unsigned NUM_COH = CFG.numRnf + CFG.numRnd;
  localparam int unsigned RNF_E = (CFG.numRnf > 0) ? CFG.numRnf : 1;
  logic [NUM_REQ_E-1:0] reqCoReq;
  logic [NUM_REQ_E-1:0] reqCoAck;
  logic [NUM_DVM_TGT_E-1:0] cohReq;
  logic [NUM_DVM_TGT_E-1:0] cohAck;
  logic [NUM_DVM_TGT_E-1:0] cohSnoopable;
  logic [NUM_DVM_TGT_E-1:0] cohDrained;
  logic [NUM_HNF_E-1:0][RNF_E-1:0] hnfRnfIdle;
  logic [NUM_MN_E-1:0][NUM_DVM_TGT_E-1:0] mnNodeIdle;
  // REQ injection of the Request Node ports, through the QoS regulator.
  logic [NUM_REQ_E-1:0] reqPortValid;
  logic [NUM_REQ_E-1:0] reqPortReady;
  logic [NUM_REQ_E-1:0] qosReqValid;
  logic [NUM_REQ_E-1:0] qosReqReady;
  logic [NUM_REQ_E-1:0][7:0] qosTokens;
  logic [NUM_REQ_E-1:0][8:0] qosRate;
  logic [NUM_REQ_E-1:0][7:0] qosBurst;
  // APB block 4: the QoS regulator's rate and burst per port.
  logic apbQosSelect;
  logic [31:0] apbQosRdata;
  logic apbQosReady;
  logic apbQosError;
  // RAS records: every HN-F, then the GPC's GPT cache when it walks.
  localparam int unsigned NUM_REC = NUM_HNF_E + ((CFG.gpcMode == GPC_WALK) ? 1 : 0);
  logic [NUM_HNF_E-1:0] hnfRasCorrected;
  logic [NUM_HNF_E-1:0] hnfRasUncorrected;
  logic [NUM_HNF_E-1:0][3:0] hnfRasSource;
  logic [NUM_HNF_E-1:0][CHI_MAX_ADDR_W-1:0] hnfRasAddr;
  logic [NUM_HNF_E-1:0][2:0] hnfRasPas;
  logic gpcRasCorrected;
  logic gpcRasUncorrected;
  logic [CHI_MAX_ADDR_W-1:0] gpcRasAddr;
  logic [NUM_REC-1:0] recCorrected;
  logic [NUM_REC-1:0] recUncorrected;
  logic [NUM_REC-1:0][3:0] recSource;
  logic [NUM_REC-1:0][CHI_MAX_ADDR_W-1:0] recAddr;
  logic [NUM_REC-1:0][2:0] recPas;
  logic [NUM_REC-1:0] recIrq;
  // PMU: per-HN-F event counts and per-crosspoint flit counts.
  localparam int unsigned NUM_XP_E = (numXpOf(CFG) > 0) ? numXpOf(CFG) : 1;
  logic [NUM_HNF_E-1:0][chi_hnf_pkg::HNF_PMU_EVENTS-1:0][7:0] hnfPmuCount;
  logic [NUM_XP_E-1:0][3:0][3:0] xpInjected;
  logic [NUM_XP_E-1:0][3:0][3:0] xpEjected;
  // APB block 3: RAS records and counters.
  logic apbObsSelect;
  logic [31:0] apbObsRdata;
  logic apbObsReady;
  logic apbObsError;
  // Endpoint Order across HN-Fs (design specification, 9.5): tickets per
  // {Requester, SN-F}, wide enough for every POS entry that can hold one.
  localparam int unsigned EO_TICKET_W =
    clog2Min1(NUM_HNF_E * ((CFG.posEntries > 0) ? CFG.posEntries : 1) + 1) + 1;
  typedef int unsigned hnf_snf_index_t [NUM_HNF_E];
  function automatic hnf_snf_index_t makeHnfSnfIndex();
    hnf_snf_index_t values;
    for (int unsigned i = 0; i < NUM_HNF_E; i++)
      values[i] = (i < CFG.numHnf) ? snfIndexOfHnf(CFG, HNF_SNF_TABLE, i) : 0;
    return values;
  endfunction
  localparam hnf_snf_index_t HNF_SNF_INDEX = makeHnfSnfIndex();
  logic [NUM_HNF_E-1:0] eoAllocValid;
  logic [NUM_HNF_E-1:0][clog2Min1(NUM_DVM)-1:0] eoAllocReq;
  logic [NUM_HNF_E-1:0][EO_TICKET_W-1:0] eoAllocTicket;
  logic [NUM_HNF_E-1:0][NUM_DVM-1:0] eoRetire;
  logic [NUM_HNF_E-1:0][NUM_DVM-1:0][EO_TICKET_W-1:0] eoServing;

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
        if (CFG.gdiEn && !CFG.rmeEn)
          $fatal(1, "gdiEn needs rmeEn: the System Agent and Non-secure Protected PASs require RME_Support (IHI 0050H Table B13.47)");
        if (CFG.cdaEn && !CFG.rmeEn)
          $fatal(1, "cdaEn needs rmeEn: RME device assignment is an RME feature");
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
        if (CFG.slcEn) begin
          if (CFG.numHnf == 0)
            $fatal(1, "slcEn needs an HN-F: the SLC is one slice per HN-F");
          if (CFG.slcLineBytes != 64)
            $fatal(1, "slcLineBytes is %0d but must be 64, the CHI cache line size", CFG.slcLineBytes);
          if ((CFG.slcWays == 0) || ((CFG.slcWays & (CFG.slcWays - 1)) != 0))
            $fatal(1, "slcWays is %0d but must be a power of two of at least 1", CFG.slcWays);
          if ((CFG.slcSizePerHnf == 0)
              || ((CFG.slcSizePerHnf % (64 * CFG.slcWays)) != 0))
            $fatal(1, "slcSizePerHnf (%0d bytes) must be a whole number of %0d-way sets of 64-byte lines",
                   CFG.slcSizePerHnf, CFG.slcWays);
          if (((CFG.slcSizePerHnf / (64 * CFG.slcWays))
               & ((CFG.slcSizePerHnf / (64 * CFG.slcWays)) - 1)) != 0)
            $fatal(1, "slcSizePerHnf / (64 * slcWays) = %0d sets must be a power of two",
                   CFG.slcSizePerHnf / (64 * CFG.slcWays));
          if (CFG.slcTagPipelineDepth != 1)
            $fatal(1, "slcTagPipelineDepth is %0d but only a single-stage tag lookup, combined with the snoop filter lookup, is built",
                   CFG.slcTagPipelineDepth);
        end
        if (CFG.gpcMode != GPC_NONE) begin
          if (!CFG.rmeEn)
            $fatal(1, "gpcMode needs rmeEn: granule protection checks the RME Physical Address Spaces");
          if ((CFG.gpcMode == GPC_TABLE) && (CFG.gpcTableGranules == 0))
            $fatal(1, "gpcMode TABLE needs gpcTableGranules of at least 1");
          if ((CFG.gpcMode == GPC_WALK) && (CFG.gpcCacheEntries == 0))
            $fatal(1, "gpcMode WALK needs gpcCacheEntries of at least 1");
          if ((CFG.gpcMode == GPC_WALK) && (CFG.numHnf == 0))
            $fatal(1, "gpcMode WALK needs an HN-F: the GPT is read from memory through the HN-F that owns each line");
          if (CFG.cfgAccess != CFG_APB)
            $fatal(1, "gpcMode needs cfgAccess APB: the GPC registers are Root-only APB registers");
        end
        if ((CFG.numHni > 0) && (CFG.hniEntries == 0))
          $fatal(1, "hniEntries must be at least 1: an HN-I with no entry can never accept a request");
        if ((CFG.numHnf > 0) && (CFG.maxOutstandingSnoops == 0))
          $fatal(1, "maxOutstandingSnoops must be at least 1: an HN-F with no snoop slot can never snoop a sharer");
        // The set index is taken straight from the low line-address bits.
        if (((CFG.snpFilterEntries / CFG.snpFilterWays) < 2)
            || (((CFG.snpFilterEntries / CFG.snpFilterWays)
                 & ((CFG.snpFilterEntries / CFG.snpFilterWays) - 1)) != 0))
          $fatal(1, "snpFilterEntries / snpFilterWays = %0d sets must be a power of two of at least 2",
                 CFG.snpFilterEntries / CFG.snpFilterWays);
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
        if (CFG.dmtSepEn && !CFG.dmtEn)
          $fatal(1, "dmtSepEn selects ReadNoSnpSep for DMT reads, so it needs dmtEn");
        if ((CFG.rasEn || CFG.pmuEn) && (CFG.cfgAccess != CFG_APB))
          $fatal(1, "rasEn and pmuEn need cfgAccess APB: the error records and counters are APB registers");
        if (CFG.rasEn && (CFG.numHnf == 0))
          $fatal(1, "rasEn needs an HN-F: the error records are kept per HN-F");
        if (CFG.qosRegEn && ((CFG.qosRegRate == 0) || (CFG.qosRegRate > 256)))
          $fatal(1, "qosRegRate is %0d but must be 1 to 256 tokens per 256 cycles", CFG.qosRegRate);
        if (CFG.qosRegEn && ((CFG.qosRegBurst == 0) || (CFG.qosRegBurst > 255)))
          $fatal(1, "qosRegBurst is %0d but must be 1 to 255 tokens", CFG.qosRegBurst);
        if (CFG.qosRegEn && (NUM_REQ == 0))
          $fatal(1, "qosRegEn needs a Request Node port to regulate");
        if (CFG.gpcSlcAlloc && !(CFG.slcEn && (CFG.gpcMode == GPC_WALK)))
          $fatal(1, "gpcSlcAlloc needs slcEn and gpcMode WALK: it lets the GPT walker read and fill the SLC");
        if (CFG.stashEn && ((CFG.numRnf == 0) || (CFG.numHnf == 0)))
          $fatal(1, "Stash requires RN-F and HN-F endpoints");
        if (CFG.dvmEn && ((CFG.numMn == 0) || (NUM_REQ == 0)))
          $fatal(1, "DVM requires an MN and a Request Node");
        if ((CFG.numMn > 0) && (CFG.dvmMaxOps < 2))
          $fatal(1, "dvmMaxOps is %0d but must be at least 2: one MN tracker entry stays reserved for a Non-sync DVMOp (IHI 0050H B8.2.3.1)",
                 CFG.dvmMaxOps);
        if (CFG.dvmEn && (CFG.addrW < 44))
          $fatal(1, "dvmEn needs addrW of at least 44: the DVM payload spans REQ.Addr up to bit 43 (IHI 0050H B8.4.2)");
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
        // Fabric geometry. Every topology is numXp crosspoints with
        // numDevPortsPerXp device ports each, and every node needs a port.
        if ((CFG.topology == MESH_2D) && ((CFG.meshX == 0) || (CFG.meshY == 0)))
          $fatal(1, "MESH_2D needs positive meshX and meshY");
        if ((numXpOf(CFG) == 0) || (CFG.numDevPortsPerXp == 0))
          $fatal(1, "The fabric needs at least one crosspoint and one device port per crosspoint");
        if ((numXpOf(CFG) > CHI_MAX_XP)
            || (CFG.numDevPortsPerXp > CHI_MAX_DEV_PORTS))
          $fatal(1, "At most %0d crosspoints and %0d device ports per crosspoint are supported",
                 CHI_MAX_XP, CHI_MAX_DEV_PORTS);
        if ((numXpOf(CFG) * CFG.numDevPortsPerXp) < NUM_NODES)
          $fatal(1, "numXp * numDevPortsPerXp = %0d device ports cannot hold NUM_NODES = %0d",
                 numXpOf(CFG) * CFG.numDevPortsPerXp, NUM_NODES);
        if ((CFG.topology == RING) && (CFG.numXp < 2))
          $fatal(1, "RING needs at least two crosspoints, numXp is %0d",
                 CFG.numXp);
        if ((CFG.topology == CROSSBAR) && (CFG.numXp > XBAR_MAX_XP))
          $fatal(1, "CROSSBAR numXp %0d exceeds XBAR_MAX_XP %0d",
                 CFG.numXp, XBAR_MAX_XP);
        // The NodeID must hold the routing fields; deviceId may be empty.
        if (deviceIdWidth(CFG) < 0)
          $fatal(1, "nodeIdW %0d cannot encode {xpId, devicePort}; the minimum nodeIdW for this topology is %0d",
                 CFG.nodeIdW, minNodeIdWidth(CFG));
        if (USE_DEFAULT_PLACEMENTS && (NUM_NODES > CHI_MAX_NODES))
          $fatal(1, "Automatic placement supports at most %0d nodes", CHI_MAX_NODES);
        if (CFG.numHnf > CHI_MAX_HNF)
          $fatal(1, "At most %0d HN-F nodes are supported", CHI_MAX_HNF);
        if ((CFG.hnfSnfMap == HNF_SNF_MAP_TABLE) && (CFG.numHnf > 0))
          for (int unsigned i = 0; i < CFG.numHnf; i++)
            if (HNF_TO_SNF[i] >= CFG.numSnf)
              $fatal(1, "HNF_TO_SNF[%0d] = %0d names an SN-F that does not exist (numSnf = %0d)",
                     i, HNF_TO_SNF[i], CFG.numSnf);
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
          placement = EFFECTIVE_PLACEMENTS[i];
          if (!placement.valid)
            $fatal(1, "Node %0d has no placement", i);
          if ((placement.nodeClass != nodeClassForOrdinal(CFG, i))
              || (int'(placement.nodeIndex)
                  != nodeIndexForOrdinal(CFG, i)))
            $fatal(1, "Placement class/index of node %0d does not match its ordinal", i);
          if (CFG.topology == MESH_2D) begin
            if ((int'(placement.meshX) >= CFG.meshX)
                || (int'(placement.meshY) >= CFG.meshY))
              $fatal(1, "Node %0d is placed outside the mesh", i);
          end else if ((int'(placement.meshX) >= CFG.numXp)
                       || (placement.meshY != '0)) begin
            $fatal(1, "Node %0d names crosspoint %0d of %0d; meshY must be zero for RING and CROSSBAR",
                   i, placement.meshX, CFG.numXp);
          end
          if (int'(placement.devicePort) >= CFG.numDevPortsPerXp)
            $fatal(1, "Node %0d names device port %0d of %0d",
                   i, placement.devicePort, CFG.numDevPortsPerXp);
          if ((EFFECTIVE_NODE_IDS[i] >> CFG.nodeIdW) != '0)
            $fatal(1, "NodeID of node %0d does not fit in nodeIdW %0d",
                   i, CFG.nodeIdW);
          // The crosspoints route on these fields alone.
          if ((nodeIdXpIndex(CFG, EFFECTIVE_NODE_IDS[i])
                != xpIndexOfPlacement(CFG, placement))
              || (nodeIdDevicePort(CFG, EFFECTIVE_NODE_IDS[i])
                != int'(placement.devicePort))
              || ((CFG.topology == MESH_2D)
                  && ((nodeIdMeshX(CFG, EFFECTIVE_NODE_IDS[i])
                       != int'(placement.meshX))
                      || (nodeIdMeshY(CFG, EFFECTIVE_NODE_IDS[i])
                       != int'(placement.meshY)))))
            $fatal(1, "NodeID routing fields of node %0d do not match its placement", i);
          for (int unsigned j = i + 1; j < NUM_NODES; j++) begin
            if (EFFECTIVE_NODE_IDS[i] == EFFECTIVE_NODE_IDS[j])
              $fatal(1, "Nodes %0d and %0d have the same NodeID", i, j);
            if ((xpIndexOfPlacement(CFG, placement)
                 == xpIndexOfPlacement(CFG, EFFECTIVE_PLACEMENTS[j]))
                && (placement.devicePort == EFFECTIVE_PLACEMENTS[j].devicePort))
              $fatal(1, "Nodes %0d and %0d are placed on the same device port", i, j);
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
    // Quiescent: nothing entering the fabric, nothing inside it, and every
    // Home and MN idle.
    trafficQuiescent = !(|reqInValid) && !(|rspInValid)
                       && !(|snpInValid) && !(|datInValid) && !fabricBusy;
    for (int unsigned i = 0; i < CFG.numHni; i++)
      trafficQuiescent &= hniIdle[i];
    for (int unsigned i = 0; i < CFG.numHnf; i++)
      trafficQuiescent &= hnfIdle[i];
    for (int unsigned i = 0; i < CFG.numMn; i++)
      trafficQuiescent &= mnIdle[i];
  end

  // A CHI MMIO commit at an HN-I needs the same quiescence apart from its own
  // transaction, whose flits have all been delivered by the time its data is
  // applied: nothing entering or inside the fabric, every other Home and the
  // MNs idle.
  always_comb begin
    for (int unsigned i = 0; i < NUM_HNI_E; i++) begin
      hniOthersQuiescent[i] = !(|reqInValid) && !(|rspInValid)
                              && !(|snpInValid) && !(|datInValid) && !fabricBusy;
      for (int unsigned j = 0; j < CFG.numHni; j++)
        if (j != i)
          hniOthersQuiescent[i] &= hniIdle[j];
      for (int unsigned j = 0; j < CFG.numHnf; j++)
        hniOthersQuiescent[i] &= hnfIdle[j];
      for (int unsigned j = 0; j < CFG.numMn; j++)
        hniOthersQuiescent[i] &= mnIdle[j];
    end
  end

  if (CFG.cfgAccess == CFG_APB) begin : apb_cfg
    always_comb begin
      apbRegionSelect = PSEL && (PADDR[11:8] == 4'h0);
      apbPolicySelect = PSEL && (PADDR[11:8] == 4'h1);
      apbGpcSelect = PSEL && (PADDR[11:8] == 4'h2) && (CFG.gpcMode != GPC_NONE);
      apbObsSelect = PSEL && (PADDR[11:8] == 4'h3) && (CFG.rasEn || CFG.pmuEn);
      apbQosSelect = PSEL && (PADDR[11:8] == 4'h4) && CFG.qosRegEn;
    end

    chi_cfg_slave #(
      .CFG(CFG), .NUM_REGIONS(NUM_REGIONS),
      .REGION_BASE(EFFECTIVE_REGION_BASE),
      .REGION_LIMIT(EFFECTIVE_REGION_LIMIT),
      .REGION_TARGET(EFFECTIVE_REGION_TARGET),
      .REGION_ATTRIBUTES(EFFECTIVE_REGION_ATTRIBUTES),
      .NUM_HNF_IDS(NUM_HNF_E), .HNF_IDS(HNF_SLOT_IDS),
      .NUM_HNI_IDS(NUM_HNI_E), .HNI_IDS(HNI_SLOT_IDS),
      .HNF_PRESENT(CFG.numHnf > 0), .HNI_PRESENT(CFG.numHni > 0)
    ) cfg_slave (
      .PCLK(clk), .PRESETn(resetn), .PADDR, .PSEL(apbRegionSelect), .PENABLE,
      .PWRITE, .PWDATA, .PSTRB, .PPROT, .PNSE, .PRDATA(apbRegionRdata),
      .PREADY(apbRegionReady), .PSLVERR(apbRegionError),
      .trafficQuiescent, .regionUpdate(apbRegionUpdate),
      .regionUpdateIndex(apbRegionUpdateIndex),
      .regionUpdateBase(apbRegionUpdateBase),
      .regionUpdateLimit(apbRegionUpdateLimit),
      .regionUpdateTarget(apbRegionUpdateTarget),
      .regionUpdateAttributes(apbRegionUpdateAttributes)
    );

    chi_hnf_policy_regs #(
      .CFG(CFG), .NUM_HNF(NUM_HNF_E)
    ) policy_regs (
      .PCLK(clk), .PRESETn(resetn), .PADDR(PADDR[7:0]),
      .PSEL(apbPolicySelect), .PENABLE, .PWRITE, .PWDATA, .PSTRB, .PPROT,
      .PNSE,
      .PRDATA(apbPolicyRdata), .PREADY(apbPolicyReady),
      .PSLVERR(apbPolicyError), .trafficQuiescent, .policy(hnfPolicy),
      .slcMaintStart, .slcMaintInvalidate, .slcMaintBusy
    );

    if (CFG.rasEn || CFG.pmuEn) begin : observability
      chi_obs_regs #(
        .CFG(CFG), .NUM_HNF(NUM_HNF_E), .NUM_REC(NUM_REC), .NUM_XP(NUM_XP_E)
      ) obs_regs (
        .PCLK(clk), .PRESETn(resetn), .PADDR(PADDR[7:0]), .PSEL(apbObsSelect),
        .PENABLE, .PWRITE, .PWDATA, .PSTRB, .PPROT, .PNSE,
        .PRDATA(apbObsRdata), .PREADY(apbObsReady), .PSLVERR(apbObsError),
        .rasCorrected(recCorrected), .rasUncorrected(recUncorrected),
        .rasSource(recSource), .rasAddr(recAddr), .rasPas(recPas),
        .rasIrq(recIrq), .pmuCount(hnfPmuCount),
        .xpInjected(xpInjected), .xpEjected(xpEjected)
      );
    end else begin : no_observability
      always_comb begin
        apbObsRdata = '0;
        apbObsReady = 1'b1;
        apbObsError = 1'b1;
        recIrq = '0;
      end
    end

    if (CFG.qosRegEn) begin : qos_registers
      chi_qos_regs #(
        .CFG(CFG), .NUM_PORTS(NUM_REQ_E)
      ) qos_regs (
        .PCLK(clk), .PRESETn(resetn), .PADDR(PADDR[7:0]), .PSEL(apbQosSelect),
        .PENABLE, .PWRITE, .PWDATA, .PSTRB, .PPROT, .PNSE,
        .PRDATA(apbQosRdata), .PREADY(apbQosReady), .PSLVERR(apbQosError),
        .tokens(qosTokens), .rate(qosRate), .burst(qosBurst)
      );
    end else begin : no_qos_registers
      always_comb begin
        apbQosRdata = '0;
        apbQosReady = 1'b1;
        apbQosError = 1'b1;
        for (int unsigned k = 0; k < NUM_REQ_E; k++) begin
          qosRate[k] = 9'(CFG.qosRegRate);
          qosBurst[k] = 8'(CFG.qosRegBurst);
        end
      end
    end

    always_comb begin
      PRDATA = '0;
      PREADY = 1'b1;
      PSLVERR = PSEL && PENABLE;
      if (apbRegionSelect) begin
        PRDATA = apbRegionRdata;
        PREADY = apbRegionReady;
        PSLVERR = apbRegionError;
      end else if (apbPolicySelect) begin
        PRDATA = apbPolicyRdata;
        PREADY = apbPolicyReady;
        PSLVERR = apbPolicyError;
      end else if (apbGpcSelect) begin
        PRDATA = apbGpcRdata;
        PREADY = apbGpcReady;
        PSLVERR = apbGpcError;
      end else if (apbObsSelect) begin
        PRDATA = apbObsRdata;
        PREADY = apbObsReady;
        PSLVERR = apbObsError;
      end else if (apbQosSelect) begin
        PRDATA = apbQosRdata;
        PREADY = apbQosReady;
        PSLVERR = apbQosError;
      end
    end
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
      apbRegionSelect = 1'b0;
      apbPolicySelect = 1'b0;
      apbGpcSelect = 1'b0;
      apbRegionRdata = '0;
      apbPolicyRdata = '0;
      apbRegionReady = 1'b1;
      apbPolicyReady = 1'b1;
      apbRegionError = 1'b0;
      apbPolicyError = 1'b0;
      apbObsSelect = 1'b0;
      apbObsRdata = '0;
      apbObsReady = 1'b1;
      apbObsError = 1'b1;
      recIrq = '0;
      // Without APB the regulator runs at the configured rate and burst.
      apbQosSelect = 1'b0;
      apbQosRdata = '0;
      apbQosReady = 1'b1;
      apbQosError = 1'b1;
      for (int unsigned k = 0; k < NUM_REQ_E; k++) begin
        qosRate[k] = 9'(CFG.qosRegRate);
        qosBurst[k] = 8'(CFG.qosRegBurst);
      end
    end
    for (genvar i = 0; i < NUM_HNF_E; i++) begin : reset_policy
      assign hnfPolicy[i] = CHI_HNF_POLICY_DEFAULT;
    end
    // Without APB there is no maintenance register.
    assign slcMaintStart = '0;
    assign slcMaintInvalidate = '0;
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
      // B3.3.1 takes two cases away from the address mapper, and both must
      // override the two overrides above. A PCrdReturn has to reach the Home
      // that granted the credit, which the Requester names in TgtID; that
      // Home does not follow from the address, and the address field is not
      // even in use for the opcode. A request replayed on a pre-allocated
      // credit, which B2.10.2.1 identifies by AllowRetry being 0, has to keep
      // the target the RetryAck came from, so that editing the region table
      // between the RetryAck and the replay cannot deliver it to a Home
      // holding no record of the credit. PrefetchTgt is unaffected because
      // B2.10.2.1 requires AllowRetry to be 1 for it.
      if ((requesterReq[i].opcode == REQ_PCRD_RETURN)
          || !requesterReq[i].allowRetry)
        requesterRouteTarget[i] = requesterReq[i].tgtId;
      // An address no region maps still needs a Home to answer it. With no
      // HN-F to hash to, that is the first HN-I.
      if (requesterSamError[i] && (CFG.numHnf == 0) && (CFG.numHni > 0)
          && requesterReq[i].allowRetry
          && !(requesterReq[i].opcode inside {REQ_DVM_OP, REQ_PREFETCH_TGT,
                                              REQ_PCRD_RETURN}))
        requesterRouteTarget[i] = EFFECTIVE_NODE_IDS[OFF_HNI];
    end

    // A refused request carries the reason to its Home, which completes it
    // with NDERR (IHI 0050H B9.1.1). A replay is checked against the current
    // map too, although it keeps its target. DVMOp, PrefetchTgt and
    // PCrdReturn are not address-mapped.
    always_comb begin
      requesterDecodeErr[i] = NOC_ERR_NONE;
      if (!(requesterReq[i].opcode inside {REQ_DVM_OP, REQ_PREFETCH_TGT,
                                           REQ_PCRD_RETURN})) begin
        if (requesterSamError[i])
          requesterDecodeErr[i] = NOC_ERR_ADDRESS;
        else if (requesterSamPasError[i])
          requesterDecodeErr[i] = NOC_ERR_PAS;
      end
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
      .pas(requesterReq[i].pas),
      .targetNodeId(requesterSamTarget[i]),
      .matchedAttributes(requesterSamAttributes[i]),
      .unmappedError(requesterSamError[i]),
      .pasError(requesterSamPasError[i]),
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
// The interface array cannot be declared with zero elements, so a node class
// that is configured out still has a one-element sentinel port. The loop runs
// to COUNT rather than to the array size so that no link layer is built for
// it: an unused link would cost real buffers and credit counters, and its
// node-side inputs would have no driver.
`define CHI_CONNECT_PORT(PORT, COUNT, OFFSET, IS_REQUESTER) \
  for (genvar i = 0; i < COUNT; i++) begin : PORT``_ports \
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
    logic portSysCoReq, portSysCoAck, portReqReadyIn; \
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
      .parityError(portParityError), .creditError(portCreditError), \
      .sysCoReq(portSysCoReq), .sysCoAck(portSysCoAck) \
    ); \
    always_comb begin \
      portRspTxFlit = '0; portDatTxFlit = '0; \
      portReqTxFlit = '0; portSnpTxFlit = '0; \
      portRspTxValid = 1'b0; portDatTxValid = 1'b0; \
      portReqTxValid = 1'b0; portSnpTxValid = 1'b0; \
      portReqRxReady = 1'b0; portRspRxReady = 1'b0; portDatRxReady = 1'b0; \
      if (i < COUNT) begin \
        portReqRxReady = portReqReadyIn; \
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
        assign reqPortValid[OFFSET+i] = portReqRxValid; \
        assign portReqReadyIn = reqPortReady[OFFSET+i]; \
        assign reqCoReq[OFFSET+i] = portSysCoReq; \
        assign portSysCoAck = reqCoAck[OFFSET+i]; \
        assign requesterRawReq[OFFSET+i] = \
          {{(CHI_MAX_REQ_FLIT_W-reqFlitWidth(CFG)){1'b0}}, portReqRxFlit}; \
        assign reqInFlit[OFFSET+i] = \
          reqToNoc(requesterRawReq[OFFSET+i], requesterRouteTarget[OFFSET+i], \
                   requesterDecodeErr[OFFSET+i]); \
        assign reqOutReady[OFFSET+i] = 1'b1; \
        assign snpOutReady[OFFSET+i] = portSnpTxReady; \
      end else begin : subordinate_ingress \
        assign reqInValid[OFFSET+i] = 1'b0; \
        assign reqInFlit[OFFSET+i] = '0; \
        assign portReqReadyIn = reqInReady[OFFSET+i]; \
        assign portSysCoAck = portSysCoReq; \
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
      assign linkUp[OFFSET+i] = portLinkUp; \
      assign linkParityError[OFFSET+i] = portParityError; \
      assign linkCreditError[OFFSET+i] = portCreditError; \
    end \
  end

  `CHI_CONNECT_PORT(rnf, CFG.numRnf, OFF_RNF, 1'b1)
  `CHI_CONNECT_PORT(rnd, CFG.numRnd, OFF_RND, 1'b1)
  `CHI_CONNECT_PORT(rni, CFG.numRni, OFF_RNI, 1'b1)
  `CHI_CONNECT_PORT(snf, CFG.numSnf, OFF_SNF, 1'b0)
  `CHI_CONNECT_PORT(sni, CFG.numSni, OFF_SNI, 1'b0)
`undef CHI_CONNECT_PORT

  // REQ injection of every Request Node port passes the QoS regulator.
  chi_qos_reg #(
    .CFG(CFG), .NUM_PORTS(NUM_REQ_E)
  ) qos_regulator (
    .clk, .resetn, .inValid(reqPortValid), .inReady(reqPortReady),
    .outValid(qosReqValid), .outReady(qosReqReady), .rate(qosRate),
    .burst(qosBurst), .tokens(qosTokens)
  );
  for (genvar k = 0; k < NUM_REQ; k++) begin : requester_injection
    assign reqInValid[k] = qosReqValid[k];
    assign qosReqReady[k] = reqInReady[k];
  end
  for (genvar k = NUM_REQ; k < NUM_REQ_E; k++) begin : no_requester
    assign reqPortValid[k] = 1'b0;
    assign reqCoReq[k] = 1'b0;
    assign qosReqReady[k] = 1'b0;
  end

  chi_eo_order #(
    .NUM_HNF(NUM_HNF_E), .NUM_REQ(NUM_DVM), .NUM_SNF(NUM_SNF_E),
    .HNF_SNF(HNF_SNF_INDEX), .TICKET_W(EO_TICKET_W)
  ) endpoint_order (
    .clk, .resetn, .allocValid(eoAllocValid), .allocReq(eoAllocReq),
    .allocTicket(eoAllocTicket), .retire(eoRetire), .serving(eoServing)
  );

  // System coherency: RN-F and RN-D ports handshake in chi_sysco; an RN-I
  // has no snoop channel, so its SYSCOACK echoes SYSCOREQ. A node is
  // drained once every HN-F and MN reports it so.
  chi_sysco #(
    .CFG(CFG), .NUM_COH(NUM_DVM_TGT_E)
  ) system_coherency (
    .clk, .resetn, .coReq(cohReq), .coAck(cohAck), .snoopable(cohSnoopable),
    .drained(cohDrained)
  );
  always_comb begin
    for (int unsigned k = 0; k < NUM_DVM_TGT_E; k++) begin
      cohReq[k] = (k < NUM_COH) ? reqCoReq[k] : 1'b0;
      cohDrained[k] = 1'b1;
      if (k < CFG.numRnf)
        for (int unsigned h = 0; h < CFG.numHnf; h++)
          cohDrained[k] = cohDrained[k] && hnfRnfIdle[h][k];
      for (int unsigned m = 0; m < CFG.numMn; m++)
        cohDrained[k] = cohDrained[k] && mnNodeIdle[m][k];
    end
    for (int unsigned k = 0; k < NUM_REQ_E; k++) begin
      reqCoAck[k] = reqCoReq[k];
      if ((k < NUM_COH) && (k < NUM_DVM_TGT_E))
        reqCoAck[k] = cohAck[k];
    end
  end

  // RAS records for the observability block, and the interrupts.
  always_comb begin
    for (int unsigned h = 0; h < NUM_HNF_E; h++) begin
      recCorrected[h] = hnfRasCorrected[h];
      recUncorrected[h] = hnfRasUncorrected[h];
      recSource[h] = hnfRasSource[h];
      recAddr[h] = hnfRasAddr[h];
      recPas[h] = hnfRasPas[h];
    end
    if (NUM_REC > NUM_HNF_E) begin
      recCorrected[NUM_REC-1] = gpcRasCorrected;
      recUncorrected[NUM_REC-1] = gpcRasUncorrected;
      recSource[NUM_REC-1] = chi_hnf_pkg::RAS_SRC_GPT;
      recAddr[NUM_REC-1] = gpcRasAddr;
      recPas[NUM_REC-1] = PAS_ROOT;
    end
    rasIrq = recIrq[NUM_HNF_E-1:0];
    gpcRasIrq = (NUM_REC > NUM_HNF_E) ? recIrq[NUM_REC-1] : 1'b0;
  end

  for (genvar i = OFF_HNF; i < NUM_NODES; i++) begin : internal_node_status
    assign linkUp[i] = 1'b0;
    assign linkParityError[i] = 1'b0;
    assign linkCreditError[i] = 1'b0;
  end

  // Two MNs invalidating by PA in one cycle become one invalidation of
  // everything.
  always_comb begin
    int unsigned byPa;
    dvmGptInvalidateAll = 1'b0;
    dvmGptInvalidateByPa = 1'b0;
    dvmGptInvalidateAddr = '0;
    byPa = 0;
    for (int unsigned i = 0; i < CFG.numMn; i++) begin
      if (mnGptInvalidateAll[i])
        dvmGptInvalidateAll = 1'b1;
      if (mnGptInvalidateByPa[i]) begin
        byPa++;
        dvmGptInvalidateAddr = mnGptInvalidateAddr[i];
      end
    end
    if (byPa > 1)
      dvmGptInvalidateAll = 1'b1;
    else if (byPa == 1)
      dvmGptInvalidateByPa = !dvmGptInvalidateAll;
  end

  for (genvar i = CFG.numMn; i < NUM_MN_E; i++) begin : no_mn_gpt
    assign mnNodeIdle[i] = '1;
    assign mnGptInvalidateAll[i] = 1'b0;
    assign mnGptInvalidateByPa[i] = 1'b0;
    assign mnGptInvalidateAddr[i] = '0;
  end

  if (CFG.gpcMode != GPC_NONE) begin : gpc
    chi_gpc #(
      .CFG(CFG), .NUM_HOMES(NUM_HOMES_E), .NUM_HNF(NUM_HNF_E)
    ) gpc_unit (
      .clk, .resetn,
      .PADDR(PADDR[7:0]), .PSEL(apbGpcSelect), .PENABLE, .PWRITE, .PWDATA,
      .PSTRB, .PPROT, .PNSE, .PRDATA(apbGpcRdata), .PREADY(apbGpcReady),
      .PSLVERR(apbGpcError),
      .checkValid(gpcCheckValid), .checkAddr(gpcCheckAddr),
      .checkPas(gpcCheckPas), .checkSrcId(gpcCheckSrcId),
      .checkDone(gpcCheckDone), .checkFail(gpcCheckFail),
      .gptReadValid, .gptReadAddr, .gptReadDone, .gptReadData, .gptReadError,
      .dvmInvalidateAll(dvmGptInvalidateAll),
      .dvmInvalidateByPa(dvmGptInvalidateByPa),
      .dvmInvalidateAddr(dvmGptInvalidateAddr),
      .walking(gpcWalking), .eventFault(gpcEventFault),
      .rasCorrected(gpcRasCorrected), .rasUncorrected(gpcRasUncorrected),
      .rasAddr(gpcRasAddr)
    );
  end else begin : no_gpc
    always_comb begin
      gpcCheckDone = '1;
      gpcCheckFail = '0;
      gptReadValid = '0;
      gptReadAddr = '0;
      apbGpcRdata = '0;
      apbGpcReady = 1'b1;
      apbGpcError = 1'b1;
      gpcWalking = 1'b0;
      gpcEventFault = 1'b0;
      gpcRasCorrected = 1'b0;
      gpcRasUncorrected = 1'b0;
      gpcRasAddr = '0;
    end
  end

  for (genvar i = CFG.numHnf; i < NUM_HNF_E; i++) begin : no_hnf_maint
    assign slcMaintBusy[i] = 1'b0;
    assign gptReadDone[i] = 1'b0;
    assign gptReadData[i] = '0;
    assign gptReadError[i] = 1'b0;
    assign hnfRnfIdle[i] = '1;
    assign hnfRasCorrected[i] = 1'b0;
    assign hnfRasUncorrected[i] = 1'b0;
    assign hnfRasSource[i] = '0;
    assign hnfRasAddr[i] = '0;
    assign hnfRasPas[i] = '0;
    assign hnfPmuCount[i] = '0;
    assign eoAllocValid[i] = 1'b0;
    assign eoAllocReq[i] = '0;
    assign eoRetire[i] = '0;
  end
  for (genvar i = CFG.numHnf + CFG.numHni; i < NUM_HOMES_E; i++) begin : no_home_check
    assign gpcCheckValid[i] = 1'b0;
    assign gpcCheckAddr[i] = '0;
    assign gpcCheckPas[i] = PAS_SECURE;
    assign gpcCheckSrcId[i] = '0;
  end

  for (genvar i = 0; i < CFG.numHnf; i++) begin : hnf_nodes
    // The SN-F that holds this HN-F's memory, by modulo or by HNF_TO_SNF.
    localparam int unsigned SNF_INDEX = snfIndexOfHnf(CFG, HNF_SNF_TABLE, i);
    chi_pas_e rasPasOut;
    chi_hnf_top #(
      .CFG(CFG), .HN_NODE_ID(EFFECTIVE_NODE_IDS[OFF_HNF+i]),
      .SN_NODE_ID(EFFECTIVE_NODE_IDS[OFF_SNF+SNF_INDEX]),
      .NUM_RNF((CFG.numRnf > 0) ? CFG.numRnf : 1),
      .RNF_NODE_IDS(RNF_NODE_IDS),
      .NUM_REQUESTERS(NUM_DVM), .REQUESTER_NODE_IDS(REQUESTER_NODE_IDS),
      .RN_NUM_LP(RN_NUM_LP), .NUM_LP(TOTAL_LP),
      .SN_DMT_CAP(SNF_DMT_CAP[SNF_INDEX]),
      .SN_DWT_CAP(SNF_DWT_CAP[SNF_INDEX]),
      .RNF_DCT_CAP(RNF_DCT_CAP), .EO_TICKET_W(EO_TICKET_W)
    ) hnf (
      .clk, .resetn, .policy(hnfPolicy[i]), .reqInValid(reqOutValid[OFF_HNF+i]),
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
      .idle(hnfIdle[i]),
      .slcMaintStart(slcMaintStart[i]),
      .slcMaintInvalidate(slcMaintInvalidate[i]),
      .slcMaintBusy(slcMaintBusy[i]),
      .gpcCheckValid(gpcCheckValid[i]), .gpcCheckAddr(gpcCheckAddr[i]),
      .gpcCheckPas(gpcCheckPas[i]), .gpcCheckSrcId(gpcCheckSrcId[i]),
      .gpcCheckDone(gpcCheckDone[i]), .gpcCheckFail(gpcCheckFail[i]),
      .gptReadValid(gptReadValid[i]), .gptReadAddr(gptReadAddr),
      .gptReadDone(gptReadDone[i]), .gptReadData(gptReadData[i]),
      .gptReadError(gptReadError[i]),
      .rnfSnoopable(cohSnoopable[RNF_E-1:0]), .rnfIdle(hnfRnfIdle[i]),
      .rasCorrected(hnfRasCorrected[i]), .rasUncorrected(hnfRasUncorrected[i]),
      .rasSource(hnfRasSource[i]), .rasAddr(hnfRasAddr[i]),
      .rasPas(rasPasOut), .pmuCount(hnfPmuCount[i]),
      .eoAllocValid(eoAllocValid[i]), .eoAllocReq(eoAllocReq[i]),
      .eoAllocTicket(eoAllocTicket[i]), .eoRetire(eoRetire[i]),
      .eoServing(eoServing[i])
    );
    assign hnfRasPas[i] = rasPasOut;
  end

  for (genvar i = 0; i < CFG.numHni; i++) begin : hni_nodes
    chi_hni_top #(
      .CFG(CFG), .HN_NODE_ID(EFFECTIVE_NODE_IDS[OFF_HNI+i]),
      .NUM_REGIONS(NUM_REGIONS), .CFG_MMIO_BASE(CFG_MMIO_BASE),
      .REGION_BASE('{default:'0}), .REGION_LIMIT('{default:{CFG.addrW{1'b1}}}),
      .REGION_TARGET('{default:EFFECTIVE_NODE_IDS[OFF_SNI+(i % CFG.numSni)]}),
      .REGION_ATTRIBUTES('{default:samAttributes(SAM_REGION_DIRECT,
                                                 pasLegalMask(CFG), 1'b1)}),
      .NUM_SNI(NUM_SNI_E), .SNI_NODE_IDS(SNI_NODE_IDS),
      .NUM_REQUESTERS(NUM_DVM), .REQUESTER_NODE_IDS(REQUESTER_NODE_IDS),
      .RN_NUM_LP(RN_NUM_LP), .NUM_LP(TOTAL_LP),
      .NUM_HNF_IDS(NUM_HNF_E), .HNF_IDS(HNF_SLOT_IDS),
      .NUM_HNI_IDS(NUM_HNI_E), .HNI_IDS(HNI_SLOT_IDS),
      .HNF_PRESENT(CFG.numHnf > 0), .HNI_PRESENT(CFG.numHni > 0)
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
      .othersQuiescent(hniOthersQuiescent[i]),
      .gpcCheckValid(gpcCheckValid[CFG.numHnf+i]),
      .gpcCheckAddr(gpcCheckAddr[CFG.numHnf+i]),
      .gpcCheckPas(gpcCheckPas[CFG.numHnf+i]),
      .gpcCheckSrcId(gpcCheckSrcId[CFG.numHnf+i]),
      .gpcCheckDone(gpcCheckDone[CFG.numHnf+i]),
      .gpcCheckFail(gpcCheckFail[CFG.numHnf+i]),
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
      .NUM_DVM_NODES(NUM_DVM_TGT_E), .DVM_NODE_IDS(DVM_TARGET_IDS),
      .NUM_REQUESTERS(NUM_DVM), .REQUESTER_NODE_IDS(REQUESTER_NODE_IDS)
    ) mn (
      .clk, .resetn, .reqInValid(reqOutValid[OFF_MN+i]),
      .reqInReady(reqOutReady[OFF_MN+i]), .reqInFlit(reqOutFlit[OFF_MN+i]),
      .rspInValid(rspOutValid[OFF_MN+i]),
      .rspInReady(rspOutReady[OFF_MN+i]), .rspInFlit(rspOutFlit[OFF_MN+i]),
      // The 8-byte DVM payload arrives as NonCopyBackWriteData.
      .datInValid(datOutValid[OFF_MN+i]),
      .datInReady(datOutReady[OFF_MN+i]), .datInFlit(datOutFlit[OFF_MN+i]),
      .snpOutValid(snpInValid[OFF_MN+i]),
      .snpOutReady(snpInReady[OFF_MN+i]), .snpOutFlit(snpInFlit[OFF_MN+i]),
      .rspOutValid(rspInValid[OFF_MN+i]),
      .rspOutReady(rspInReady[OFF_MN+i]), .rspOutFlit(rspInFlit[OFF_MN+i]),
      .gptInvalidateAll(mnGptInvalidateAll[i]),
      .gptInvalidateByPa(mnGptInvalidateByPa[i]),
      .gptInvalidateAddr(mnGptInvalidateAddr[i]),
      .nodeSnoopable(cohSnoopable), .nodeIdle(mnNodeIdle[i]),
      .idle(mnIdle[i])
    );
    assign reqInValid[OFF_MN+i] = 1'b0;
    assign reqInFlit[OFF_MN+i] = '0;
    assign datInValid[OFF_MN+i] = 1'b0;
    assign datInFlit[OFF_MN+i] = '0;
    assign snpOutReady[OFF_MN+i] = 1'b1;
  end

  chi_noc_top #(
    .CFG(CFG), .NUM_PORTS(NUM_NODES), .AGE_LIMIT(AGE_LIMIT),
    .NODE_IDS(EFFECTIVE_NODE_IDS), .PLACEMENTS(EFFECTIVE_PLACEMENTS),
    .NUM_XP_OUT(NUM_XP_E)
  ) noc (
    .clk, .resetn, .reqInValid, .reqInReady, .reqInFlit,
    .reqOutValid, .reqOutReady, .reqOutFlit,
    .rspInValid, .rspInReady, .rspInFlit,
    .rspOutValid, .rspOutReady, .rspOutFlit,
    .snpInValid, .snpInReady, .snpInFlit,
    .snpOutValid, .snpOutReady, .snpOutFlit,
    .datInValid, .datInReady, .datInFlit,
    .datOutValid, .datOutReady, .datOutFlit,
    .routeError(fabricRouteError), .fabricBusy(fabricBusy),
    .xpInjected(xpInjected), .xpEjected(xpEjected)
  );
endmodule
