package chi_pkg;
  import chi_cfg_pkg::*;

  // Issue H flit totals (IHI 0050H B13.9). The constant terms below are the
  // spec totals with every variable-width field at its minimum, so the
  // maxima here are the spec formulas evaluated at their widest legal point.
  localparam int unsigned CHI_REQ_FIXED_W = 72;
  localparam int unsigned CHI_RSP_FIXED_W = 57;
  localparam int unsigned CHI_SNP_FIXED_W = 39;
  localparam int unsigned CHI_DAT_FIXED_W = 70;

  localparam int unsigned CHI_MAX_REQ_FLIT_W = CHI_REQ_FIXED_W
      + (3 * CHI_MAX_NODEID_W) + CHI_MAX_ADDR_W + CHI_MAX_RSVDC_W
      + CHI_MPAM_W + CHI_PBHA_W + 1 + CHI_STREAMID_W;
  localparam int unsigned CHI_MAX_RSP_FLIT_W = CHI_RSP_FIXED_W
      + (2 * CHI_MAX_NODEID_W);
  localparam int unsigned CHI_MAX_SNP_FLIT_W = CHI_SNP_FIXED_W
      + (2 * CHI_MAX_NODEID_W) + (CHI_MAX_ADDR_W - 3)
      + CHI_MPAM_W + CHI_MECID_W;
  localparam int unsigned CHI_MAX_DAT_FLIT_W = CHI_DAT_FIXED_W
      + (3 * CHI_MAX_NODEID_W) + CHI_MECID_W + CHI_MAX_RSVDC_W
      + 512 + (512 / 8) + (512 / 32) + (512 / 128)
      + (512 / 8) + (512 / 64);
  localparam int unsigned CHI_MAX_NOC_PAYLOAD_W = CHI_MAX_DAT_FLIT_W;

  typedef enum logic [1:0] {
    CHI_CHANNEL_REQ = 2'b00,
    CHI_CHANNEL_RSP = 2'b01,
    CHI_CHANNEL_SNP = 2'b10,
    CHI_CHANNEL_DAT = 2'b11
  } chi_channel_e;

  // Why the Requester-side SAM refused a request. The request still goes to
  // a Home, which completes it with NDERR (IHI 0050H B9.1.1).
  typedef enum logic [1:0] {
    NOC_ERR_NONE    = 2'd0,
    NOC_ERR_ADDRESS = 2'd1,  // no region maps the address
    NOC_ERR_PAS     = 2'd2   // the region does not allow the request's PAS
  } chi_noc_err_e;

  // Internal fabric flit. hops counts the crosspoint-to-crosspoint links the
  // flit has crossed and decodeErr carries a SAM refusal to the Home; both are
  // fabric bookkeeping, never part of a CHI message. hops lets the bound
  // assertions bound the route length per topology.
  typedef struct packed {
    chi_channel_e channel;
    logic [3:0] qos;
    logic [CHI_MAX_NODEID_W-1:0] targetNodeId;
    logic [7:0] hops;
    chi_noc_err_e decodeErr;
    logic [CHI_MAX_NOC_PAYLOAD_W-1:0] payload;
  } chi_noc_flit_t;

  typedef enum logic [6:0] {
    REQ_LCRD_RETURN                    = 7'h00,
    REQ_READ_SHARED                    = 7'h01,
    REQ_READ_CLEAN                     = 7'h02,
    REQ_READ_ONCE                      = 7'h03,
    REQ_READ_NO_SNP                    = 7'h04,
    REQ_PCRD_RETURN                    = 7'h05,
    REQ_READ_UNIQUE                    = 7'h07,
    REQ_CLEAN_SHARED                   = 7'h08,
    REQ_CLEAN_INVALID                  = 7'h09,
    REQ_MAKE_INVALID                   = 7'h0A,
    REQ_CLEAN_UNIQUE                   = 7'h0B,
    REQ_MAKE_UNIQUE                    = 7'h0C,
    REQ_EVICT                          = 7'h0D,
    REQ_CLEAN_INVALID_STORAGE          = 7'h0E,
    REQ_READ_NO_SNP_SEP                = 7'h11,
    REQ_CLEAN_SHARED_PERSIST_SEP       = 7'h13,
    REQ_DVM_OP                         = 7'h14,
    REQ_WRITE_EVICT_FULL               = 7'h15,
    REQ_WRITE_CLEAN_FULL               = 7'h17,
    REQ_WRITE_UNIQUE_PTL               = 7'h18,
    REQ_WRITE_UNIQUE_FULL              = 7'h19,
    REQ_WRITE_BACK_PTL                 = 7'h1A,
    REQ_WRITE_BACK_FULL                = 7'h1B,
    REQ_WRITE_NO_SNP_PTL               = 7'h1C,
    REQ_WRITE_NO_SNP_FULL              = 7'h1D,
    REQ_WRITE_UNIQUE_FULL_STASH        = 7'h20,
    REQ_WRITE_UNIQUE_PTL_STASH         = 7'h21,
    REQ_STASH_ONCE_SHARED              = 7'h22,
    REQ_STASH_ONCE_UNIQUE              = 7'h23,
    REQ_READ_ONCE_CLEAN_INVALID        = 7'h24,
    REQ_READ_ONCE_MAKE_INVALID         = 7'h25,
    REQ_READ_NOT_SHARED_DIRTY          = 7'h26,
    REQ_CLEAN_SHARED_PERSIST           = 7'h27,
    REQ_ATOMIC_STORE_ADD               = 7'h28,
    REQ_ATOMIC_STORE_CLR               = 7'h29,
    REQ_ATOMIC_STORE_EOR               = 7'h2A,
    REQ_ATOMIC_STORE_SET               = 7'h2B,
    REQ_ATOMIC_STORE_SMAX              = 7'h2C,
    REQ_ATOMIC_STORE_SMIN              = 7'h2D,
    REQ_ATOMIC_STORE_UMAX              = 7'h2E,
    REQ_ATOMIC_STORE_UMIN              = 7'h2F,
    REQ_ATOMIC_LOAD_ADD                = 7'h30,
    REQ_ATOMIC_LOAD_CLR                = 7'h31,
    REQ_ATOMIC_LOAD_EOR                = 7'h32,
    REQ_ATOMIC_LOAD_SET                = 7'h33,
    REQ_ATOMIC_LOAD_SMAX               = 7'h34,
    REQ_ATOMIC_LOAD_SMIN               = 7'h35,
    REQ_ATOMIC_LOAD_UMAX               = 7'h36,
    REQ_ATOMIC_LOAD_UMIN               = 7'h37,
    REQ_ATOMIC_SWAP                    = 7'h38,
    REQ_ATOMIC_COMPARE                 = 7'h39,
    REQ_PREFETCH_TGT                   = 7'h3A,
    REQ_MAKE_READ_UNIQUE               = 7'h41,
    REQ_WRITE_EVICT_OR_EVICT           = 7'h42,
    REQ_WRITE_UNIQUE_ZERO              = 7'h43,
    REQ_WRITE_NO_SNP_ZERO              = 7'h44,
    REQ_STASH_ONCE_SEP_SHARED          = 7'h47,
    REQ_STASH_ONCE_SEP_UNIQUE          = 7'h48,
    REQ_READ_PREFER_UNIQUE             = 7'h4C,
    REQ_CLEAN_INVALID_POPA             = 7'h4D,
    REQ_WRITE_NO_SNP_DEF               = 7'h4E,
    REQ_WRITE_NO_SNP_FULL_CLEAN_SH     = 7'h50,
    REQ_WRITE_NO_SNP_FULL_CLEAN_INV    = 7'h51,
    REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP = 7'h52,
    REQ_WRITE_UNIQUE_FULL_CLEAN_SH     = 7'h54,
    REQ_WRITE_UNIQUE_FULL_CLEAN_SH_PER_SEP = 7'h56,
    REQ_WRITE_UNIQUE_FULL_CLEAN_INV_STRG = 7'h57,
    REQ_WRITE_BACK_FULL_CLEAN_SH       = 7'h58,
    REQ_WRITE_BACK_FULL_CLEAN_INV      = 7'h59,
    REQ_WRITE_BACK_FULL_CLEAN_SH_PER_SEP = 7'h5A,
    REQ_WRITE_BACK_FULL_CLEAN_INV_STRG = 7'h5B,
    REQ_WRITE_CLEAN_FULL_CLEAN_SH      = 7'h5C,
    REQ_WRITE_CLEAN_FULL_CLEAN_SH_PER_SEP = 7'h5E,
    REQ_WRITE_NO_SNP_PTL_CLEAN_SH      = 7'h60,
    REQ_WRITE_NO_SNP_PTL_CLEAN_INV     = 7'h61,
    REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP = 7'h62,
    REQ_WRITE_UNIQUE_PTL_CLEAN_SH      = 7'h64,
    REQ_WRITE_UNIQUE_PTL_CLEAN_SH_PER_SEP = 7'h66,
    REQ_WRITE_NO_SNP_PTL_CLEAN_INV_POPA = 7'h70,
    REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA = 7'h71,
    REQ_WRITE_NO_SNP_FULL_CLEAN_INV_STRG = 7'h72,
    REQ_WRITE_BACK_FULL_CLEAN_INV_POPA = 7'h79
  } chi_req_opcode_e;

  typedef enum logic [4:0] {
    RSP_LCRD_RETURN     = 5'h00, RSP_SNP_RESP       = 5'h01,
    RSP_COMP_ACK        = 5'h02, RSP_RETRY_ACK      = 5'h03,
    RSP_COMP            = 5'h04, RSP_COMP_DBID_RESP = 5'h05,
    RSP_DBID_RESP       = 5'h06, RSP_PCRD_GRANT     = 5'h07,
    RSP_READ_RECEIPT    = 5'h08, RSP_SNP_RESP_FWDED = 5'h09,
    RSP_TAG_MATCH       = 5'h0A, RSP_RESP_SEP_DATA  = 5'h0B,
    RSP_PERSIST         = 5'h0C, RSP_COMP_PERSIST   = 5'h0D,
    RSP_DBID_RESP_ORD   = 5'h0E, RSP_STASH_DONE     = 5'h10,
    RSP_COMP_STASH_DONE = 5'h11, RSP_COMP_CMO       = 5'h14
  } chi_rsp_opcode_e;

  typedef enum logic [4:0] {
    SNP_LCRD_RETURN          = 5'h00, SNP_SHARED             = 5'h01,
    SNP_CLEAN                = 5'h02, SNP_ONCE               = 5'h03,
    SNP_NOT_SHARED_DIRTY     = 5'h04, SNP_UNIQUE_STASH       = 5'h05,
    SNP_MAKE_INVALID_STASH   = 5'h06, SNP_UNIQUE             = 5'h07,
    SNP_CLEAN_SHARED         = 5'h08, SNP_CLEAN_INVALID      = 5'h09,
    SNP_MAKE_INVALID         = 5'h0A, SNP_STASH_UNIQUE       = 5'h0B,
    SNP_STASH_SHARED         = 5'h0C, SNP_DVM_OP             = 5'h0D,
    SNP_QUERY                = 5'h10, SNP_SHARED_FWD         = 5'h11,
    SNP_CLEAN_FWD            = 5'h12, SNP_ONCE_FWD           = 5'h13,
    SNP_NOT_SHARED_DIRTY_FWD = 5'h14, SNP_PREFER_UNIQUE      = 5'h15,
    SNP_PREFER_UNIQUE_FWD    = 5'h16, SNP_UNIQUE_FWD         = 5'h17
  } chi_snp_opcode_e;

  typedef enum logic [3:0] {
    DAT_LCRD_RETURN          = 4'h0, DAT_SNP_RESP_DATA       = 4'h1,
    DAT_COPY_BACK_WR_DATA    = 4'h2, DAT_NON_COPY_BACK_WR_DATA = 4'h3,
    DAT_COMP_DATA            = 4'h4, DAT_SNP_RESP_DATA_PTL   = 4'h5,
    DAT_SNP_RESP_DATA_FWDED  = 4'h6, DAT_WRITE_DATA_CANCEL   = 4'h7,
    DAT_DATA_SEP_RESP        = 4'hB, DAT_NCB_WR_DATA_COMP_ACK = 4'hC
  } chi_dat_opcode_e;

  typedef enum logic [1:0] {
    ORDER_NONE = 2'b00, ORDER_REQUEST_ACCEPTED = 2'b01,
    ORDER_REQUEST_ORDER = 2'b10, ORDER_ENDPOINT = 2'b11
  } chi_order_e;

  typedef enum logic [1:0] {
    RESP_ERR_OK = 2'b00, RESP_ERR_EXOK = 2'b01,
    RESP_ERR_DERR = 2'b10, RESP_ERR_NDERR = 2'b11
  } chi_resp_err_e;

  // Resp[2] is PassDirty and Resp[1:0] is the cache state, so the label set
  // must keep that bit structure (IHI 0050H B13.10.34). RESP_UC_UD is UC in
  // completion responses and UC or UD in snoop responses; RESP_UD_PD is
  // UC_PD in snoop responses.
  typedef enum logic [2:0] {
    RESP_I = 3'b000, RESP_SC = 3'b001, RESP_UC_UD = 3'b010,
    RESP_SD = 3'b011, RESP_I_PD = 3'b100, RESP_SC_PD = 3'b101,
    RESP_UD_PD = 3'b110, RESP_SD_PD = 3'b111
  } chi_resp_e;

  function automatic logic respPassDirty(input chi_resp_e resp);
    return resp[2];
  endfunction

  typedef enum logic [2:0] {
    CACHE_I = 3'b000, CACHE_SC = 3'b001, CACHE_UC = 3'b010,
    CACHE_UD = 3'b011, CACHE_SD = 3'b100, CACHE_UDP = 3'b101
  } chi_cache_state_e;

  typedef enum logic [1:0] {
    TAG_OP_INVALID = 2'b00, TAG_OP_TRANSFER = 2'b01,
    TAG_OP_UPDATE = 2'b10, TAG_OP_MATCH = 2'b11
  } chi_tag_op_e;

  // DVMType values carried in the DVM message payload (IHI 0050H B8.4.1).
  typedef enum logic [2:0] {
    DVM_TYPE_TLBI = 3'b000, DVM_TYPE_BPI = 3'b001,
    DVM_TYPE_PICI = 3'b010, DVM_TYPE_VICI = 3'b011,
    DVM_TYPE_SYNC = 3'b100, DVM_TYPE_RESERVED_5 = 3'b101,
    DVM_TYPE_RESERVED_6 = 3'b110, DVM_TYPE_RESERVED_7 = 3'b111
  } chi_dvm_type_e;

  // Issue H replaces the separate NS and NSE bits with a 3-bit PAS field.
  // System Agent and Non-secure Protected additionally require GDI support
  // (IHI 0050H B13.10.68).
  typedef enum logic [2:0] {
    PAS_SECURE = 3'b000, PAS_NON_SECURE = 3'b001,
    PAS_ROOT = 3'b010, PAS_REALM = 3'b011,
    PAS_SYSTEM_AGENT = 3'b100, PAS_NON_SECURE_PROTECTED = 3'b101,
    PAS_RESERVED_6 = 3'b110, PAS_RESERVED_7 = 3'b111
  } chi_pas_e;

  // Retained so logic written against the pre-Issue-H NS/NSE encoding keeps
  // one definition of what each PAS value means.
  function automatic logic pasNonSecure(input chi_pas_e pas);
    return (pas == PAS_NON_SECURE) || (pas == PAS_REALM)
           || (pas == PAS_NON_SECURE_PROTECTED);
  endfunction

  // The PASs a configuration supports (IHI 0050H Table B13.47): Secure and
  // Non-secure always, Root and Realm with RME, System Agent and Non-secure
  // Protected with RME and GDI. Bit p stands for PAS encoding p; the two
  // reserved encodings are never legal.
  function automatic logic [7:0] pasLegalMask(input chi_cfg_pkg::chi_cfg_t cfg);
    logic [7:0] mask;
    mask = 8'b0000_0011;
    if (cfg.rmeEn)
      mask[3:2] = 2'b11;
    if (cfg.rmeEn && cfg.gdiEn)
      mask[5:4] = 2'b11;
    return mask;
  endfunction

  function automatic logic pasLegal(
    input chi_cfg_pkg::chi_cfg_t cfg,
    input chi_pas_e pas
  );
    logic [7:0] mask;
    mask = pasLegalMask(cfg);
    return mask[pas];
  endfunction

  function automatic logic pasMecIdApplicable(input chi_pas_e pas);
    return (pas == PAS_REALM) || (pas == PAS_SYSTEM_AGENT)
           || (pas == PAS_NON_SECURE_PROTECTED);
  endfunction

  typedef struct packed {
    logic [3:0] qos;
    logic [CHI_MAX_NODEID_W-1:0] tgtId;
    logic [CHI_MAX_NODEID_W-1:0] srcId;
    logic [CHI_MAX_TXNID_W-1:0] txnId;
    logic [CHI_MAX_NODEID_W-1:0] returnNidOrStashNidOrDataTarget;
    logic stashNidValidOrEndianOrDeep;
    logic [CHI_RTNTXNID_SLOT_W-1:0] returnTxnIdOrStashLpid;
    chi_req_opcode_e opcode;
    logic multiReq;
    logic [CHI_NUMREQ_SLOT_W-1:0] numReq;
    logic [2:0] size;
    logic [CHI_MAX_ADDR_W-1:0] addr;
    chi_pas_e pas;
    logic likelyShared;
    logic allowRetry;
    chi_order_e order;
    logic [3:0] pCrdType;
    logic [3:0] memAttr;
    logic snpAttrOrDoDwt;
    logic [CHI_MAX_GROUPID_W-1:0] groupIdOrLpid;
    logic exclOrSnoopMeOrCah;
    logic expCompAck;
    chi_tag_op_e tagOp;
    logic traceTag;
    logic [CHI_MPAM_W-1:0] mpam;
    logic [CHI_PBHA_W-1:0] pbha;
    logic [CHI_MECID_W-1:0] mecId;
    logic [CHI_STREAMID_W-1:0] streamId;
    logic secSid1;
    logic [31:0] rsvdc;
  } chi_req_flit_t;

  typedef struct packed {
    logic [3:0] qos;
    logic [CHI_MAX_NODEID_W-1:0] tgtId;
    logic [CHI_MAX_NODEID_W-1:0] srcId;
    logic [CHI_MAX_TXNID_W-1:0] txnId;
    chi_rsp_opcode_e opcode;
    chi_resp_err_e respErr;
    chi_resp_e resp;
    logic [2:0] fwdState;
    logic [2:0] cBusy;
    logic [CHI_RSP_DBID_SLOT_W-1:0] dbIdOrGroupId;
    logic [3:0] pCrdType;
    chi_tag_op_e tagOp;
    logic traceTag;
    logic [CHI_CACHELINEID_W-1:0] cacheLineId;
  } chi_rsp_flit_t;

  typedef struct packed {
    logic [3:0] qos;
    logic [CHI_MAX_NODEID_W-1:0] srcId;
    logic [CHI_MAX_TXNID_W-1:0] txnId;
    logic [CHI_MAX_NODEID_W-1:0] fwdNidOrPbha;
    logic [CHI_RTNTXNID_SLOT_W-1:0] fwdTxnIdOrStashLpidOrVmidExt;
    chi_snp_opcode_e opcode;
    logic [CHI_MAX_ADDR_W-4:0] addr;
    chi_pas_e pas;
    logic doNotGoToSd;
    logic retToSrc;
    logic traceTag;
    logic [CHI_MPAM_W-1:0] mpam;
    logic [CHI_MECID_W-1:0] mecId;
  } chi_snp_flit_t;

  typedef struct packed {
    logic [3:0] qos;
    logic [CHI_MAX_NODEID_W-1:0] tgtId;
    logic [CHI_MAX_NODEID_W-1:0] srcId;
    logic [CHI_MAX_TXNID_W-1:0] txnId;
    logic [CHI_MAX_NODEID_W-1:0] homeNidOrPbha;
    chi_dat_opcode_e opcode;
    chi_resp_err_e respErr;
    chi_resp_e resp;
    logic [7:0] dataSourceOrFwdState;
    logic dataPull;
    logic [2:0] cBusy;
    logic [CHI_MECID_W-1:0] mecId;
    logic [CHI_DAT_DBID_SLOT_W-1:0] dbId;
    logic [CHI_CCID_SLOT_W-1:0] ccId;
    logic [CHI_DATAID_SLOT_W-1:0] dataId;
    logic [CHI_CACHELINEID_W-1:0] cacheLineId;
    chi_tag_op_e tagOp;
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
  } chi_dat_flit_t;

  function automatic int unsigned maxWidth(input int unsigned firstWidth, input int unsigned secondWidth);
    return (firstWidth > secondWidth) ? firstWidth : secondWidth;
  endfunction

  // Optional-bus widths. Issue H allows MPAM at 12 or 15 bits, and lets the
  // MECID and StreamID buses share one field of width Max(E,R).
  function automatic int unsigned mpamBusWidth(input chi_cfg_t cfg);
    if (!cfg.mpamEn) return 0;
    return (cfg.mpamW == CHI_MPAM_SHORT_W) ? CHI_MPAM_SHORT_W : CHI_MPAM_W;
  endfunction

  function automatic int unsigned mecIdBusWidth(input chi_cfg_t cfg);
    return cfg.mecEn ? CHI_MECID_W : 0;
  endfunction

  function automatic int unsigned streamIdBusWidth(input chi_cfg_t cfg);
    return cfg.cdaEn ? CHI_STREAMID_W : 0;
  endfunction

  function automatic int unsigned reqMecStreamWidth(input chi_cfg_t cfg);
    return maxWidth(mecIdBusWidth(cfg), streamIdBusWidth(cfg));
  endfunction

  function automatic int unsigned pbhaBusWidth(input chi_cfg_t cfg);
    return cfg.pbhaEn ? CHI_PBHA_W : 0;
  endfunction

  function automatic int unsigned secSid1Width(input chi_cfg_t cfg);
    return cfg.cdaEn ? 1 : 0;
  endfunction

  // Total = 93 + RAW + Y + M + PB + S + Max(E,R) at NodeID_Width 7, rising to
  // 120 + ... at NodeID_Width 16 (IHI 0050H B13.9.1).
  function automatic int unsigned reqFlitWidth(input chi_cfg_t cfg);
    return CHI_REQ_FIXED_W + (3 * cfg.nodeIdW) + cfg.addrW + cfg.rsvdcW
           + mpamBusWidth(cfg) + pbhaBusWidth(cfg) + secSid1Width(cfg)
           + reqMecStreamWidth(cfg);
  endfunction

  // Total = 71 to 89 (IHI 0050H B13.9.2).
  function automatic int unsigned rspFlitWidth(input chi_cfg_t cfg);
    return CHI_RSP_FIXED_W + (2 * cfg.nodeIdW);
  endfunction

  // Total = 53 + SAW + M + E to 71 + SAW + M + E (IHI 0050H B13.9.3).
  function automatic int unsigned snpFlitWidth(input chi_cfg_t cfg);
    return CHI_SNP_FIXED_W + (2 * cfg.nodeIdW) + (cfg.addrW - 3)
           + mpamBusWidth(cfg) + mecIdBusWidth(cfg);
  endfunction

  // Total = (240 to 267) + Y + DC + P for a 128-bit data bus, scaling with
  // the data bus width (IHI 0050H B13.9.4).
  function automatic int unsigned datFlitWidth(input chi_cfg_t cfg);
    return CHI_DAT_FIXED_W + (3 * cfg.nodeIdW) + mecIdBusWidth(cfg)
           + cfg.dataW + (cfg.dataW / 8)
           + (cfg.dataW / 32) + (cfg.dataW / 128) + cfg.rsvdcW
           + (cfg.dataCheckEn ? (cfg.dataW / 8) : 0)
           + (cfg.poisonEn ? (cfg.dataW / 64) : 0);
  endfunction

  function automatic int unsigned parityWidth(input int unsigned flitWidth);
    return (flitWidth + 7) / 8;
  endfunction

  // DataID counts 16-byte granules of the 64-byte line, so one DAT packet
  // advances it by the number of granules the data bus carries at once: 1 for
  // a 128-bit bus, 2 for 256-bit, 4 for 512-bit (IHI 0050H B2.4.6,
  // Table B2.16).
  function automatic int unsigned datIdStep(input chi_cfg_t cfg);
    int unsigned step;
    step = (cfg.dataW / 8) / 16;
    return (step == 0) ? 1 : step;
  endfunction

  // DataID of the final packet of the data message for a transfer of 1 << size
  // bytes starting at addr. A transfer of 16 bytes or less is always a single
  // packet, so the first and the final DataID coincide.
  function automatic logic [CHI_DATAID_SLOT_W-1:0] datLastDataId(
    input chi_cfg_t cfg,
    input logic [CHI_MAX_ADDR_W-1:0] addr,
    input logic [2:0] size
  );
    int unsigned lastByte;
    int unsigned granule;
    int unsigned step;
    step = datIdStep(cfg);
    lastByte = (32'(addr[5:0]) + (32'd1 << size) - 32'd1) & 32'h3F;
    granule = (lastByte / 16) & ~(step - 1);
    return CHI_DATAID_SLOT_W'(granule);
  endfunction

  // Whether a received DAT packet completes the data message. NumDat counts
  // the packets elided behind this one, so an elided tail completes the
  // message on the packet that stands in for it (IHI 0050H B2.9.5.1).
  function automatic logic datLastPacket(
    input chi_cfg_t cfg,
    input logic [CHI_DATAID_SLOT_W-1:0] dataId,
    input logic [1:0] numDat,
    input logic [CHI_MAX_ADDR_W-1:0] addr,
    input logic [2:0] size
  );
    int unsigned covered;
    covered = 32'(dataId) + (32'(numDat) * datIdStep(cfg));
    return covered >= 32'(datLastDataId(cfg, addr, size));
  endfunction

  // The result is clamped to the width of the counter so that a nonsensical
  // value cannot spin the loop past the point where the shift wraps.
  function automatic int unsigned clog2Min1(input int unsigned value);
    int unsigned result;
    result = 1;
    while ((result < 31) && ((32'd1 << result) < value))
      result++;
    return result;
  endfunction

  // Size limits for the elaboration-time placement tables. They bound the
  // configurations automatic placement can handle, not the fabric itself.
  localparam int unsigned CHI_MAX_NODES = 128;
  localparam int unsigned CHI_MAX_XP = 256;
  localparam int unsigned CHI_MAX_DEV_PORTS = 16;
  localparam int unsigned CHI_MAX_HNF = 64;

  typedef chi_mesh_placement_t chi_placement_table_t [CHI_MAX_NODES];
  typedef logic [7:0] chi_hnf_snf_table_t [CHI_MAX_HNF];

  // NodeID layout, least significant field first (IHI 0050H B3.2 leaves the
  // assignment to the implementation):
  //
  //   NodeID = {xpId, devicePort, deviceId}
  //
  // xpId is {Y, X} for MESH_2D and the crosspoint index for RING and
  // CROSSBAR. The crosspoints route on xpId and devicePort alone, so deviceId
  // only distinguishes nodes for software and may be zero bits wide.
  function automatic int unsigned numXpOf(input chi_cfg_t cfg);
    return (cfg.topology == MESH_2D) ? (cfg.meshX * cfg.meshY) : cfg.numXp;
  endfunction

  function automatic int unsigned xpIdWidth(input chi_cfg_t cfg);
    if (cfg.topology == MESH_2D)
      return clog2Min1(cfg.meshX) + clog2Min1(cfg.meshY);
    return clog2Min1(cfg.numXp);
  endfunction

  function automatic int unsigned devPortWidth(input chi_cfg_t cfg);
    return clog2Min1(cfg.numDevPortsPerXp);
  endfunction

  function automatic int signed deviceIdWidth(input chi_cfg_t cfg);
    return $signed(cfg.nodeIdW) - $signed(xpIdWidth(cfg))
           - $signed(devPortWidth(cfg));
  endfunction

  // The narrowest NodeID that still carries the routing fields, clamped to
  // the Issue H minimum NodeID_Width (IHI 0050H B16.1.12).
  function automatic int unsigned minNodeIdWidth(input chi_cfg_t cfg);
    int unsigned width;
    width = xpIdWidth(cfg) + devPortWidth(cfg);
    return (width < CHI_MIN_NODEID_W) ? CHI_MIN_NODEID_W : width;
  endfunction

  function automatic logic [CHI_MAX_NODEID_W-1:0] encodeXpNodeId(
    input chi_cfg_t cfg,
    input int unsigned xpIndex,
    input int unsigned devicePort,
    input int unsigned deviceId
  );
    logic [CHI_MAX_NODEID_W-1:0] nodeId;
    int unsigned bitPos;
    int signed idWidthSigned;
    // Every field width is taken once into a local. A loop bound that is itself
    // a function call would be re-evaluated on each iteration, and Verilator
    // 5.020 miscompiles that when the callee contains a loop of its own.
    int unsigned idW;
    int unsigned portW;
    int unsigned xW;
    int unsigned xpW;
    int unsigned xpField;
    nodeId = '0;
    bitPos = 0;
    idWidthSigned = deviceIdWidth(cfg);
    idW = (idWidthSigned > 0) ? int'(idWidthSigned) : 0;
    portW = devPortWidth(cfg);
    xpW = xpIdWidth(cfg);
    if (cfg.topology == MESH_2D) begin
      xW = clog2Min1(cfg.meshX);
      xpField = ((xpIndex / cfg.meshX) << xW) | (xpIndex % cfg.meshX);
    end else begin
      xpField = xpIndex;
    end
    for (int i = 0; i < idW; i++) begin
      nodeId[bitPos] = deviceId[i];
      bitPos++;
    end
    for (int i = 0; i < portW; i++) begin
      nodeId[bitPos] = devicePort[i];
      bitPos++;
    end
    for (int i = 0; i < xpW; i++) begin
      nodeId[bitPos] = xpField[i];
      bitPos++;
    end
    return nodeId;
  endfunction

  // Mesh-coordinate form of encodeXpNodeId, kept for callers that place by
  // (X, Y).
  function automatic logic [CHI_MAX_NODEID_W-1:0] encodeNodeId(
    input chi_cfg_t cfg,
    input int unsigned meshX,
    input int unsigned meshY,
    input int unsigned devicePort,
    input int unsigned deviceId
  );
    return encodeXpNodeId(cfg, meshY * cfg.meshX + meshX, devicePort,
                          deviceId);
  endfunction

  function automatic int unsigned nodeIdField(
    input logic [CHI_MAX_NODEID_W-1:0] nodeId,
    input int unsigned base,
    input int unsigned width
  );
    int unsigned value;
    value = 0;
    for (int unsigned i = 0; i < width; i++)
      if ((base + i) < CHI_MAX_NODEID_W)
        value[i] = nodeId[base + i];
    return value;
  endfunction

  function automatic int unsigned nodeIdDeviceId(input chi_cfg_t cfg, input logic [CHI_MAX_NODEID_W-1:0] nodeId);
    int signed idWidthSigned;
    int unsigned idW;
    idWidthSigned = deviceIdWidth(cfg);
    idW = (idWidthSigned > 0) ? int'(idWidthSigned) : 0;
    return nodeIdField(nodeId, 0, idW);
  endfunction

  function automatic int unsigned nodeIdDevicePort(input chi_cfg_t cfg, input logic [CHI_MAX_NODEID_W-1:0] nodeId);
    int signed idWidthSigned;
    int unsigned idW;
    int unsigned portW;
    idWidthSigned = deviceIdWidth(cfg);
    idW = (idWidthSigned > 0) ? int'(idWidthSigned) : 0;
    portW = devPortWidth(cfg);
    return nodeIdField(nodeId, idW, portW);
  endfunction

  function automatic int unsigned nodeIdXpField(input chi_cfg_t cfg, input logic [CHI_MAX_NODEID_W-1:0] nodeId);
    int signed idWidthSigned;
    int unsigned idW;
    int unsigned portW;
    int unsigned xpW;
    idWidthSigned = deviceIdWidth(cfg);
    idW = (idWidthSigned > 0) ? int'(idWidthSigned) : 0;
    portW = devPortWidth(cfg);
    xpW = xpIdWidth(cfg);
    return nodeIdField(nodeId, idW + portW, xpW);
  endfunction

  function automatic int unsigned nodeIdMeshX(input chi_cfg_t cfg, input logic [CHI_MAX_NODEID_W-1:0] nodeId);
    int unsigned xW;
    xW = clog2Min1(cfg.meshX);
    return nodeIdXpField(cfg, nodeId) & ((32'd1 << xW) - 32'd1);
  endfunction

  function automatic int unsigned nodeIdMeshY(input chi_cfg_t cfg, input logic [CHI_MAX_NODEID_W-1:0] nodeId);
    int unsigned xW;
    xW = clog2Min1(cfg.meshX);
    return nodeIdXpField(cfg, nodeId) >> xW;
  endfunction

  // Linear crosspoint index of the node a NodeID names: Y * meshX + X for a
  // mesh, the xpId field itself for a ring or crossbar.
  function automatic int unsigned nodeIdXpIndex(input chi_cfg_t cfg, input logic [CHI_MAX_NODEID_W-1:0] nodeId);
    if (cfg.topology == MESH_2D)
      return nodeIdMeshY(cfg, nodeId) * cfg.meshX + nodeIdMeshX(cfg, nodeId);
    return nodeIdXpField(cfg, nodeId);
  endfunction

  function automatic int unsigned xpIndexOfPlacement(
    input chi_cfg_t cfg,
    input chi_mesh_placement_t placement
  );
    if (cfg.topology == MESH_2D)
      return int'(placement.meshY) * cfg.meshX + int'(placement.meshX);
    return int'(placement.meshX);
  endfunction

  // Network distance in crosspoint-to-crosspoint links between two
  // crosspoints: Manhattan distance for XY routing, the shorter way round a
  // ring, one link between distinct crossbar crosspoints.
  function automatic int unsigned xpDistance(
    input chi_cfg_t cfg,
    input int unsigned fromXp,
    input int unsigned toXp
  );
    int unsigned fromX;
    int unsigned fromY;
    int unsigned toX;
    int unsigned toY;
    int unsigned clockwise;
    case (cfg.topology)
      MESH_2D: begin
        fromX = fromXp % cfg.meshX;
        fromY = fromXp / cfg.meshX;
        toX = toXp % cfg.meshX;
        toY = toXp / cfg.meshX;
        return ((fromX > toX) ? (fromX - toX) : (toX - fromX))
               + ((fromY > toY) ? (fromY - toY) : (toY - fromY));
      end
      RING: begin
        clockwise = (toXp >= fromXp) ? (toXp - fromXp)
                                     : (toXp + cfg.numXp - fromXp);
        return (clockwise <= (cfg.numXp - clockwise))
               ? clockwise : (cfg.numXp - clockwise);
      end
      default: return (fromXp == toXp) ? 0 : 1;
    endcase
  endfunction

  // The longest route the topology can produce, in links.
  function automatic int unsigned maxXpHops(input chi_cfg_t cfg);
    case (cfg.topology)
      MESH_2D: return (cfg.meshX - 1) + (cfg.meshY - 1);
      RING: return cfg.numXp / 2;
      default: return (cfg.numXp > 1) ? 1 : 0;
    endcase
  endfunction

  // 0 for a corner crosspoint of the mesh, 1 for an edge, 2 for the interior.
  function automatic int unsigned meshXpClass(
    input chi_cfg_t cfg,
    input int unsigned xp
  );
    int unsigned x;
    int unsigned y;
    logic xEdge;
    logic yEdge;
    x = xp % cfg.meshX;
    y = xp / cfg.meshX;
    xEdge = (x == 0) || (x == (cfg.meshX - 1));
    yEdge = (y == 0) || (y == (cfg.meshY - 1));
    if (xEdge && yEdge) return 0;
    if (xEdge || yEdge) return 1;
    return 2;
  endfunction

  function automatic int unsigned classOffset(
    input chi_cfg_t cfg,
    input chi_node_class_e nodeClass
  );
    int unsigned offset;
    offset = 0;
    if (nodeClass == NODE_RNF) return offset;
    offset += cfg.numRnf;
    if (nodeClass == NODE_RND) return offset;
    offset += cfg.numRnd;
    if (nodeClass == NODE_RNI) return offset;
    offset += cfg.numRni;
    if (nodeClass == NODE_SNF) return offset;
    offset += cfg.numSnf;
    if (nodeClass == NODE_SNI) return offset;
    offset += cfg.numSni;
    if (nodeClass == NODE_HNF) return offset;
    offset += cfg.numHnf;
    if (nodeClass == NODE_HNI) return offset;
    offset += cfg.numHni;
    return offset;
  endfunction

  function automatic int unsigned classCount(
    input chi_cfg_t cfg,
    input chi_node_class_e nodeClass
  );
    case (nodeClass)
      NODE_RNF: return cfg.numRnf;
      NODE_RND: return cfg.numRnd;
      NODE_RNI: return cfg.numRni;
      NODE_SNF: return cfg.numSnf;
      NODE_SNI: return cfg.numSni;
      NODE_HNF: return cfg.numHnf;
      NODE_HNI: return cfg.numHni;
      default:  return cfg.numMn;
    endcase
  endfunction

  // The SN-F whose memory an HN-F serves.
  function automatic int unsigned snfIndexOfHnf(
    input chi_cfg_t cfg,
    input chi_hnf_snf_table_t hnfSnfTable,
    input int unsigned hnfIndex
  );
    if (cfg.numSnf == 0) return 0;
    if (cfg.hnfSnfMap == HNF_SNF_MAP_TABLE) return int'(hnfSnfTable[hnfIndex]);
    return hnfIndex % cfg.numSnf;
  endfunction

  // Elaboration-time placement for any population (IHI 0050H B3.2 leaves
  // node placement to the implementation). The order is:
  //
  //   1. HN-Fs, spread as far apart as the topology allows: on a mesh each
  //      next HN-F takes the free crosspoint farthest from those already
  //      placed, preferring corners, then edges; on a ring HN-F h aims at
  //      crosspoint h * numXp / numHnf; on a crossbar HN-F h aims at h % numXp.
  //   2. Each SN-F on the free port nearest the first HN-F striped to it.
  //   3. HN-Is, then each SN-I nearest the first HN-I striped to it.
  //   4. MN, RN-F, RN-D, RN-I on the least loaded crosspoint, so Requesters
  //      spread across the fabric.
  //
  // Within a crosspoint the lowest free device port is used. Ties always go to
  // the lower crosspoint index, so the result is deterministic. A node that
  // cannot be placed is left invalid and rejected by chi_cfg_check.
  function automatic chi_placement_table_t autoPlacements(
    input chi_cfg_t cfg,
    input chi_hnf_snf_table_t hnfSnfTable
  );
    chi_placement_table_t result;
    logic [CHI_MAX_DEV_PORTS-1:0] used [CHI_MAX_XP];
    int unsigned load [CHI_MAX_XP];
    int unsigned hnfXp [CHI_MAX_HNF];
    int unsigned hniXp [CHI_MAX_HNF];
    int unsigned numXp;
    int unsigned ports;
    int unsigned count;
    int unsigned ordinal;
    int unsigned bestXp;
    int unsigned bestKey;
    int unsigned key;
    int unsigned minDistance;
    int unsigned distance;
    int unsigned target;
    int unsigned port;
    int unsigned anchorXp;
    logic anchorFound;
    logic found;
    chi_node_class_e nodeClass;

    numXp = numXpOf(cfg);
    ports = cfg.numDevPortsPerXp;
    for (int unsigned xp = 0; xp < CHI_MAX_XP; xp++) begin
      used[xp] = '0;
      load[xp] = 0;
    end
    for (int unsigned n = 0; n < CHI_MAX_NODES; n++)
      result[n] = '0;
    for (int unsigned h = 0; h < CHI_MAX_HNF; h++) begin
      hnfXp[h] = 0;
      hniXp[h] = 0;
    end
    if ((numXp == 0) || (numXp > CHI_MAX_XP) || (ports == 0)
        || (ports > CHI_MAX_DEV_PORTS))
      return result;

    // Eight passes, one per class, in the order described above.
    for (int unsigned pass = 0; pass < 8; pass++) begin
      case (pass)
        0: nodeClass = NODE_HNF;
        1: nodeClass = NODE_SNF;
        2: nodeClass = NODE_HNI;
        3: nodeClass = NODE_SNI;
        4: nodeClass = NODE_MN;
        5: nodeClass = NODE_RNF;
        6: nodeClass = NODE_RND;
        default: nodeClass = NODE_RNI;
      endcase
      count = classCount(cfg, nodeClass);
      for (int unsigned index = 0; index < count; index++) begin
        ordinal = classOffset(cfg, nodeClass) + index;
        anchorFound = 1'b0;
        anchorXp = 0;
        if (nodeClass == NODE_SNF) begin
          for (int unsigned h = 0; h < cfg.numHnf; h++)
            if (!anchorFound && (h < CHI_MAX_HNF)
                && (snfIndexOfHnf(cfg, hnfSnfTable, h) == index)) begin
              anchorFound = 1'b1;
              anchorXp = hnfXp[h];
            end
        end
        if ((nodeClass == NODE_SNI) && (cfg.numSni > 0)) begin
          for (int unsigned h = 0; h < cfg.numHni; h++)
            if (!anchorFound && (h < CHI_MAX_HNF)
                && ((h % cfg.numSni) == index)) begin
              anchorFound = 1'b1;
              anchorXp = hniXp[h];
            end
        end

        found = 1'b0;
        bestXp = 0;
        bestKey = 0;
        for (int unsigned xp = 0; xp < numXp; xp++) begin
          if (load[xp] < ports) begin
            // Every class is scored so that a larger key is better; strict
            // comparison keeps the lowest index on a tie.
            if (nodeClass == NODE_HNF) begin
              case (cfg.topology)
                MESH_2D: begin
                  minDistance = 4095;
                  for (int unsigned h = 0; h < index; h++) begin
                    distance = xpDistance(cfg, hnfXp[h], xp);
                    if (distance < minDistance)
                      minDistance = distance;
                  end
                  key = (minDistance * 4) + (2 - meshXpClass(cfg, xp));
                end
                RING: begin
                  target = (index * numXp) / ((cfg.numHnf > 0) ? cfg.numHnf : 1);
                  key = numXp - xpDistance(cfg, target, xp);
                end
                default: begin
                  target = index % numXp;
                  key = numXp - ((xp + numXp - target) % numXp);
                end
              endcase
            end else if (anchorFound) begin
              key = ((numXp + 1) - xpDistance(cfg, anchorXp, xp))
                    * (ports + 1) + (ports - load[xp]);
            end else begin
              key = ports - load[xp];
            end
            if (!found || (key > bestKey)) begin
              found = 1'b1;
              bestKey = key;
              bestXp = xp;
            end
          end
        end

        if (found && (ordinal < CHI_MAX_NODES)) begin
          port = 0;
          while ((port < ports) && used[bestXp][port])
            port++;
          used[bestXp][port] = 1'b1;
          load[bestXp] = load[bestXp] + 1;
          result[ordinal].valid = 1'b1;
          result[ordinal].nodeClass = nodeClass;
          result[ordinal].nodeIndex = 8'(index);
          result[ordinal].devicePort = 8'(port);
          if (cfg.topology == MESH_2D) begin
            result[ordinal].meshX = 8'(bestXp % cfg.meshX);
            result[ordinal].meshY = 8'(bestXp / cfg.meshX);
          end else begin
            result[ordinal].meshX = 8'(bestXp);
            result[ordinal].meshY = '0;
          end
          if ((nodeClass == NODE_HNF) && (index < CHI_MAX_HNF))
            hnfXp[index] = bestXp;
          if ((nodeClass == NODE_HNI) && (index < CHI_MAX_HNF))
            hniXp[index] = bestXp;
        end
      end
    end
    return result;
  endfunction

  function automatic logic [CHI_MAX_NODEID_W-1:0] defaultNodeId(
    input chi_cfg_t cfg,
    input int unsigned ordinal
  );
    chi_mesh_placement_t placement;
    placement = defaultMeshPlacement(ordinal);
    return encodeNodeId(cfg, int'(placement.meshX), int'(placement.meshY),
                        int'(placement.devicePort), ordinal);
  endfunction

`define CHI_PACK_FIELD(fieldName, fieldWidth) \
    for (int i = 0; i < fieldWidth; i++) begin packedFlit[bitPos] = flit.fieldName[i]; bitPos++; end
`define CHI_UNPACK_FIELD(fieldName, fieldWidth) \
    for (int i = 0; i < fieldWidth; i++) begin flit.fieldName[i] = packedFlit[bitPos]; bitPos++; end
`define CHI_PACK_BIT(fieldName) \
    packedFlit[bitPos] = flit.fieldName; bitPos++;
`define CHI_UNPACK_BIT(fieldName) \
    flit.fieldName = packedFlit[bitPos]; bitPos++;

  function automatic logic [CHI_MAX_REQ_FLIT_W-1:0] packReqFlit(input chi_cfg_t cfg, input chi_req_flit_t flit);
    logic [CHI_MAX_REQ_FLIT_W-1:0] packedFlit;
    int unsigned bitPos;
    packedFlit = '0; bitPos = 0;
    `CHI_PACK_FIELD(qos, 4) `CHI_PACK_FIELD(tgtId, cfg.nodeIdW)
    `CHI_PACK_FIELD(srcId, cfg.nodeIdW) `CHI_PACK_FIELD(txnId, CHI_TXNID_FLIT_W)
    `CHI_PACK_FIELD(returnNidOrStashNidOrDataTarget, cfg.nodeIdW)
    `CHI_PACK_BIT(stashNidValidOrEndianOrDeep)
    `CHI_PACK_FIELD(returnTxnIdOrStashLpid, CHI_RTNTXNID_SLOT_W)
    `CHI_PACK_FIELD(opcode, 7) `CHI_PACK_BIT(multiReq)
    if (flit.multiReq) begin
      `CHI_PACK_FIELD(numReq, CHI_NUMREQ_SLOT_W)
    end else begin
      `CHI_PACK_FIELD(size, 3)
      bitPos += (CHI_NUMREQ_SLOT_W - 3);
    end
    `CHI_PACK_FIELD(addr, cfg.addrW)
    `CHI_PACK_FIELD(pas, CHI_PAS_W) `CHI_PACK_BIT(likelyShared)
    `CHI_PACK_BIT(allowRetry) `CHI_PACK_FIELD(order, 2) `CHI_PACK_FIELD(pCrdType, 4)
    `CHI_PACK_FIELD(memAttr, 4) `CHI_PACK_BIT(snpAttrOrDoDwt)
    `CHI_PACK_FIELD(groupIdOrLpid, CHI_GROUPID_SLOT_W) `CHI_PACK_BIT(exclOrSnoopMeOrCah)
    `CHI_PACK_BIT(expCompAck) `CHI_PACK_FIELD(tagOp, 2) `CHI_PACK_BIT(traceTag)
    if (mpamBusWidth(cfg) > 0) begin `CHI_PACK_FIELD(mpam, mpamBusWidth(cfg)) end
    if (pbhaBusWidth(cfg) > 0) begin `CHI_PACK_FIELD(pbha, CHI_PBHA_W) end
    if (reqMecStreamWidth(cfg) > 0) begin
      if (cfg.mecEn) begin `CHI_PACK_FIELD(mecId, CHI_MECID_W) end
      else begin `CHI_PACK_FIELD(streamId, CHI_STREAMID_W) end
    end
    if (secSid1Width(cfg) > 0) begin `CHI_PACK_BIT(secSid1) end
    `CHI_PACK_FIELD(rsvdc, cfg.rsvdcW)
    return packedFlit;
  endfunction

  function automatic chi_req_flit_t unpackReqFlit(input chi_cfg_t cfg, input logic [CHI_MAX_REQ_FLIT_W-1:0] packedFlit);
    chi_req_flit_t flit;
    int unsigned bitPos;
    flit = '0; bitPos = 0;
    `CHI_UNPACK_FIELD(qos, 4) `CHI_UNPACK_FIELD(tgtId, cfg.nodeIdW)
    `CHI_UNPACK_FIELD(srcId, cfg.nodeIdW) `CHI_UNPACK_FIELD(txnId, CHI_TXNID_FLIT_W)
    `CHI_UNPACK_FIELD(returnNidOrStashNidOrDataTarget, cfg.nodeIdW)
    `CHI_UNPACK_BIT(stashNidValidOrEndianOrDeep)
    `CHI_UNPACK_FIELD(returnTxnIdOrStashLpid, CHI_RTNTXNID_SLOT_W)
    `CHI_UNPACK_FIELD(opcode, 7) `CHI_UNPACK_BIT(multiReq)
    if (flit.multiReq) begin
      `CHI_UNPACK_FIELD(numReq, CHI_NUMREQ_SLOT_W)
    end else begin
      `CHI_UNPACK_FIELD(size, 3)
      bitPos += (CHI_NUMREQ_SLOT_W - 3);
    end
    `CHI_UNPACK_FIELD(addr, cfg.addrW)
    `CHI_UNPACK_FIELD(pas, CHI_PAS_W) `CHI_UNPACK_BIT(likelyShared)
    `CHI_UNPACK_BIT(allowRetry) `CHI_UNPACK_FIELD(order, 2) `CHI_UNPACK_FIELD(pCrdType, 4)
    `CHI_UNPACK_FIELD(memAttr, 4) `CHI_UNPACK_BIT(snpAttrOrDoDwt)
    `CHI_UNPACK_FIELD(groupIdOrLpid, CHI_GROUPID_SLOT_W) `CHI_UNPACK_BIT(exclOrSnoopMeOrCah)
    `CHI_UNPACK_BIT(expCompAck) `CHI_UNPACK_FIELD(tagOp, 2) `CHI_UNPACK_BIT(traceTag)
    if (mpamBusWidth(cfg) > 0) begin `CHI_UNPACK_FIELD(mpam, mpamBusWidth(cfg)) end
    if (pbhaBusWidth(cfg) > 0) begin `CHI_UNPACK_FIELD(pbha, CHI_PBHA_W) end
    if (reqMecStreamWidth(cfg) > 0) begin
      if (cfg.mecEn) begin `CHI_UNPACK_FIELD(mecId, CHI_MECID_W) end
      else begin `CHI_UNPACK_FIELD(streamId, CHI_STREAMID_W) end
    end
    if (secSid1Width(cfg) > 0) begin `CHI_UNPACK_BIT(secSid1) end
    `CHI_UNPACK_FIELD(rsvdc, cfg.rsvdcW)
    return flit;
  endfunction

  function automatic logic [CHI_MAX_RSP_FLIT_W-1:0] packRspFlit(input chi_cfg_t cfg, input chi_rsp_flit_t flit);
    logic [CHI_MAX_RSP_FLIT_W-1:0] packedFlit;
    int unsigned bitPos;
    packedFlit = '0; bitPos = 0;
    `CHI_PACK_FIELD(qos, 4) `CHI_PACK_FIELD(tgtId, cfg.nodeIdW)
    `CHI_PACK_FIELD(srcId, cfg.nodeIdW) `CHI_PACK_FIELD(txnId, CHI_TXNID_FLIT_W)
    `CHI_PACK_FIELD(opcode, 5) `CHI_PACK_FIELD(respErr, 2) `CHI_PACK_FIELD(resp, 3)
    `CHI_PACK_FIELD(fwdState, 3) `CHI_PACK_FIELD(cBusy, 3)
    `CHI_PACK_FIELD(dbIdOrGroupId, CHI_RSP_DBID_SLOT_W) `CHI_PACK_FIELD(pCrdType, 4)
    `CHI_PACK_FIELD(tagOp, 2) `CHI_PACK_BIT(traceTag)
    `CHI_PACK_FIELD(cacheLineId, CHI_CACHELINEID_W)
    return packedFlit;
  endfunction

  function automatic chi_rsp_flit_t unpackRspFlit(input chi_cfg_t cfg, input logic [CHI_MAX_RSP_FLIT_W-1:0] packedFlit);
    chi_rsp_flit_t flit;
    int unsigned bitPos;
    flit = '0; bitPos = 0;
    `CHI_UNPACK_FIELD(qos, 4) `CHI_UNPACK_FIELD(tgtId, cfg.nodeIdW)
    `CHI_UNPACK_FIELD(srcId, cfg.nodeIdW) `CHI_UNPACK_FIELD(txnId, CHI_TXNID_FLIT_W)
    `CHI_UNPACK_FIELD(opcode, 5) `CHI_UNPACK_FIELD(respErr, 2) `CHI_UNPACK_FIELD(resp, 3)
    `CHI_UNPACK_FIELD(fwdState, 3) `CHI_UNPACK_FIELD(cBusy, 3)
    `CHI_UNPACK_FIELD(dbIdOrGroupId, CHI_RSP_DBID_SLOT_W) `CHI_UNPACK_FIELD(pCrdType, 4)
    `CHI_UNPACK_FIELD(tagOp, 2) `CHI_UNPACK_BIT(traceTag)
    `CHI_UNPACK_FIELD(cacheLineId, CHI_CACHELINEID_W)
    return flit;
  endfunction

  function automatic logic [CHI_MAX_SNP_FLIT_W-1:0] packSnpFlit(input chi_cfg_t cfg, input chi_snp_flit_t flit);
    logic [CHI_MAX_SNP_FLIT_W-1:0] packedFlit;
    int unsigned bitPos;
    packedFlit = '0; bitPos = 0;
    `CHI_PACK_FIELD(qos, 4) `CHI_PACK_FIELD(srcId, cfg.nodeIdW)
    `CHI_PACK_FIELD(txnId, CHI_TXNID_FLIT_W) `CHI_PACK_FIELD(fwdNidOrPbha, cfg.nodeIdW)
    `CHI_PACK_FIELD(fwdTxnIdOrStashLpidOrVmidExt, CHI_RTNTXNID_SLOT_W) `CHI_PACK_FIELD(opcode, 5)
    `CHI_PACK_FIELD(addr, cfg.addrW-3) `CHI_PACK_FIELD(pas, CHI_PAS_W)
    `CHI_PACK_BIT(doNotGoToSd) `CHI_PACK_BIT(retToSrc) `CHI_PACK_BIT(traceTag)
    if (mpamBusWidth(cfg) > 0) begin `CHI_PACK_FIELD(mpam, mpamBusWidth(cfg)) end
    if (mecIdBusWidth(cfg) > 0) begin `CHI_PACK_FIELD(mecId, CHI_MECID_W) end
    return packedFlit;
  endfunction

  function automatic chi_snp_flit_t unpackSnpFlit(input chi_cfg_t cfg, input logic [CHI_MAX_SNP_FLIT_W-1:0] packedFlit);
    chi_snp_flit_t flit;
    int unsigned bitPos;
    flit = '0; bitPos = 0;
    `CHI_UNPACK_FIELD(qos, 4) `CHI_UNPACK_FIELD(srcId, cfg.nodeIdW)
    `CHI_UNPACK_FIELD(txnId, CHI_TXNID_FLIT_W) `CHI_UNPACK_FIELD(fwdNidOrPbha, cfg.nodeIdW)
    `CHI_UNPACK_FIELD(fwdTxnIdOrStashLpidOrVmidExt, CHI_RTNTXNID_SLOT_W) `CHI_UNPACK_FIELD(opcode, 5)
    `CHI_UNPACK_FIELD(addr, cfg.addrW-3) `CHI_UNPACK_FIELD(pas, CHI_PAS_W)
    `CHI_UNPACK_BIT(doNotGoToSd) `CHI_UNPACK_BIT(retToSrc) `CHI_UNPACK_BIT(traceTag)
    if (mpamBusWidth(cfg) > 0) begin `CHI_UNPACK_FIELD(mpam, mpamBusWidth(cfg)) end
    if (mecIdBusWidth(cfg) > 0) begin `CHI_UNPACK_FIELD(mecId, CHI_MECID_W) end
    return flit;
  endfunction

  function automatic logic [CHI_MAX_DAT_FLIT_W-1:0] packDatFlit(input chi_cfg_t cfg, input chi_dat_flit_t flit);
    logic [CHI_MAX_DAT_FLIT_W-1:0] packedFlit;
    int unsigned bitPos;
    packedFlit = '0; bitPos = 0;
    `CHI_PACK_FIELD(qos, 4) `CHI_PACK_FIELD(tgtId, cfg.nodeIdW)
    `CHI_PACK_FIELD(srcId, cfg.nodeIdW) `CHI_PACK_FIELD(txnId, CHI_TXNID_FLIT_W)
    `CHI_PACK_FIELD(homeNidOrPbha, cfg.nodeIdW) `CHI_PACK_FIELD(opcode, 4)
    `CHI_PACK_FIELD(respErr, 2) `CHI_PACK_FIELD(resp, 3)
    `CHI_PACK_FIELD(dataSourceOrFwdState, CHI_DATASOURCE_W) `CHI_PACK_BIT(dataPull)
    `CHI_PACK_FIELD(cBusy, 3)
    if (mecIdBusWidth(cfg) > 0) begin `CHI_PACK_FIELD(mecId, CHI_MECID_W) end
    `CHI_PACK_FIELD(dbId, CHI_DAT_DBID_SLOT_W)
    `CHI_PACK_FIELD(ccId, CHI_CCID_SLOT_W) `CHI_PACK_FIELD(dataId, CHI_DATAID_SLOT_W)
    `CHI_PACK_FIELD(cacheLineId, CHI_CACHELINEID_W) `CHI_PACK_FIELD(tagOp, 2)
    `CHI_PACK_FIELD(tag, cfg.dataW/32) `CHI_PACK_FIELD(tu, cfg.dataW/128)
    `CHI_PACK_BIT(traceTag) `CHI_PACK_BIT(cah)
    `CHI_PACK_FIELD(numDat, 2) `CHI_PACK_BIT(replicate)
    `CHI_PACK_FIELD(rsvdc, cfg.rsvdcW) `CHI_PACK_FIELD(be, cfg.dataW/8)
    `CHI_PACK_FIELD(data, cfg.dataW)
    if (cfg.dataCheckEn) begin `CHI_PACK_FIELD(dataCheck, cfg.dataW/8) end
    if (cfg.poisonEn) begin `CHI_PACK_FIELD(poison, cfg.dataW/64) end
    return packedFlit;
  endfunction

  function automatic chi_dat_flit_t unpackDatFlit(input chi_cfg_t cfg, input logic [CHI_MAX_DAT_FLIT_W-1:0] packedFlit);
    chi_dat_flit_t flit;
    int unsigned bitPos;
    flit = '0; bitPos = 0;
    `CHI_UNPACK_FIELD(qos, 4) `CHI_UNPACK_FIELD(tgtId, cfg.nodeIdW)
    `CHI_UNPACK_FIELD(srcId, cfg.nodeIdW) `CHI_UNPACK_FIELD(txnId, CHI_TXNID_FLIT_W)
    `CHI_UNPACK_FIELD(homeNidOrPbha, cfg.nodeIdW) `CHI_UNPACK_FIELD(opcode, 4)
    `CHI_UNPACK_FIELD(respErr, 2) `CHI_UNPACK_FIELD(resp, 3)
    `CHI_UNPACK_FIELD(dataSourceOrFwdState, CHI_DATASOURCE_W) `CHI_UNPACK_BIT(dataPull)
    `CHI_UNPACK_FIELD(cBusy, 3)
    if (mecIdBusWidth(cfg) > 0) begin `CHI_UNPACK_FIELD(mecId, CHI_MECID_W) end
    `CHI_UNPACK_FIELD(dbId, CHI_DAT_DBID_SLOT_W)
    `CHI_UNPACK_FIELD(ccId, CHI_CCID_SLOT_W) `CHI_UNPACK_FIELD(dataId, CHI_DATAID_SLOT_W)
    `CHI_UNPACK_FIELD(cacheLineId, CHI_CACHELINEID_W) `CHI_UNPACK_FIELD(tagOp, 2)
    `CHI_UNPACK_FIELD(tag, cfg.dataW/32) `CHI_UNPACK_FIELD(tu, cfg.dataW/128)
    `CHI_UNPACK_BIT(traceTag) `CHI_UNPACK_BIT(cah)
    `CHI_UNPACK_FIELD(numDat, 2) `CHI_UNPACK_BIT(replicate)
    `CHI_UNPACK_FIELD(rsvdc, cfg.rsvdcW) `CHI_UNPACK_FIELD(be, cfg.dataW/8)
    `CHI_UNPACK_FIELD(data, cfg.dataW)
    if (cfg.dataCheckEn) begin `CHI_UNPACK_FIELD(dataCheck, cfg.dataW/8) end
    if (cfg.poisonEn) begin `CHI_UNPACK_FIELD(poison, cfg.dataW/64) end
    return flit;
  endfunction

  // An LCrdReturn is identified by a zero Opcode, and every other field except
  // TxnID is unused and can carry any value (IHI 0050H B13.11). The Link layer
  // therefore has to look at the Opcode field alone, without unpacking the
  // flit, so each channel exports a mask of the bits that field occupies. The
  // mask is built by packing the field set to each of its bit positions in
  // turn, which keeps it tied to the pack function rather than to a hand
  // written offset.
  function automatic logic [CHI_MAX_REQ_FLIT_W-1:0] reqOpcodeMask(
    input chi_cfg_t cfg
  );
    chi_req_flit_t probe;
    logic [CHI_MAX_REQ_FLIT_W-1:0] mask;
    mask = '0;
    for (int unsigned b = 0; b < 7; b++) begin
      probe = '0;
      probe.opcode = chi_req_opcode_e'(7'(32'd1 << b));
      mask = mask | packReqFlit(cfg, probe);
    end
    return mask;
  endfunction

  function automatic logic [CHI_MAX_RSP_FLIT_W-1:0] rspOpcodeMask(
    input chi_cfg_t cfg
  );
    chi_rsp_flit_t probe;
    logic [CHI_MAX_RSP_FLIT_W-1:0] mask;
    mask = '0;
    for (int unsigned b = 0; b < 5; b++) begin
      probe = '0;
      probe.opcode = chi_rsp_opcode_e'(5'(32'd1 << b));
      mask = mask | packRspFlit(cfg, probe);
    end
    return mask;
  endfunction

  function automatic logic [CHI_MAX_SNP_FLIT_W-1:0] snpOpcodeMask(
    input chi_cfg_t cfg
  );
    chi_snp_flit_t probe;
    logic [CHI_MAX_SNP_FLIT_W-1:0] mask;
    mask = '0;
    for (int unsigned b = 0; b < 5; b++) begin
      probe = '0;
      probe.opcode = chi_snp_opcode_e'(5'(32'd1 << b));
      mask = mask | packSnpFlit(cfg, probe);
    end
    return mask;
  endfunction

  function automatic logic [CHI_MAX_DAT_FLIT_W-1:0] datOpcodeMask(
    input chi_cfg_t cfg
  );
    chi_dat_flit_t probe;
    logic [CHI_MAX_DAT_FLIT_W-1:0] mask;
    mask = '0;
    for (int unsigned b = 0; b < 4; b++) begin
      probe = '0;
      probe.opcode = chi_dat_opcode_e'(4'(32'd1 << b));
      mask = mask | packDatFlit(cfg, probe);
    end
    return mask;
  endfunction

`undef CHI_PACK_FIELD
`undef CHI_UNPACK_FIELD
`undef CHI_PACK_BIT
`undef CHI_UNPACK_BIT
endpackage
