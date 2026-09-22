// chiGlobalsPkg is the single configuration and protocol model for both tops.
// It is UVM-free so hdlTop can elaborate it with no test running.
// Flit layouts are the testbench's own reading of IHI 0050H B13.9. They are
// not taken from the DUT's pack functions. A width or field mismatch against
// the silicon is a finding, not a reason to import those functions.
// See OPEN QUESTIONS for the Stage 0 answers this file codes against.

package chiGlobalsPkg;
  import chi_cfg_pkg::*;

  // Storage widths. The significant width of a flit is chiReqFlitWidth and
  // its siblings; the high bits of these vectors stay zero.
  localparam int unsigned CHI_TB_MAX_REQ_FLIT_W = 1024;
  localparam int unsigned CHI_TB_MAX_RSP_FLIT_W = 256;
  localparam int unsigned CHI_TB_MAX_SNP_FLIT_W = 1024;
  localparam int unsigned CHI_TB_MAX_DAT_FLIT_W = 4096;
  localparam int unsigned CHI_TB_MAX_FLIT_CHK_W = 512;
  localparam int unsigned CHI_TB_CACHE_LINE_BYTES = 64;
  localparam int unsigned CHI_TB_NUM_REGIONS = 4;
  localparam int unsigned CHI_TB_AGE_LIMIT = 16;
  localparam int unsigned CHI_TB_OUTSTANDING_CAP = 16;
  localparam logic [1:0] CHI_TB_REGION_KIND_HNF_HASH = 2'b00;
  localparam logic [1:0] CHI_TB_REGION_KIND_DIRECT = 2'b01;
  localparam logic [1:0] CHI_TB_REGION_KIND_MMIO = 2'b10;

  typedef logic [CHI_TB_MAX_DAT_FLIT_W-1:0] chiFlitBitsT;

  // [SPEC:IHI0050H B14.5] {LINKACTIVEREQ, LINKACTIVEACK}.
  typedef enum logic [1:0] {
    CHI_LINK_STATE_STOP = 2'b00,
    CHI_LINK_STATE_DEACTIVATE = 2'b01,
    CHI_LINK_STATE_ACTIVATE = 2'b10,
    CHI_LINK_STATE_RUN = 2'b11
  } chiLinkStateE;

  // [ASSUMPTION:5] Class values confirmed for nodeClassForOrdinal.
  typedef enum logic [2:0] {
    CHI_NODE_CLASS_RNF = 3'd0,
    CHI_NODE_CLASS_RND = 3'd1,
    CHI_NODE_CLASS_RNI = 3'd2,
    CHI_NODE_CLASS_SNF = 3'd3,
    CHI_NODE_CLASS_SNI = 3'd4,
    CHI_NODE_CLASS_HNF = 3'd5,
    CHI_NODE_CLASS_HNI = 3'd6,
    CHI_NODE_CLASS_MN = 3'd7
  } chiNodeClassE;

  // [SPEC:IHI0050H B13.10.68] PAS[2:0].
  typedef enum logic [2:0] {
    CHI_PAS_SECURE = 3'b000,
    CHI_PAS_NON_SECURE = 3'b001,
    CHI_PAS_ROOT = 3'b010,
    CHI_PAS_REALM = 3'b011,
    CHI_PAS_SYSTEM_AGENT = 3'b100,
    CHI_PAS_NON_SECURE_PROTECTED = 3'b101
  } chiPasE;

  // [SPEC:IHI0050H B2.7] Order[1:0]. 0b10 is Request Order, or OWO when
  // ExpCompAck is 1.
  typedef enum logic [1:0] {
    CHI_ORDER_NO_ORDER = 2'b00,
    CHI_ORDER_REQUEST_ACCEPTED = 2'b01,
    CHI_ORDER_REQUEST_ORDER = 2'b10,
    CHI_ORDER_ENDPOINT_ORDER = 2'b11
  } chiOrderE;

  // [SPEC:IHI0050H B13.10.45]
  typedef enum logic [1:0] {
    CHI_RESP_ERR_OK = 2'b00,
    CHI_RESP_ERR_EXOK = 2'b01,
    CHI_RESP_ERR_DERR = 2'b10,
    CHI_RESP_ERR_NDERR = 2'b11
  } chiRespErrE;

  // [SPEC:IHI0050H B13.10.46] Resp[2] is PassDirty. 0b010 is the unique
  // final state a snoopee reports when it keeps the line. 0b110 is the
  // unique pass-dirty completion.
  typedef enum logic [2:0] {
    CHI_RESP_I = 3'b000,
    CHI_RESP_SC = 3'b001,
    CHI_RESP_UC = 3'b010,
    CHI_RESP_SD = 3'b011,
    CHI_RESP_I_PD = 3'b100,
    CHI_RESP_SC_PD = 3'b101,
    CHI_RESP_UC_PD = 3'b110,
    CHI_RESP_SD_PD = 3'b111
  } chiRespE;

  // [SPEC:IHI0050H B4.1] Architectural cache states, not a flit field.
  typedef enum logic [2:0] {
    CHI_CACHE_STATE_I = 3'd0,
    CHI_CACHE_STATE_SC = 3'd1,
    CHI_CACHE_STATE_UC = 3'd2,
    CHI_CACHE_STATE_UD = 3'd3,
    CHI_CACHE_STATE_SD = 3'd4,
    CHI_CACHE_STATE_UCE = 3'd5
  } chiCacheStateE;

  // [SPEC:IHI0050H B13.10.18.1] REQ opcode, 7 bits. Bit 6 selects the
  // second column of the opcode map.
  typedef enum logic [6:0] {
    CHI_REQ_LCRD_RETURN = 7'h00,
    CHI_REQ_READ_SHARED = 7'h01,
    CHI_REQ_READ_CLEAN = 7'h02,
    CHI_REQ_READ_ONCE = 7'h03,
    CHI_REQ_READ_NO_SNP = 7'h04,
    CHI_REQ_PCRD_RETURN = 7'h05,
    CHI_REQ_READ_UNIQUE = 7'h07,
    CHI_REQ_CLEAN_SHARED = 7'h08,
    CHI_REQ_CLEAN_INVALID = 7'h09,
    CHI_REQ_MAKE_INVALID = 7'h0A,
    CHI_REQ_CLEAN_UNIQUE = 7'h0B,
    CHI_REQ_MAKE_UNIQUE = 7'h0C,
    CHI_REQ_EVICT = 7'h0D,
    CHI_REQ_CLEAN_INVALID_STORAGE = 7'h0E,
    CHI_REQ_READ_NO_SNP_SEP = 7'h11,
    CHI_REQ_CLEAN_SHARED_PERSIST_SEP = 7'h13,
    CHI_REQ_DVM_OP = 7'h14,
    CHI_REQ_WRITE_EVICT_FULL = 7'h15,
    CHI_REQ_WRITE_CLEAN_FULL = 7'h17,
    CHI_REQ_WRITE_UNIQUE_PTL = 7'h18,
    CHI_REQ_WRITE_UNIQUE_FULL = 7'h19,
    CHI_REQ_WRITE_BACK_PTL = 7'h1A,
    CHI_REQ_WRITE_BACK_FULL = 7'h1B,
    CHI_REQ_WRITE_NO_SNP_PTL = 7'h1C,
    CHI_REQ_WRITE_NO_SNP_FULL = 7'h1D,
    CHI_REQ_WRITE_UNIQUE_FULL_STASH = 7'h20,
    CHI_REQ_WRITE_UNIQUE_PTL_STASH = 7'h21,
    CHI_REQ_STASH_ONCE_SHARED = 7'h22,
    CHI_REQ_STASH_ONCE_UNIQUE = 7'h23,
    CHI_REQ_READ_ONCE_CLEAN_INVALID = 7'h24,
    CHI_REQ_READ_ONCE_MAKE_INVALID = 7'h25,
    CHI_REQ_READ_NOT_SHARED_DIRTY = 7'h26,
    CHI_REQ_CLEAN_SHARED_PERSIST = 7'h27,
    CHI_REQ_ATOMIC_STORE_ADD = 7'h28,
    CHI_REQ_ATOMIC_STORE_CLR = 7'h29,
    CHI_REQ_ATOMIC_STORE_EOR = 7'h2A,
    CHI_REQ_ATOMIC_STORE_SET = 7'h2B,
    CHI_REQ_ATOMIC_STORE_SMAX = 7'h2C,
    CHI_REQ_ATOMIC_STORE_SMIN = 7'h2D,
    CHI_REQ_ATOMIC_STORE_UMAX = 7'h2E,
    CHI_REQ_ATOMIC_STORE_UMIN = 7'h2F,
    CHI_REQ_ATOMIC_LOAD_ADD = 7'h30,
    CHI_REQ_ATOMIC_LOAD_CLR = 7'h31,
    CHI_REQ_ATOMIC_LOAD_EOR = 7'h32,
    CHI_REQ_ATOMIC_LOAD_SET = 7'h33,
    CHI_REQ_ATOMIC_LOAD_SMAX = 7'h34,
    CHI_REQ_ATOMIC_LOAD_SMIN = 7'h35,
    CHI_REQ_ATOMIC_LOAD_UMAX = 7'h36,
    CHI_REQ_ATOMIC_LOAD_UMIN = 7'h37,
    CHI_REQ_ATOMIC_SWAP = 7'h38,
    CHI_REQ_ATOMIC_COMPARE = 7'h39,
    CHI_REQ_PREFETCH_TGT = 7'h3A,
    CHI_REQ_MAKE_READ_UNIQUE = 7'h41,
    CHI_REQ_WRITE_EVICT_OR_EVICT = 7'h42,
    CHI_REQ_WRITE_UNIQUE_ZERO = 7'h43,
    CHI_REQ_WRITE_NO_SNP_ZERO = 7'h44,
    CHI_REQ_STASH_ONCE_SEP_SHARED = 7'h47,
    CHI_REQ_STASH_ONCE_SEP_UNIQUE = 7'h48,
    CHI_REQ_READ_PREFER_UNIQUE = 7'h4C,
    CHI_REQ_CLEAN_INVALID_POPA = 7'h4D,
    CHI_REQ_WRITE_NO_SNP_DEF = 7'h4E,
    CHI_REQ_WRITE_NO_SNP_FULL_CLEAN_SH = 7'h50,
    CHI_REQ_WRITE_NO_SNP_FULL_CLEAN_INV = 7'h51,
    CHI_REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP = 7'h52,
    CHI_REQ_WRITE_UNIQUE_FULL_CLEAN_SH = 7'h54,
    CHI_REQ_WRITE_UNIQUE_FULL_CLEAN_SH_PER_SEP = 7'h56,
    CHI_REQ_WRITE_UNIQUE_FULL_CLEAN_INV_STRG = 7'h57,
    CHI_REQ_WRITE_BACK_FULL_CLEAN_SH = 7'h58,
    CHI_REQ_WRITE_BACK_FULL_CLEAN_INV = 7'h59,
    CHI_REQ_WRITE_BACK_FULL_CLEAN_SH_PER_SEP = 7'h5A,
    CHI_REQ_WRITE_BACK_FULL_CLEAN_INV_STRG = 7'h5B,
    CHI_REQ_WRITE_CLEAN_FULL_CLEAN_SH = 7'h5C,
    CHI_REQ_WRITE_CLEAN_FULL_CLEAN_SH_PER_SEP = 7'h5E,
    CHI_REQ_WRITE_NO_SNP_PTL_CLEAN_SH = 7'h60,
    CHI_REQ_WRITE_NO_SNP_PTL_CLEAN_INV = 7'h61,
    CHI_REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP = 7'h62,
    CHI_REQ_WRITE_UNIQUE_PTL_CLEAN_SH = 7'h64,
    CHI_REQ_WRITE_UNIQUE_PTL_CLEAN_SH_PER_SEP = 7'h66,
    CHI_REQ_WRITE_NO_SNP_PTL_CLEAN_INV_POPA = 7'h70,
    CHI_REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA = 7'h71,
    CHI_REQ_WRITE_NO_SNP_FULL_CLEAN_INV_STRG = 7'h72,
    CHI_REQ_WRITE_BACK_FULL_CLEAN_INV_POPA = 7'h79
  } chiReqOpcodeE;

  // [SPEC:IHI0050H B13.10.18.2]
  typedef enum logic [4:0] {
    CHI_RSP_LCRD_RETURN = 5'h00,
    CHI_RSP_SNP_RESP = 5'h01,
    CHI_RSP_COMP_ACK = 5'h02,
    CHI_RSP_RETRY_ACK = 5'h03,
    CHI_RSP_COMP = 5'h04,
    CHI_RSP_COMP_DBID_RESP = 5'h05,
    CHI_RSP_DBID_RESP = 5'h06,
    CHI_RSP_PCRD_GRANT = 5'h07,
    CHI_RSP_READ_RECEIPT = 5'h08,
    CHI_RSP_SNP_RESP_FWDED = 5'h09,
    CHI_RSP_TAG_MATCH = 5'h0A,
    CHI_RSP_RESP_SEP_DATA = 5'h0B,
    CHI_RSP_PERSIST = 5'h0C,
    CHI_RSP_COMP_PERSIST = 5'h0D,
    CHI_RSP_DBID_RESP_ORD = 5'h0E,
    CHI_RSP_STASH_DONE = 5'h10,
    CHI_RSP_COMP_STASH_DONE = 5'h11,
    CHI_RSP_COMP_CMO = 5'h14
  } chiRspOpcodeE;

  // [SPEC:IHI0050H B13.10.18.3]
  typedef enum logic [4:0] {
    CHI_SNP_LCRD_RETURN = 5'h00,
    CHI_SNP_SHARED = 5'h01,
    CHI_SNP_CLEAN = 5'h02,
    CHI_SNP_ONCE = 5'h03,
    CHI_SNP_NOT_SHARED_DIRTY = 5'h04,
    CHI_SNP_UNIQUE_STASH = 5'h05,
    CHI_SNP_MAKE_INVALID_STASH = 5'h06,
    CHI_SNP_UNIQUE = 5'h07,
    CHI_SNP_CLEAN_SHARED = 5'h08,
    CHI_SNP_CLEAN_INVALID = 5'h09,
    CHI_SNP_MAKE_INVALID = 5'h0A,
    CHI_SNP_STASH_UNIQUE = 5'h0B,
    CHI_SNP_STASH_SHARED = 5'h0C,
    CHI_SNP_DVM_OP = 5'h0D,
    CHI_SNP_QUERY = 5'h10,
    CHI_SNP_SHARED_FWD = 5'h11,
    CHI_SNP_CLEAN_FWD = 5'h12,
    CHI_SNP_ONCE_FWD = 5'h13,
    CHI_SNP_NOT_SHARED_DIRTY_FWD = 5'h14,
    CHI_SNP_PREFER_UNIQUE = 5'h15,
    CHI_SNP_PREFER_UNIQUE_FWD = 5'h16,
    CHI_SNP_UNIQUE_FWD = 5'h17
  } chiSnpOpcodeE;

  // [SPEC:IHI0050H B13.10.18.4] Opcode 0xD is reserved for C2C and is omitted.
  typedef enum logic [3:0] {
    CHI_DAT_LCRD_RETURN = 4'h0,
    CHI_DAT_SNP_RESP_DATA = 4'h1,
    CHI_DAT_COPY_BACK_WRITE_DATA = 4'h2,
    CHI_DAT_NON_COPY_BACK_WRITE_DATA = 4'h3,
    CHI_DAT_COMP_DATA = 4'h4,
    CHI_DAT_SNP_RESP_DATA_PTL = 4'h5,
    CHI_DAT_SNP_RESP_DATA_FWDED = 4'h6,
    CHI_DAT_WRITE_DATA_CANCEL = 4'h7,
    CHI_DAT_DATA_SEP_RESP = 4'hB,
    CHI_DAT_NON_COPY_BACK_WRITE_DATA_COMP_ACK = 4'hC
  } chiDatOpcodeE;

  // Logical flits. Overlaid wire slots are single fields:
  // opcodeCtrl is StashNIDValid, Endian, Deep, or PrefetchTgtHint;
  // snpAttr is also DoDWT; excl is also SnoopMe or CAH;
  // groupSlot is the opaque 8-bit LPID/group byte [ASSUMPTION:7];
  // returnNid also carries StashNID; fwdState also carries DataPull on RSP;
  // dataSource also carries {5'b0, FwdState} on DAT.
  typedef struct {
    logic [3:0] qos;
    logic [CHI_MAX_NODEID_W-1:0] tgtId;
    logic [CHI_MAX_NODEID_W-1:0] srcId;
    logic [11:0] txnId;
    logic [CHI_MAX_NODEID_W-1:0] returnNid;
    logic opcodeCtrl;
    logic [11:0] returnTxnId;
    logic [6:0] opcode;
    logic multiReq;
    logic [2:0] size;
    logic [5:0] numReq;
    logic [51:0] addr;
    logic [2:0] pas;
    logic likelyShared;
    logic allowRetry;
    logic [1:0] order;
    logic [3:0] pCrdType;
    logic [3:0] memAttr;
    logic snpAttr;
    logic [7:0] groupSlot;
    logic excl;
    logic expCompAck;
    logic [1:0] tagOp;
    logic traceTag;
    logic [14:0] mpam;
    logic [15:0] mecId;
    logic [15:0] streamId;
    logic secSid1;
    logic [31:0] rsvdc;
  } chiReqFlitT;

  typedef struct {
    logic [3:0] qos;
    logic [CHI_MAX_NODEID_W-1:0] tgtId;
    logic [CHI_MAX_NODEID_W-1:0] srcId;
    logic [11:0] txnId;
    logic [4:0] opcode;
    logic [1:0] respErr;
    logic [2:0] resp;
    logic [2:0] fwdState;
    logic [2:0] cBusy;
    logic [11:0] dbid;
    logic [3:0] pCrdType;
    logic [1:0] tagOp;
    logic traceTag;
    logic [5:0] cacheLineId;
  } chiRspFlitT;

  typedef struct {
    logic [3:0] qos;
    logic [CHI_MAX_NODEID_W-1:0] srcId;
    logic [11:0] txnId;
    logic [CHI_MAX_NODEID_W-1:0] fwdNid;
    logic [11:0] fwdTxnId;
    logic [4:0] opcode;
    logic [51:0] addr;
    logic [2:0] pas;
    logic doNotGoToSd;
    logic retToSrc;
    logic traceTag;
    logic [14:0] mpam;
    logic [15:0] mecId;
  } chiSnpFlitT;

  typedef struct {
    logic [3:0] qos;
    logic [CHI_MAX_NODEID_W-1:0] tgtId;
    logic [CHI_MAX_NODEID_W-1:0] srcId;
    logic [11:0] txnId;
    logic [CHI_MAX_NODEID_W-1:0] homeNid;
    logic [3:0] opcode;
    logic [1:0] respErr;
    logic [2:0] resp;
    logic [7:0] dataSource;
    logic dataPull;
    logic [2:0] cBusy;
    logic [15:0] mecId;
    logic [15:0] dbid;
    logic [1:0] ccid;
    logic [1:0] dataId;
    logic [5:0] cacheLineId;
    logic [1:0] tagOp;
    logic [15:0] tag;
    logic [3:0] tu;
    logic traceTag;
    logic cah;
    logic [1:0] numDat;
    logic replicate;
    logic [31:0] rsvdc;
    logic [63:0] be;
    logic [511:0] data;
    logic [63:0] dataCheck;
    logic [7:0] poison;
  } chiDatFlitT;

  function automatic chi_cfg_t chiMakeCfg();
    chi_cfg_t cfg;
    cfg = CHI_CFG_DEFAULT;
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
`ifdef CHI_TB_DATA_W
    cfg.dataW = `CHI_TB_DATA_W;
`endif
`ifdef CHI_TB_ADDR_W
    cfg.addrW = `CHI_TB_ADDR_W;
`endif
`ifdef CHI_TB_NODEID_W
    cfg.nodeIdW = `CHI_TB_NODEID_W;
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
`ifdef CHI_TB_ATOMIC_EN
    cfg.atomicEn = `CHI_TB_ATOMIC_EN;
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
`ifdef CHI_TB_STASH_EN
    cfg.stashEn = `CHI_TB_STASH_EN;
`endif
`ifdef CHI_TB_DVM_EN
    cfg.dvmEn = `CHI_TB_DVM_EN;
`endif
`ifdef CHI_TB_EXCL_EN
    cfg.exclEn = `CHI_TB_EXCL_EN;
`endif
`ifdef CHI_TB_DATA_CHECK_EN
    cfg.dataCheckEn = `CHI_TB_DATA_CHECK_EN;
`endif
`ifdef CHI_TB_POISON_EN
    cfg.poisonEn = `CHI_TB_POISON_EN;
`endif
`ifdef CHI_TB_LCRD_DEPTH
    cfg.lcrdDepth = `CHI_TB_LCRD_DEPTH;
`endif
    return cfg;
  endfunction

  parameter chi_cfg_t CHI_CFG = chiMakeCfg();

  localparam int unsigned CHI_TB_NUM_NODES =
    CHI_CFG.numRnf + CHI_CFG.numRnd + CHI_CFG.numRni + CHI_CFG.numSnf
    + CHI_CFG.numSni + CHI_CFG.numHnf + CHI_CFG.numHni + CHI_CFG.numMn;
  localparam int unsigned CHI_TB_NUM_REQUESTERS =
    CHI_CFG.numRnf + CHI_CFG.numRnd + CHI_CFG.numRni;
  localparam int unsigned CHI_TB_NUM_SUBORDINATES =
    CHI_CFG.numSnf + CHI_CFG.numSni;
  localparam int unsigned CHI_TB_NUM_RNF_E =
    (CHI_CFG.numRnf > 0) ? CHI_CFG.numRnf : 1;
  localparam int unsigned CHI_TB_NUM_RND_E =
    (CHI_CFG.numRnd > 0) ? CHI_CFG.numRnd : 1;
  localparam int unsigned CHI_TB_NUM_RNI_E =
    (CHI_CFG.numRni > 0) ? CHI_CFG.numRni : 1;
  localparam int unsigned CHI_TB_NUM_SNF_E =
    (CHI_CFG.numSnf > 0) ? CHI_CFG.numSnf : 1;
  localparam int unsigned CHI_TB_NUM_SNI_E =
    (CHI_CFG.numSni > 0) ? CHI_CFG.numSni : 1;

  typedef logic [CHI_MAX_NODEID_W-1:0] chiNodeIdArrayT [CHI_TB_NUM_NODES-1:0];
  typedef chi_mesh_placement_t chiPlacementArrayT [CHI_TB_NUM_NODES-1:0];

  function automatic int unsigned chiNumNodes(input chi_cfg_t cfg);
    return cfg.numRnf + cfg.numRnd + cfg.numRni + cfg.numSnf
      + cfg.numSni + cfg.numHnf + cfg.numHni + cfg.numMn;
  endfunction

  function automatic int unsigned chiNumRequesters(input chi_cfg_t cfg);
    return cfg.numRnf + cfg.numRnd + cfg.numRni;
  endfunction

  function automatic int unsigned chiOffRnd(input chi_cfg_t cfg);
    return cfg.numRnf;
  endfunction

  function automatic int unsigned chiOffRni(input chi_cfg_t cfg);
    return cfg.numRnf + cfg.numRnd;
  endfunction

  function automatic int unsigned chiOffSnf(input chi_cfg_t cfg);
    return cfg.numRnf + cfg.numRnd + cfg.numRni;
  endfunction

  function automatic int unsigned chiOffSni(input chi_cfg_t cfg);
    return chiOffSnf(cfg) + cfg.numSnf;
  endfunction

  function automatic int unsigned chiOffHnf(input chi_cfg_t cfg);
    return chiOffSni(cfg) + cfg.numSni;
  endfunction

  function automatic int unsigned chiOffHni(input chi_cfg_t cfg);
    return chiOffHnf(cfg) + cfg.numHnf;
  endfunction

  function automatic int unsigned chiOffMn(input chi_cfg_t cfg);
    return chiOffHni(cfg) + cfg.numHni;
  endfunction

  // [ASSUMPTION:5] Minimum width is 1, matching clog2Min1.
  function automatic int unsigned chiClog2Min1(input int unsigned value);
    int unsigned width;
    int unsigned remaining;
    width = 1;
    if (value > 1) begin
      width = 0;
      remaining = value - 1;
      while (remaining > 0) begin
        width++;
        remaining = remaining >> 1;
      end
    end
    return width;
  endfunction

  function automatic int unsigned chiDeviceIdWidth(input chi_cfg_t cfg);
    int unsigned yWidth;
    int unsigned xWidth;
    int unsigned portWidth;
    yWidth = chiClog2Min1(cfg.meshY);
    xWidth = chiClog2Min1(cfg.meshX);
    portWidth = chiClog2Min1(cfg.numDevPortsPerXp);
    return cfg.nodeIdW - yWidth - xWidth - portWidth;
  endfunction

  // [SPEC:IHI0050H B13.6.1] RN-F is the only requester with a cache.
  function automatic bit chiClassHasCache(input chiNodeClassE nodeClass);
    return nodeClass == CHI_NODE_CLASS_RNF;
  endfunction

  // [SPEC:IHI0050H B13.6.1] RN-I has no SNP channel. RN-D uses SNP for DVM.
  function automatic bit chiClassHasSnoop(input chiNodeClassE nodeClass);
    return (nodeClass == CHI_NODE_CLASS_RNF)
      || (nodeClass == CHI_NODE_CLASS_RND);
  endfunction

  // [SPEC:IHI0050H B15.1] SYSCO connects RN-F to coherency and RN-D to DVM.
  function automatic bit chiClassHasSysCo(input chiNodeClassE nodeClass);
    return (nodeClass == CHI_NODE_CLASS_RNF)
      || (nodeClass == CHI_NODE_CLASS_RND);
  endfunction

  function automatic bit chiClassIsRequester(input chiNodeClassE nodeClass);
    return (nodeClass == CHI_NODE_CLASS_RNF)
      || (nodeClass == CHI_NODE_CLASS_RND)
      || (nodeClass == CHI_NODE_CLASS_RNI);
  endfunction

  function automatic bit chiClassIsSubordinate(input chiNodeClassE nodeClass);
    return (nodeClass == CHI_NODE_CLASS_SNF)
      || (nodeClass == CHI_NODE_CLASS_SNI);
  endfunction

  function automatic chiNodeClassE chiNodeClassOf(
    input chi_cfg_t cfg,
    input int unsigned ordinal
  );
    if (ordinal < cfg.numRnf)
      return CHI_NODE_CLASS_RNF;
    else if (ordinal < chiOffRni(cfg))
      return CHI_NODE_CLASS_RND;
    else if (ordinal < chiOffSnf(cfg))
      return CHI_NODE_CLASS_RNI;
    else if (ordinal < chiOffSni(cfg))
      return CHI_NODE_CLASS_SNF;
    else if (ordinal < chiOffHnf(cfg))
      return CHI_NODE_CLASS_SNI;
    else if (ordinal < chiOffHni(cfg))
      return CHI_NODE_CLASS_HNF;
    else if (ordinal < chiOffMn(cfg))
      return CHI_NODE_CLASS_HNI;
    else
      return CHI_NODE_CLASS_MN;
  endfunction

  function automatic int unsigned chiNodeIndexOf(
    input chi_cfg_t cfg,
    input int unsigned ordinal
  );
    chiNodeClassE nodeClass;
    nodeClass = chiNodeClassOf(cfg, ordinal);
    if (nodeClass == CHI_NODE_CLASS_RNF)
      return ordinal;
    else if (nodeClass == CHI_NODE_CLASS_RND)
      return ordinal - chiOffRnd(cfg);
    else if (nodeClass == CHI_NODE_CLASS_RNI)
      return ordinal - chiOffRni(cfg);
    else if (nodeClass == CHI_NODE_CLASS_SNF)
      return ordinal - chiOffSnf(cfg);
    else if (nodeClass == CHI_NODE_CLASS_SNI)
      return ordinal - chiOffSni(cfg);
    else if (nodeClass == CHI_NODE_CLASS_HNF)
      return ordinal - chiOffHnf(cfg);
    else if (nodeClass == CHI_NODE_CLASS_HNI)
      return ordinal - chiOffHni(cfg);
    else
      return ordinal - chiOffMn(cfg);
  endfunction

  typedef struct packed {
    int unsigned meshX;
    int unsigned meshY;
    int unsigned devicePort;
  } chiMeshCoordT;

  // Packed return so this stays a constant function for parameter overrides.
  function automatic chiMeshCoordT chiMeshCoords(
    input chi_cfg_t cfg,
    input int unsigned ordinal
  );
    chiMeshCoordT coord;
    int unsigned ports;
    int unsigned xDim;
    int unsigned slot;
    ports = cfg.numDevPortsPerXp;
    xDim = cfg.meshX;
    if (ports == 0)
      ports = 1;
    if (xDim == 0)
      xDim = 1;
    coord.devicePort = ordinal % ports;
    slot = ordinal / ports;
    coord.meshX = slot % xDim;
    coord.meshY = slot / xDim;
    return coord;
  endfunction

  function automatic logic [CHI_MAX_NODEID_W-1:0] chiFieldMask(
    input int unsigned width
  );
    logic [CHI_MAX_NODEID_W-1:0] mask;
    int unsigned bitNumber;
    mask = '0;
    for (bitNumber = 0; bitNumber < width; bitNumber++) begin
      if (bitNumber < CHI_MAX_NODEID_W)
        mask[bitNumber] = 1'b1;
    end
    return mask;
  endfunction

  // [ASSUMPTION:5] deviceId is the ordinal. LSB-first packing.
  function automatic logic [CHI_MAX_NODEID_W-1:0] chiNodeIdForOrdinal(
    input chi_cfg_t cfg,
    input int unsigned ordinal
  );
    int unsigned yWidth;
    int unsigned xWidth;
    int unsigned portWidth;
    int unsigned deviceWidth;
    chiMeshCoordT coord;
    logic [CHI_MAX_NODEID_W-1:0] identifier;
    yWidth = chiClog2Min1(cfg.meshY);
    xWidth = chiClog2Min1(cfg.meshX);
    portWidth = chiClog2Min1(cfg.numDevPortsPerXp);
    deviceWidth = chiDeviceIdWidth(cfg);
    coord = chiMeshCoords(cfg, ordinal);
    identifier = '0;
    identifier |= (CHI_MAX_NODEID_W'(ordinal) & chiFieldMask(deviceWidth));
    identifier |= (CHI_MAX_NODEID_W'(coord.devicePort) & chiFieldMask(portWidth))
      << deviceWidth;
    identifier |= (CHI_MAX_NODEID_W'(coord.meshX) & chiFieldMask(xWidth))
      << (deviceWidth + portWidth);
    identifier |= (CHI_MAX_NODEID_W'(coord.meshY) & chiFieldMask(yWidth))
      << (deviceWidth + portWidth + xWidth);
    return identifier;
  endfunction

  function automatic chiNodeIdArrayT chiMakeNodeIds(input chi_cfg_t cfg);
    chiNodeIdArrayT identifiers;
    int unsigned ordinal;
    identifiers = '{default: '0};
    for (ordinal = 0; ordinal < chiNumNodes(cfg); ordinal++)
      identifiers[ordinal] = chiNodeIdForOrdinal(cfg, ordinal);
    return identifiers;
  endfunction

  function automatic chi_mesh_placement_t chiMakeOnePlacement(
    input chi_cfg_t cfg,
    input int unsigned ordinal
  );
    chi_mesh_placement_t placement;
    chiMeshCoordT coord;
    placement = '0;
    placement.valid = 1'b1;
    coord = chiMeshCoords(cfg, ordinal);
    // type() keeps the assignment legal without naming the DUT enum.
    placement.meshX = type(placement.meshX)'(coord.meshX);
    placement.meshY = type(placement.meshY)'(coord.meshY);
    placement.devicePort = type(placement.devicePort)'(coord.devicePort);
    placement.nodeClass = type(placement.nodeClass)'(chiNodeClassOf(cfg, ordinal));
    placement.nodeIndex = type(placement.nodeIndex)'(chiNodeIndexOf(cfg, ordinal));
    return placement;
  endfunction

  // Procedural form of the placement table. The DUT parameter uses the
  // assignment pattern in chiDutElab.svh, because a function that returns
  // an unpacked array of structs is not a constant expression here.
  function automatic chiPlacementArrayT chiMakePlacements(input chi_cfg_t cfg);
    chiPlacementArrayT placements;
    int unsigned ordinal;
    for (ordinal = 0; ordinal < chiNumNodes(cfg); ordinal++)
      placements[ordinal] = chiMakeOnePlacement(cfg, ordinal);
    return placements;
  endfunction

  // [ASSUMPTION:10] Non-secure, Realm, and Non-secure Protected.
  function automatic bit chiPasIsNonSecure(input logic [2:0] pas);
    return (pas == CHI_PAS_NON_SECURE)
      || (pas == CHI_PAS_REALM)
      || (pas == CHI_PAS_NON_SECURE_PROTECTED);
  endfunction

  function automatic logic [3:0] chiRegionAttributes(
    input logic [1:0] kind,
    input logic secureOnly,
    input logic valid
  );
    return {kind, secureOnly, valid};
  endfunction

  function automatic int unsigned chiMecStreamWidth(input chi_cfg_t cfg);
    if (cfg.mecEn || cfg.cdaEn)
      return 16;
    return 0;
  endfunction

  function automatic int unsigned chiSecSidWidth(input chi_cfg_t cfg);
    if (cfg.cdaEn)
      return 1;
    return 0;
  endfunction

  // [SPEC:IHI0050H B13.9.1] Optional tails follow the enabled config.
  // [ASSUMPTION:7] PBHA contributes no bits.
  function automatic int unsigned chiReqFlitWidth(input chi_cfg_t cfg);
    return 4 + cfg.nodeIdW + cfg.nodeIdW + 12 + cfg.nodeIdW + 1 + 12
      + 7 + 1 + 6 + cfg.addrW + 3 + 1 + 1 + 2 + 4 + 4 + 1 + 8 + 1 + 1
      + 2 + 1 + cfg.mpamW + chiMecStreamWidth(cfg) + chiSecSidWidth(cfg)
      + cfg.rsvdcW;
  endfunction

  // [SPEC:IHI0050H B13.9.2]
  function automatic int unsigned chiRspFlitWidth(input chi_cfg_t cfg);
    return 4 + cfg.nodeIdW + cfg.nodeIdW + 12 + 5 + 2 + 3 + 3 + 3 + 12
      + 4 + 2 + 1 + 6;
  endfunction

  // [SPEC:IHI0050H B13.9.3] SNP address is addrW-3 bits.
  function automatic int unsigned chiSnpFlitWidth(input chi_cfg_t cfg);
    int unsigned mecWidth;
    mecWidth = cfg.mecEn ? 16 : 0;
    return 4 + cfg.nodeIdW + 12 + cfg.nodeIdW + 12 + 5 + (cfg.addrW - 3)
      + 3 + 1 + 1 + 1 + cfg.mpamW + mecWidth;
  endfunction

  // [SPEC:IHI0050H B13.9.4] Tag and TU are always present.
  // [ASSUMPTION:7] DataCheck and Poison follow their enables.
  function automatic int unsigned chiDatFlitWidth(input chi_cfg_t cfg);
    int unsigned mecWidth;
    int unsigned dataCheckWidth;
    int unsigned poisonWidth;
    mecWidth = cfg.mecEn ? 16 : 0;
    dataCheckWidth = cfg.dataCheckEn ? (cfg.dataW / 8) : 0;
    poisonWidth = cfg.poisonEn ? (cfg.dataW / 64) : 0;
    return 4 + cfg.nodeIdW + cfg.nodeIdW + 12 + cfg.nodeIdW + 4 + 2 + 3
      + 8 + 1 + 3 + mecWidth + 16 + 2 + 2 + 6 + 2 + (cfg.dataW / 32)
      + (cfg.dataW / 128) + 1 + 1 + 2 + 1 + cfg.rsvdcW + (cfg.dataW / 8)
      + cfg.dataW + dataCheckWidth + poisonWidth;
  endfunction

  function automatic int unsigned chiDataBeats(input chi_cfg_t cfg);
    return (CHI_TB_CACHE_LINE_BYTES * 8) / cfg.dataW;
  endfunction

  // [ASSUMPTION:9] Legal lcrdDepth is already at least 2, so this is the
  // advertised credit count and the hard grant cap.
  function automatic int unsigned chiLcrdCap(input chi_cfg_t cfg);
    return cfg.lcrdDepth;
  endfunction

  function automatic void chiPutBits(
    ref chiFlitBitsT packedFlit,
    ref int unsigned bitIndex,
    input chiFlitBitsT value,
    input int unsigned width
  );
    int unsigned bitNumber;
    for (bitNumber = 0; bitNumber < width; bitNumber++)
      packedFlit[bitIndex + bitNumber] = value[bitNumber];
    bitIndex += width;
  endfunction

  function automatic chiFlitBitsT chiGetBits(
    input chiFlitBitsT packedFlit,
    ref int unsigned bitIndex,
    input int unsigned width
  );
    chiFlitBitsT value;
    int unsigned bitNumber;
    value = '0;
    for (bitNumber = 0; bitNumber < width; bitNumber++)
      value[bitNumber] = packedFlit[bitIndex + bitNumber];
    bitIndex += width;
    return value;
  endfunction

  function automatic chiFlitBitsT chiPackReqFlit(
    input chi_cfg_t cfg,
    input chiReqFlitT flit
  );
    chiFlitBitsT packedFlit;
    int unsigned bitIndex;
    logic [5:0] sizeSlot;
    chiFlitBitsT mecOrStream;
    packedFlit = '0;
    bitIndex = 0;
    sizeSlot = flit.multiReq ? flit.numReq : {3'b0, flit.size};
    mecOrStream = '0;
    if (cfg.mecEn)
      mecOrStream = flit.mecId;
    else if (cfg.cdaEn)
      mecOrStream = flit.streamId;
    chiPutBits(packedFlit, bitIndex, flit.qos, 4);
    chiPutBits(packedFlit, bitIndex, flit.tgtId, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.srcId, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.txnId, 12);
    chiPutBits(packedFlit, bitIndex, flit.returnNid, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.opcodeCtrl, 1);
    chiPutBits(packedFlit, bitIndex, flit.returnTxnId, 12);
    chiPutBits(packedFlit, bitIndex, flit.opcode, 7);
    chiPutBits(packedFlit, bitIndex, flit.multiReq, 1);
    chiPutBits(packedFlit, bitIndex, sizeSlot, 6);
    chiPutBits(packedFlit, bitIndex, flit.addr, cfg.addrW);
    chiPutBits(packedFlit, bitIndex, flit.pas, 3);
    chiPutBits(packedFlit, bitIndex, flit.likelyShared, 1);
    chiPutBits(packedFlit, bitIndex, flit.allowRetry, 1);
    chiPutBits(packedFlit, bitIndex, flit.order, 2);
    chiPutBits(packedFlit, bitIndex, flit.pCrdType, 4);
    chiPutBits(packedFlit, bitIndex, flit.memAttr, 4);
    chiPutBits(packedFlit, bitIndex, flit.snpAttr, 1);
    chiPutBits(packedFlit, bitIndex, flit.groupSlot, 8);
    chiPutBits(packedFlit, bitIndex, flit.excl, 1);
    chiPutBits(packedFlit, bitIndex, flit.expCompAck, 1);
    chiPutBits(packedFlit, bitIndex, flit.tagOp, 2);
    chiPutBits(packedFlit, bitIndex, flit.traceTag, 1);
    chiPutBits(packedFlit, bitIndex, flit.mpam, cfg.mpamW);
    chiPutBits(packedFlit, bitIndex, mecOrStream, chiMecStreamWidth(cfg));
    chiPutBits(packedFlit, bitIndex, flit.secSid1, chiSecSidWidth(cfg));
    chiPutBits(packedFlit, bitIndex, flit.rsvdc, cfg.rsvdcW);
    return packedFlit;
  endfunction

  function automatic chiReqFlitT chiUnpackReqFlit(
    input chi_cfg_t cfg,
    input chiFlitBitsT packedFlit
  );
    chiReqFlitT flit;
    int unsigned bitIndex;
    logic [5:0] sizeSlot;
    chiFlitBitsT mecOrStream;
    bitIndex = 0;
    flit = '0;
    flit.qos = chiGetBits(packedFlit, bitIndex, 4);
    flit.tgtId = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.srcId = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.txnId = chiGetBits(packedFlit, bitIndex, 12);
    flit.returnNid = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.opcodeCtrl = chiGetBits(packedFlit, bitIndex, 1);
    flit.returnTxnId = chiGetBits(packedFlit, bitIndex, 12);
    flit.opcode = chiGetBits(packedFlit, bitIndex, 7);
    flit.multiReq = chiGetBits(packedFlit, bitIndex, 1);
    sizeSlot = chiGetBits(packedFlit, bitIndex, 6);
    flit.numReq = sizeSlot;
    flit.size = sizeSlot[2:0];
    flit.addr = chiGetBits(packedFlit, bitIndex, cfg.addrW);
    flit.pas = chiGetBits(packedFlit, bitIndex, 3);
    flit.likelyShared = chiGetBits(packedFlit, bitIndex, 1);
    flit.allowRetry = chiGetBits(packedFlit, bitIndex, 1);
    flit.order = chiGetBits(packedFlit, bitIndex, 2);
    flit.pCrdType = chiGetBits(packedFlit, bitIndex, 4);
    flit.memAttr = chiGetBits(packedFlit, bitIndex, 4);
    flit.snpAttr = chiGetBits(packedFlit, bitIndex, 1);
    flit.groupSlot = chiGetBits(packedFlit, bitIndex, 8);
    flit.excl = chiGetBits(packedFlit, bitIndex, 1);
    flit.expCompAck = chiGetBits(packedFlit, bitIndex, 1);
    flit.tagOp = chiGetBits(packedFlit, bitIndex, 2);
    flit.traceTag = chiGetBits(packedFlit, bitIndex, 1);
    flit.mpam = chiGetBits(packedFlit, bitIndex, cfg.mpamW);
    mecOrStream = chiGetBits(packedFlit, bitIndex, chiMecStreamWidth(cfg));
    if (cfg.mecEn)
      flit.mecId = mecOrStream;
    else if (cfg.cdaEn)
      flit.streamId = mecOrStream;
    flit.secSid1 = chiGetBits(packedFlit, bitIndex, chiSecSidWidth(cfg));
    flit.rsvdc = chiGetBits(packedFlit, bitIndex, cfg.rsvdcW);
    return flit;
  endfunction

  function automatic chiFlitBitsT chiPackRspFlit(
    input chi_cfg_t cfg,
    input chiRspFlitT flit
  );
    chiFlitBitsT packedFlit;
    int unsigned bitIndex;
    packedFlit = '0;
    bitIndex = 0;
    chiPutBits(packedFlit, bitIndex, flit.qos, 4);
    chiPutBits(packedFlit, bitIndex, flit.tgtId, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.srcId, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.txnId, 12);
    chiPutBits(packedFlit, bitIndex, flit.opcode, 5);
    chiPutBits(packedFlit, bitIndex, flit.respErr, 2);
    chiPutBits(packedFlit, bitIndex, flit.resp, 3);
    chiPutBits(packedFlit, bitIndex, flit.fwdState, 3);
    chiPutBits(packedFlit, bitIndex, flit.cBusy, 3);
    chiPutBits(packedFlit, bitIndex, flit.dbid, 12);
    chiPutBits(packedFlit, bitIndex, flit.pCrdType, 4);
    chiPutBits(packedFlit, bitIndex, flit.tagOp, 2);
    chiPutBits(packedFlit, bitIndex, flit.traceTag, 1);
    chiPutBits(packedFlit, bitIndex, flit.cacheLineId, 6);
    return packedFlit;
  endfunction

  function automatic chiRspFlitT chiUnpackRspFlit(
    input chi_cfg_t cfg,
    input chiFlitBitsT packedFlit
  );
    chiRspFlitT flit;
    int unsigned bitIndex;
    bitIndex = 0;
    flit = '0;
    flit.qos = chiGetBits(packedFlit, bitIndex, 4);
    flit.tgtId = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.srcId = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.txnId = chiGetBits(packedFlit, bitIndex, 12);
    flit.opcode = chiGetBits(packedFlit, bitIndex, 5);
    flit.respErr = chiGetBits(packedFlit, bitIndex, 2);
    flit.resp = chiGetBits(packedFlit, bitIndex, 3);
    flit.fwdState = chiGetBits(packedFlit, bitIndex, 3);
    flit.cBusy = chiGetBits(packedFlit, bitIndex, 3);
    flit.dbid = chiGetBits(packedFlit, bitIndex, 12);
    flit.pCrdType = chiGetBits(packedFlit, bitIndex, 4);
    flit.tagOp = chiGetBits(packedFlit, bitIndex, 2);
    flit.traceTag = chiGetBits(packedFlit, bitIndex, 1);
    flit.cacheLineId = chiGetBits(packedFlit, bitIndex, 6);
    return flit;
  endfunction

  function automatic chiFlitBitsT chiPackSnpFlit(
    input chi_cfg_t cfg,
    input chiSnpFlitT flit
  );
    chiFlitBitsT packedFlit;
    int unsigned bitIndex;
    int unsigned mecWidth;
    packedFlit = '0;
    bitIndex = 0;
    mecWidth = cfg.mecEn ? 16 : 0;
    chiPutBits(packedFlit, bitIndex, flit.qos, 4);
    chiPutBits(packedFlit, bitIndex, flit.srcId, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.txnId, 12);
    chiPutBits(packedFlit, bitIndex, flit.fwdNid, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.fwdTxnId, 12);
    chiPutBits(packedFlit, bitIndex, flit.opcode, 5);
    // [SPEC:IHI0050H B13.10.20] SNP Addr[0] is architectural Addr[3].
    chiPutBits(packedFlit, bitIndex, flit.addr >> 3, cfg.addrW - 3);
    chiPutBits(packedFlit, bitIndex, flit.pas, 3);
    chiPutBits(packedFlit, bitIndex, flit.doNotGoToSd, 1);
    chiPutBits(packedFlit, bitIndex, flit.retToSrc, 1);
    chiPutBits(packedFlit, bitIndex, flit.traceTag, 1);
    chiPutBits(packedFlit, bitIndex, flit.mpam, cfg.mpamW);
    chiPutBits(packedFlit, bitIndex, flit.mecId, mecWidth);
    return packedFlit;
  endfunction

  function automatic chiSnpFlitT chiUnpackSnpFlit(
    input chi_cfg_t cfg,
    input chiFlitBitsT packedFlit
  );
    chiSnpFlitT flit;
    int unsigned bitIndex;
    int unsigned mecWidth;
    chiFlitBitsT addressBits;
    bitIndex = 0;
    mecWidth = cfg.mecEn ? 16 : 0;
    flit = '0;
    flit.qos = chiGetBits(packedFlit, bitIndex, 4);
    flit.srcId = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.txnId = chiGetBits(packedFlit, bitIndex, 12);
    flit.fwdNid = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.fwdTxnId = chiGetBits(packedFlit, bitIndex, 12);
    flit.opcode = chiGetBits(packedFlit, bitIndex, 5);
    addressBits = chiGetBits(packedFlit, bitIndex, cfg.addrW - 3);
    flit.addr = addressBits << 3;
    flit.pas = chiGetBits(packedFlit, bitIndex, 3);
    flit.doNotGoToSd = chiGetBits(packedFlit, bitIndex, 1);
    flit.retToSrc = chiGetBits(packedFlit, bitIndex, 1);
    flit.traceTag = chiGetBits(packedFlit, bitIndex, 1);
    flit.mpam = chiGetBits(packedFlit, bitIndex, cfg.mpamW);
    flit.mecId = chiGetBits(packedFlit, bitIndex, mecWidth);
    return flit;
  endfunction

  function automatic chiFlitBitsT chiPackDatFlit(
    input chi_cfg_t cfg,
    input chiDatFlitT flit
  );
    chiFlitBitsT packedFlit;
    int unsigned bitIndex;
    int unsigned mecWidth;
    int unsigned dataCheckWidth;
    int unsigned poisonWidth;
    packedFlit = '0;
    bitIndex = 0;
    mecWidth = cfg.mecEn ? 16 : 0;
    dataCheckWidth = cfg.dataCheckEn ? (cfg.dataW / 8) : 0;
    poisonWidth = cfg.poisonEn ? (cfg.dataW / 64) : 0;
    chiPutBits(packedFlit, bitIndex, flit.qos, 4);
    chiPutBits(packedFlit, bitIndex, flit.tgtId, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.srcId, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.txnId, 12);
    chiPutBits(packedFlit, bitIndex, flit.homeNid, cfg.nodeIdW);
    chiPutBits(packedFlit, bitIndex, flit.opcode, 4);
    chiPutBits(packedFlit, bitIndex, flit.respErr, 2);
    chiPutBits(packedFlit, bitIndex, flit.resp, 3);
    chiPutBits(packedFlit, bitIndex, flit.dataSource, 8);
    chiPutBits(packedFlit, bitIndex, flit.dataPull, 1);
    chiPutBits(packedFlit, bitIndex, flit.cBusy, 3);
    chiPutBits(packedFlit, bitIndex, flit.mecId, mecWidth);
    chiPutBits(packedFlit, bitIndex, flit.dbid, 16);
    chiPutBits(packedFlit, bitIndex, flit.ccid, 2);
    chiPutBits(packedFlit, bitIndex, flit.dataId, 2);
    chiPutBits(packedFlit, bitIndex, flit.cacheLineId, 6);
    chiPutBits(packedFlit, bitIndex, flit.tagOp, 2);
    chiPutBits(packedFlit, bitIndex, flit.tag, cfg.dataW / 32);
    chiPutBits(packedFlit, bitIndex, flit.tu, cfg.dataW / 128);
    chiPutBits(packedFlit, bitIndex, flit.traceTag, 1);
    chiPutBits(packedFlit, bitIndex, flit.cah, 1);
    chiPutBits(packedFlit, bitIndex, flit.numDat, 2);
    chiPutBits(packedFlit, bitIndex, flit.replicate, 1);
    chiPutBits(packedFlit, bitIndex, flit.rsvdc, cfg.rsvdcW);
    chiPutBits(packedFlit, bitIndex, flit.be, cfg.dataW / 8);
    chiPutBits(packedFlit, bitIndex, flit.data, cfg.dataW);
    chiPutBits(packedFlit, bitIndex, flit.dataCheck, dataCheckWidth);
    chiPutBits(packedFlit, bitIndex, flit.poison, poisonWidth);
    return packedFlit;
  endfunction

  function automatic chiDatFlitT chiUnpackDatFlit(
    input chi_cfg_t cfg,
    input chiFlitBitsT packedFlit
  );
    chiDatFlitT flit;
    int unsigned bitIndex;
    int unsigned mecWidth;
    int unsigned dataCheckWidth;
    int unsigned poisonWidth;
    bitIndex = 0;
    mecWidth = cfg.mecEn ? 16 : 0;
    dataCheckWidth = cfg.dataCheckEn ? (cfg.dataW / 8) : 0;
    poisonWidth = cfg.poisonEn ? (cfg.dataW / 64) : 0;
    flit = '0;
    flit.qos = chiGetBits(packedFlit, bitIndex, 4);
    flit.tgtId = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.srcId = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.txnId = chiGetBits(packedFlit, bitIndex, 12);
    flit.homeNid = chiGetBits(packedFlit, bitIndex, cfg.nodeIdW);
    flit.opcode = chiGetBits(packedFlit, bitIndex, 4);
    flit.respErr = chiGetBits(packedFlit, bitIndex, 2);
    flit.resp = chiGetBits(packedFlit, bitIndex, 3);
    flit.dataSource = chiGetBits(packedFlit, bitIndex, 8);
    flit.dataPull = chiGetBits(packedFlit, bitIndex, 1);
    flit.cBusy = chiGetBits(packedFlit, bitIndex, 3);
    flit.mecId = chiGetBits(packedFlit, bitIndex, mecWidth);
    flit.dbid = chiGetBits(packedFlit, bitIndex, 16);
    flit.ccid = chiGetBits(packedFlit, bitIndex, 2);
    flit.dataId = chiGetBits(packedFlit, bitIndex, 2);
    flit.cacheLineId = chiGetBits(packedFlit, bitIndex, 6);
    flit.tagOp = chiGetBits(packedFlit, bitIndex, 2);
    flit.tag = chiGetBits(packedFlit, bitIndex, cfg.dataW / 32);
    flit.tu = chiGetBits(packedFlit, bitIndex, cfg.dataW / 128);
    flit.traceTag = chiGetBits(packedFlit, bitIndex, 1);
    flit.cah = chiGetBits(packedFlit, bitIndex, 1);
    flit.numDat = chiGetBits(packedFlit, bitIndex, 2);
    flit.replicate = chiGetBits(packedFlit, bitIndex, 1);
    flit.rsvdc = chiGetBits(packedFlit, bitIndex, cfg.rsvdcW);
    flit.be = chiGetBits(packedFlit, bitIndex, cfg.dataW / 8);
    flit.data = chiGetBits(packedFlit, bitIndex, cfg.dataW);
    flit.dataCheck = chiGetBits(packedFlit, bitIndex, dataCheckWidth);
    flit.poison = chiGetBits(packedFlit, bitIndex, poisonWidth);
    return flit;
  endfunction

  // [SPEC:IHI0050H B9.3.1] Odd parity, least-significant check bit over the
  // least-significant byte. A short tail byte is still covered.
  function automatic logic [CHI_TB_MAX_FLIT_CHK_W-1:0] chiOddByteParity(
    input chiFlitBitsT payload,
    input int unsigned width
  );
    logic [CHI_TB_MAX_FLIT_CHK_W-1:0] checkBits;
    int unsigned byteIndex;
    int unsigned bitIndex;
    int unsigned numBytes;
    logic parityBit;
    checkBits = '0;
    numBytes = (width + 7) / 8;
    for (byteIndex = 0; byteIndex < numBytes; byteIndex++) begin
      parityBit = 1'b0;
      for (bitIndex = 0; bitIndex < 8; bitIndex++) begin
        if ((byteIndex * 8 + bitIndex) < width)
          parityBit ^= payload[byteIndex * 8 + bitIndex];
      end
      checkBits[byteIndex] = ~parityBit;
    end
    return checkBits;
  endfunction

  function automatic chiLinkStateE chiEncodeLinkState(
    input logic linkActiveReq,
    input logic linkActiveAck
  );
    return chiLinkStateE'({linkActiveReq, linkActiveAck});
  endfunction

  function automatic chiReqFlitT chiZeroReqFlit();
    chiReqFlitT flit;
    flit = '0;
    return flit;
  endfunction

  function automatic chiRspFlitT chiZeroRspFlit();
    chiRspFlitT flit;
    flit = '0;
    return flit;
  endfunction

  function automatic chiDatFlitT chiZeroDatFlit();
    chiDatFlitT flit;
    flit = '0;
    return flit;
  endfunction

endpackage
