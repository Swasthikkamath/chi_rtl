// Non-coherent Home Node (HN-I).
//
// The HN-I is the Home for the address ranges its SAM maps to SN-Is, and it
// hosts the CHI MMIO configuration window. It keeps no coherence state, but it
// is an ordering point: it accepts up to hniEntries transactions, gives each
// its own entry, request and response buffers, TxnID towards the SN-I and
// DBID towards the Requester, and runs them concurrently under two rules.
//
//   Same line. One transaction per 64-byte location {line, PAS} runs at a
//   time, in arrival order, so every observer sees one order per line
//   (IHI 0050H B4.11) and Request Order holds trivially.
//
//   Endpoint Order. A request with Order = Endpoint goes to its SN-I only
//   once every older ordered request from the same source has been accepted
//   downstream: a ReadReceipt, a DBIDResp, data or a completion, never a
//   RetryAck. The downstream request carries the same Order value, which HN-I
//   to SN-I permits (IHI 0050H B2.7.5, Table B2.9), so the Subordinate keeps
//   the order from there.
//
// Towards the Requester, a ReadReceipt for an ordered read and the DBIDResp
// of a write go out as soon as the request has an entry, because the HN-I is
// the ordering point and the entry owns a buffer (IHI 0050H B2.7.5.1).
// CompData comes from the buffer once the Subordinate's data is complete.
// Comp follows the Subordinate's Comp unless the write permits Early Write
// Acknowledge. A write with ExpCompAck (Ordered Write Observation) is not
// sent downstream, so not made visible, before its CompAck has arrived
// (IHI 0050H B2.7.5.3). Atomics are forwarded to the Subordinate. A Combined
// write is the write followed by its CMO, which is forwarded only when it
// must reach a point behind the HN-I (persist and Storage); the HN-I holds no
// data, so the other CMOs complete here. Requests the HN-I cannot serve —
// coherent allocating reads, CopyBacks, CleanUnique, MakeUnique, a DVMOp,
// ReadNoSnpSep from a Requester (IHI 0050H B1.6) — and addresses no SN-I
// serves complete with NDERR, after any data the Requester owes
// (IHI 0050H B9.1.1). Exclusives use the HN-I's own System monitor
// (B6.2.4, chi_excl_mon): ReadNoSnp(Excl) registers, WriteNoSnp(Excl) is
// checked and writes nothing when it fails, and a write by another LP resets
// the monitors of its location; Excl is not sent on to the SN-I.
//
// Every RSP and DAT input is accepted unconditionally into storage reserved
// before the message was invited, and a request that finds no entry is
// answered with RetryAck, so the HN-I never makes one channel wait for
// another (design specification, Section 9.7).
module chi_hni_top #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] HN_NODE_ID = '0,
  parameter int unsigned NUM_REGIONS = 4,
  parameter logic [CFG.addrW-1:0] CFG_MMIO_BASE = {CFG.addrW{1'b1}} - 12'hfff,
  parameter logic [CFG.addrW-1:0]
    REGION_BASE [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [CFG.addrW-1:0]
    REGION_LIMIT [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0]
    REGION_TARGET [NUM_REGIONS-1:0] = '{default:'0},
  parameter logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0]
    REGION_ATTRIBUTES [NUM_REGIONS-1:0] = '{default:'0},
  // The SN-Is a region may name; a decode to any other node is an error.
  parameter int unsigned NUM_SNI = 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    SNI_NODE_IDS [NUM_SNI] = '{default:'0},
  // Every Requester that may send to this Home, for Request Retry and the
  // exclusive monitor, with its exclusive-capable LPs and their sum.
  parameter int unsigned NUM_REQUESTERS = 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    REQUESTER_NODE_IDS [NUM_REQUESTERS] = '{default:'0},
  parameter int unsigned RN_NUM_LP [NUM_REQUESTERS] = '{default:1},
  parameter int unsigned NUM_LP = NUM_REQUESTERS
) (
  input  logic clk,
  input  logic resetn,
  input  logic reqInValid,
  output logic reqInReady,
  input  chi_pkg::chi_noc_flit_t reqInFlit,
  input  logic rspInValid,
  output logic rspInReady,
  input  chi_pkg::chi_noc_flit_t rspInFlit,
  input  logic datInValid,
  output logic datInReady,
  input  chi_pkg::chi_noc_flit_t datInFlit,
  output logic reqOutValid,
  input  logic reqOutReady,
  output chi_pkg::chi_noc_flit_t reqOutFlit,
  output logic rspOutValid,
  input  logic rspOutReady,
  output chi_pkg::chi_noc_flit_t rspOutFlit,
  output logic datOutValid,
  input  logic datOutReady,
  output chi_pkg::chi_noc_flit_t datOutFlit,
  input  logic regionUpdate,
  input  logic [chi_pkg::clog2Min1(NUM_REGIONS)-1:0] regionUpdateIndex,
  input  logic [CFG.addrW-1:0] regionUpdateBase,
  input  logic [CFG.addrW-1:0] regionUpdateLimit,
  input  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] regionUpdateTarget,
  input  logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] regionUpdateAttributes,
  // Every other Home is idle: a CHI MMIO commit needs a quiescent fabric.
  input  logic othersQuiescent,
  output logic mmioRegionUpdate,
  output logic [chi_pkg::clog2Min1(NUM_REGIONS)-1:0] mmioRegionUpdateIndex,
  output logic [CFG.addrW-1:0] mmioRegionUpdateBase,
  output logic [CFG.addrW-1:0] mmioRegionUpdateLimit,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] mmioRegionUpdateTarget,
  output logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] mmioRegionUpdateAttributes,
  output logic idle,
  // Granule Protection Check (chi_gpc), before anything is sent downstream.
  output logic gpcCheckValid,
  output logic [chi_pkg::CHI_MAX_ADDR_W-1:0] gpcCheckAddr,
  output chi_pkg::chi_pas_e gpcCheckPas,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] gpcCheckSrcId,
  input  logic gpcCheckDone,
  input  logic gpcCheckFail
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chi_hnf_pkg::*;

  localparam int unsigned DEPTH = (CFG.hniEntries > 0) ? CFG.hniEntries : 1;
  localparam int unsigned IDX_W = clog2Min1(DEPTH);
  localparam int unsigned SUB_W = clog2Min1(NUM_SNI);
  localparam int unsigned REG_W = clog2Min1(NUM_REGIONS);
  localparam int unsigned LINE_W = CFG.addrW - 6;
  localparam int unsigned KEY_W = LINE_W + CHI_PAS_W;
  localparam int unsigned DAT_BYTES = CFG.dataW / 8;
  localparam int unsigned STEP = datIdStep(CFG);
  localparam int unsigned POISON_PER_BEAT = CFG.dataW / 64;
  localparam int unsigned RESERVE_W = 16;
  localparam int unsigned RETRY_RECORDS =
    (CFG.retryRecords > 0) ? CFG.retryRecords : 1;
  localparam logic [63:0] ALL_BYTES = '1;

  generate
    begin : chi_cfg_check
      initial begin
        if (NUM_SNI == 0)
          $fatal(1, "chi_hni_top NUM_SNI must be at least 1: an HN-I forwards to SN-Is");
        if (NUM_REQUESTERS == 0)
          $fatal(1, "chi_hni_top NUM_REQUESTERS must be at least 1: Request Retry has to know whom it owes a P-Credit");
        // The entry index is the TxnID towards the SN-I and the DBID towards
        // the Requester.
        if (DEPTH > (1 << CFG.txnIdW))
          $fatal(1, "hniEntries (%0d) does not fit the %0d-bit TxnID the HN-I uses towards SN-Is and as DBID",
                 CFG.hniEntries, CFG.txnIdW);
      end
    end
  endgenerate

  typedef enum logic [3:0] {
    HNI_K_READ       = 4'd0,  // ReadNoSnp or ReadOnce*, read with ReadNoSnp
    HNI_K_WRITE      = 4'd1,  // an Immediate or Combined write, forwarded
    HNI_K_WRITE_ZERO = 4'd2,  // WriteNoSnpZero or WriteUniqueZero
    HNI_K_CMO        = 4'd3,  // cache maintenance
    HNI_K_ATOMIC     = 4'd4,  // forwarded to the SN-I
    HNI_K_DATALESS   = 4'd5,  // Evict, StashOnce* and refused dataless requests
    HNI_K_COPYBACK   = 4'd6,  // refused: NDERR, the data is discarded
    HNI_K_DVM        = 4'd7,  // refused: NDERR after the DVM payload
    HNI_K_CFG_READ   = 4'd8,  // CHI MMIO configuration read
    HNI_K_CFG_WRITE  = 4'd9   // CHI MMIO configuration write
  } hni_kind_e;

  // One transaction. Whether the entry is in use, its location, Requester and
  // age live in chi_pos; this is what the transaction still owes and is
  // owed.
  typedef struct packed {
    chi_req_flit_t      req;          // the request as received
    hni_kind_e          kind;
    chi_hnf_cmo_e       cmo;          // the CMO of a CMO or Combined write
    logic               err;          // completes with NDERR
    logic [SUB_W-1:0]   sub;          // its SN-I, an index into SNI_NODE_IDS
    logic               ordered;      // Order is Request or Endpoint
    // Responses owed to the Requester.
    logic               receiptOwed;  // ReadReceipt
    logic               dbidOwed;     // DBIDResp, or CompDBIDResp if dbidWithComp
    logic               dbidWithComp;
    logic               compOwed;     // Comp, CompData or CompStashDone
    logic [3:0]         compGranSent;
    logic               compCmoOwed;  // CompCMO of a Combined write
    logic               compAckOwed;  // CompAck from the Requester
    // Requester data.
    logic               wrOwed;
    logic [3:0]         wrGranules;
    logic               wrCancel;     // WriteDataCancel
    // Downstream.
    logic               dnBusy;       // an operation is with the SN tracker
    chi_hnf_dn_e        dnKind;
    logic               dnMainDone;   // read, write or atomic done (or skipped)
    logic               dnCmoDone;    // forwarded CMO done
    logic               dnAccepted;   // the SN-I has accepted the first request
    logic               gpcPending;   // granule protection not yet answered
    // Exclusive result, decided when the entry starts.
    logic               exclLoad;     // a ReadNoSnp(Excl) the monitor registered
    logic               exclStore;    // a WriteNoSnp(Excl)
    logic               exclPass;     // which passed
    chi_resp_e          dnResp;       // Resp of the SN-I's CompData or Comp
    chi_resp_err_e      dnErr;        // RespErr the SN-I reported
  } hni_entry_t;

  // ---------------------------------------------------------------------
  // Inputs and address decode.
  // ---------------------------------------------------------------------
  chi_req_flit_t incomingReq;
  chi_rsp_flit_t incomingRsp;
  chi_dat_flit_t incomingDat;
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] samTarget;
  logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] samMatched;
  logic samError;
  logic samPasError;
  logic configPasOk;
  logic configAccess;
  logic sniKnown;
  logic [SUB_W-1:0] sniIndex;
  logic dropRequest;

  // The HN-I decode never hashes, but the SAM still takes a hash table. It is
  // passed as a typed one-entry array: an assignment pattern written against
  // the parameter would be sized by the SAM's default NUM_HNF before the
  // override applies, which some tools reject.
  localparam logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    HNI_HASH_NODE_IDS [0:0] = '{HN_NODE_ID};

  chi_sam #(
    .CFG(CFG), .NUM_REGIONS(NUM_REGIONS), .HASH_TO_HNF(1'b0),
    .NUM_HNF(1), .HN_NODE_IDS(HNI_HASH_NODE_IDS),
    .REGION_BASE(REGION_BASE), .REGION_LIMIT(REGION_LIMIT),
    .REGION_TARGET(REGION_TARGET), .REGION_ATTRIBUTES(REGION_ATTRIBUTES)
  ) hni_sam (
    .clk, .resetn, .address(incomingReq.addr[CFG.addrW-1:0]),
    .pas(incomingReq.pas), .targetNodeId(samTarget),
    .matchedAttributes(samMatched), .unmappedError(samError),
    .pasError(samPasError),
    .regionUpdate, .regionUpdateIndex, .regionUpdateBase,
    .regionUpdateLimit, .regionUpdateTarget, .regionUpdateAttributes
  );

  always_comb begin
    incomingReq = unpackReqFlit(CFG, reqInFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
    incomingRsp = unpackRspFlit(CFG, rspInFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    incomingDat = unpackDatFlit(CFG, datInFlit.payload[CHI_MAX_DAT_FLIT_W-1:0]);
    configAccess = (CFG.cfgAccess == CFG_CHI_MMIO)
                   && ((incomingReq.addr[CFG.addrW-1:0]
                        & ~CFG.addrW'(12'hfff))
                       == CFG_MMIO_BASE);
    // The configuration window answers only the Root PAS with RME and only
    // the Secure PAS without it.
    configPasOk = incomingReq.pas == (CFG.rmeEn ? PAS_ROOT : PAS_SECURE);
    // PCrdReturn carries no transaction and PrefetchTgt has no response, so
    // both are accepted and discarded (IHI 0050H B2.5.6, B4.2.6.2).
    dropRequest = (incomingReq.opcode == REQ_PCRD_RETURN)
                  || (incomingReq.opcode == REQ_PREFETCH_TGT);
    sniKnown = 1'b0;
    sniIndex = '0;
    for (int unsigned s = 0; s < NUM_SNI; s++)
      if (samTarget == CHI_NODEID_SLOT_W'(SNI_NODE_IDS[s])) begin
        sniKnown = 1'b1;
        sniIndex = SUB_W'(s);
      end
  end

  // ---------------------------------------------------------------------
  // State.
  // ---------------------------------------------------------------------
  hni_entry_t entry [DEPTH];
  logic [511:0] bufReq [DEPTH];       // Requester data
  logic [63:0] bufReqBe [DEPTH];
  logic [7:0] bufReqPoison [DEPTH];
  logic [DEPTH-1:0] bufReqErr;
  logic [511:0] bufRsp [DEPTH];       // Subordinate data
  logic [7:0] bufRspPoison [DEPTH];

  logic [REG_W-1:0] selectedRegion;
  logic [CFG.addrW-1:0] stagedBase [NUM_REGIONS-1:0];
  logic [CFG.addrW-1:0] stagedLimit [NUM_REGIONS-1:0];
  logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] stagedTarget [NUM_REGIONS-1:0];
  logic [CHI_SAM_ATTR_W-1:0] stagedAttributes [NUM_REGIONS-1:0];

  // chi_pos.
  logic posAllocValid;
  logic posAllocReady;
  logic [IDX_W-1:0] posAllocIndex;
  logic [DEPTH-1:0] posStartMask;
  logic [DEPTH-1:0] posFreeMask;
  logic [DEPTH-1:0] posActive;
  logic [DEPTH-1:0] posStarted;
  logic [IDX_W:0] posFreeCount;
  logic [IDX_W:0] posUnreservedCount;
  logic [DEPTH-1:0][KEY_W-1:0] posKey;
  logic [DEPTH-1:0][CHI_NODEID_SLOT_W-1:0] posRequester;
  logic [DEPTH-1:0][CHI_TXNID_FLIT_W-1:0] posTxnId;
  chi_req_opcode_e [DEPTH-1:0] posOpcode;
  chi_order_e [DEPTH-1:0] posOrder;
  logic [DEPTH-1:0][DEPTH-1:0] posOlder;

  // Admission and Request Retry.
  logic resourcesAvailable;
  logic requestHandshake;
  logic retryAck;
  logic [3:0] retryClass;
  logic [1:0] retryCategory;
  logic retryAckWant;
  logic retryHandshake;
  logic retryGrantAllowed;
  logic retryGrantValid;
  logic retryGrantReady;
  logic [CHI_NODEID_SLOT_W-1:0] retryGrantTgtId;
  logic [3:0] retryGrantClass;
  logic [RESERVE_W-1:0] retryCreditsOutstanding;
  logic retryGrantsOwed;
  hni_entry_t allocEntry;
  hni_entry_t allocEntryChecked;
  logic [DEPTH-1:0] eExclNeeds;
  logic exclCommitValid;
  logic [IDX_W-1:0] exclCommitEntry;
  logic exclCommitLoad;
  logic exclCommitStore;
  logic exclCommitUpdate;
  logic exclRegisterBlocked;
  logic exclPass;
  logic exclRegistered;
  logic exclLpKnown;
  logic [clog2Min1(NUM_LP)-1:0] exclLpIndex;
  logic gpcAllocCheck;
  logic gpcRecheckValid;
  logic [IDX_W-1:0] gpcRecheckEntry;
  logic [IDX_W-1:0] gpcRecheckPointer;

  // Per-entry conditions.
  logic [DEPTH-1:0] eMayStart;
  logic [DEPTH-1:0] eNoDownstream;
  logic [DEPTH-1:0] eEndpointClear;
  logic [DEPTH-1:0] eMainNeeded;
  logic [DEPTH-1:0] eCmoNeeded;
  logic [DEPTH-1:0] eSkipWrite;
  logic [DEPTH-1:0] eDbidReady;
  logic [DEPTH-1:0] eCompReady;
  logic [DEPTH-1:0] eCompIsData;
  logic [DEPTH-1:0] eCompCmoReady;
  logic [DEPTH-1:0] eCfgApply;
  logic [DEPTH-1:0] eAllDone;
  logic [DEPTH-1:0][3:0] eCompGranules;

  // Downstream.
  logic [DEPTH-1:0] dnStartValid;
  chi_hnf_dn_e [DEPTH-1:0] dnStartKind;
  logic [DEPTH-1:0][SUB_W-1:0] dnStartSub;
  logic [DEPTH-1:0][3:0] dnStartGranules;
  logic [DEPTH-1:0][3:0] dnStartReadGranules;
  logic [DEPTH-1:0] dnStartWantReceipt;
  logic [DEPTH-1:0] dnBusy;
  logic [DEPTH-1:0] dnWaiting;
  logic [DEPTH-1:0] dnDone;
  logic [DEPTH-1:0] dnResend;
  logic [DEPTH-1:0][3:0] dnResendType;
  logic dnReqValid;
  logic [IDX_W-1:0] dnReqOwner;
  logic dnReqCreditReturn;
  logic [3:0] dnReqCreditType;
  logic [SUB_W-1:0] dnReqCreditSub;
  logic dnDatValid;
  logic [IDX_W-1:0] dnDatOwner;
  logic [1:0] dnDatDataId;
  logic [CHI_RSP_DBID_SLOT_W-1:0] dnDatTxnId;
  chi_noc_flit_t dnReqFlit;
  chi_noc_flit_t dnDatFlit;

  // Input classification.
  logic snRspValid;
  logic snRspForEntry;
  logic [IDX_W-1:0] snRspEntry;
  logic snDatValid;
  logic snDatForEntry;
  logic [IDX_W-1:0] snDatEntry;
  logic wrDatValid;
  logic [IDX_W-1:0] wrDatEntry;
  logic [3:0] wrDatGranules;
  logic compAckValid;
  logic [IDX_W-1:0] compAckEntry;

  // Output stages and arbitration.
  logic reqFifoReady;
  logic rspFifoReady;
  logic datFifoReady;
  logic rspPushValid;
  chi_noc_flit_t rspPushFlit;
  logic datPushValid;
  chi_noc_flit_t datPushFlit;
  logic [1:0] reqFifoCount;
  logic [1:0] rspFifoCount;
  logic [1:0] datFifoCount;
  logic [DEPTH-1:0] rspWant;
  logic rspEntryValid;
  logic [IDX_W-1:0] rspEntry;
  logic [IDX_W-1:0] rspPointer;
  logic rspGrantSend;
  logic rspEntrySend;
  logic [DEPTH-1:0] datWant;
  logic datEntryValid;
  logic [IDX_W-1:0] datEntry;
  logic [IDX_W-1:0] datPointer;
  logic [1:0] datEntryDataId;
  logic datTrackerTurn;
  logic datTrackerWins;
  logic datTrackerSend;
  logic datEntrySend;
  logic cfgApplyValid;
  logic [IDX_W-1:0] cfgApplyEntry;
  logic cfgCommitAllowed;

  // The configuration register an access names, as a 64-bit little-endian
  // value at its own offset (IHI 0050H B2.9.4: bytes travel at their natural
  // positions).
  function automatic logic [63:0] configValue(input logic [7:0] offset);
    logic [63:0] value;
    value = '0;
    case (offset & 8'hf8)
      8'h08: value[CFG.addrW-1:0] = stagedBase[selectedRegion];
      8'h10: value[CFG.addrW-1:0] = stagedLimit[selectedRegion];
      8'h18: value[CHI_NODEID_SLOT_W-1:0] = stagedTarget[selectedRegion];
      8'h20: value[CHI_SAM_ATTR_W-1:0] = stagedAttributes[selectedRegion];
      default: value[REG_W-1:0] = selectedRegion;
    endcase
    return value;
  endfunction

  function automatic logic [3:0] requestGranules(input chi_req_flit_t req);
    return messageGranules(CFG, req.addr, req.size);
  endfunction

  // ---------------------------------------------------------------------
  // Transaction table.
  // ---------------------------------------------------------------------
  chi_pos #(
    .CFG(CFG), .DEPTH(DEPTH), .KEY_W(KEY_W), .RESERVE_W(RESERVE_W)
  ) pos (
    .clk, .resetn,
    .allocValid(posAllocValid), .allocCredited(!incomingReq.allowRetry),
    .reserved(retryCreditsOutstanding),
    .allocReady(posAllocReady), .allocIndex(posAllocIndex),
    .allocKey({incomingReq.pas, incomingReq.addr[CFG.addrW-1:6]}),
    .allocRequester(incomingReq.srcId), .allocTxnId(incomingReq.txnId),
    .allocOpcode(incomingReq.opcode), .allocOrder(incomingReq.order),
    .startMask(posStartMask), .freeMask(posFreeMask),
    .active(posActive), .started(posStarted), .freeCount(posFreeCount),
    .unreservedCount(posUnreservedCount), .key(posKey),
    .requester(posRequester), .txnId(posTxnId),
    .opcode(posOpcode), .order(posOrder), .older(posOlder)
  );

  // ---------------------------------------------------------------------
  // Admission: a request is allocated, dropped, or given RetryAck.
  // ---------------------------------------------------------------------
  always_comb begin
    resourcesAvailable = dropRequest || posAllocReady;
    if (isAtomicOpcode(incomingReq.opcode))
      retryCategory = 2'd3;
    else if (hnfKind(incomingReq.opcode) inside {
               HNF_KIND_WRITE, HNF_KIND_WRITE_ZERO, HNF_KIND_WRITE_DEF})
      retryCategory = 2'd1;
    else
      retryCategory = 2'd2;
    retryAckWant = reqInValid && !resourcesAvailable && retryAck;
    retryHandshake = retryAckWant && rspFifoReady;
    requestHandshake = reqInValid && resourcesAvailable;
    posAllocValid = requestHandshake && !dropRequest;
  end

  always_comb begin
    reqInReady = resourcesAvailable || retryHandshake;
  end

  // A grant reserves an entry for the request it invites (see chi_retry).
  always_comb begin
    retryGrantAllowed =
      (int'(posUnreservedCount)
       > ((posAllocValid && incomingReq.allowRetry) ? 1 : 0))
      && (int'(retryCreditsOutstanding) < RETRY_RECORDS);
  end

  chi_retry #(
    .NODEID_W(CHI_NODEID_SLOT_W), .NUM_REQUESTERS(NUM_REQUESTERS),
    .REQUESTER_NODE_IDS(REQUESTER_NODE_IDS),
    .CREDIT_TYPES(CHI_CREDIT_TYPES), .OUTSTANDING_W(RESERVE_W)
  ) retry (
    .clk, .resetn, .requestValid(reqInValid),
    .resourcesAvailable, .allowRetry(incomingReq.allowRetry),
    .requestCategory(retryCategory), .requestSrcId(incomingReq.srcId),
    .requestQos(incomingReq.qos),
    .sendRetryAck(retryAck), .retryAckSent(retryHandshake),
    .retryClass,
    .creditUseValid(posAllocValid && !incomingReq.allowRetry),
    .creditReturnValid(requestHandshake
                       && (incomingReq.opcode == REQ_PCRD_RETURN)),
    .grantAllowed(retryGrantAllowed),
    .grantValid(retryGrantValid), .grantReady(retryGrantReady),
    .grantTgtId(retryGrantTgtId), .grantClass(retryGrantClass),
    .creditsOutstanding(retryCreditsOutstanding),
    .grantsOwed(retryGrantsOwed)
  );

  // The entry a request starts as.
  always_comb begin
    chi_hnf_kind_e base;
    hni_kind_e kind;
    logic err;
    base = hnfKind(incomingReq.opcode);
    err = 1'b0;
    if (incomingReq.opcode == REQ_DVM_OP) begin
      // DVM belongs to the MN.
      kind = HNI_K_DVM;
      err = 1'b1;
    end else if (incomingReq.opcode == REQ_READ_NO_SNP_SEP) begin
      // ReadNoSnpSep is sent only from a Home to a Subordinate (B1.6).
      kind = HNI_K_READ;
      err = 1'b1;
    end else begin
      case (base)
        HNF_KIND_READ_ONCE, HNF_KIND_READ_NOSNP:
          kind = configAccess ? HNI_K_CFG_READ : HNI_K_READ;
        HNF_KIND_READ: begin
          // An allocating read needs coherent memory.
          kind = HNI_K_READ;
          err = 1'b1;
        end
        HNF_KIND_WRITE: begin
          kind = HNI_K_WRITE;
          if (configAccess && (hnfCmo(incomingReq.opcode) == HNF_CMO_NONE)
              && !isStashWrite(incomingReq.opcode))
            kind = HNI_K_CFG_WRITE;
        end
        HNF_KIND_WRITE_DEF:
          kind = HNI_K_WRITE;
        HNF_KIND_WRITE_ZERO:
          kind = HNI_K_WRITE_ZERO;
        HNF_KIND_CMO:
          kind = HNI_K_CMO;
        HNF_KIND_ATOMIC:
          kind = HNI_K_ATOMIC;
        HNF_KIND_STASH_ONCE:
          kind = HNI_K_DATALESS;
        HNF_KIND_DATALESS: begin
          kind = HNI_K_DATALESS;
          err = incomingReq.opcode != REQ_EVICT;
        end
        HNF_KIND_COPYBACK: begin
          kind = HNI_K_COPYBACK;
          err = 1'b1;
        end
        default: begin
          kind = HNI_K_DATALESS;
          err = 1'b1;
        end
      endcase
    end
    // Inside the configuration window only Root (or Secure) register
    // accesses are served; elsewhere the address must decode to an SN-I and
    // the PAS must be one the region and the configuration allow. A request
    // the Requester-side SAM refused carries that refusal here
    // (IHI 0050H B9.1.1).
    if (configAccess) begin
      if (!(kind inside {HNI_K_CFG_READ, HNI_K_CFG_WRITE}) || !configPasOk)
        err = 1'b1;
    end else if (samError || samPasError || !sniKnown) begin
      err = 1'b1;
    end
    if ((reqInFlit.decodeErr != NOC_ERR_NONE)
        || !pasLegal(CFG, incomingReq.pas))
      err = 1'b1;

    allocEntry = '0;
    allocEntry.req = incomingReq;
    allocEntry.kind = kind;
    allocEntry.cmo = hnfCmo(incomingReq.opcode);
    allocEntry.err = err;
    allocEntry.sub = sniIndex;
    allocEntry.ordered = (incomingReq.order == ORDER_REQUEST_ORDER)
                         || (incomingReq.order == ORDER_ENDPOINT);
    allocEntry.dnKind = HNF_DN_READ;
    allocEntry.dnResp = RESP_I;
    allocEntry.dnErr = RESP_ERR_OK;
    allocEntry.receiptOwed = (kind inside {HNI_K_READ, HNI_K_CFG_READ})
                             && allocEntry.ordered;
    allocEntry.dbidOwed = kind inside {HNI_K_WRITE, HNI_K_WRITE_ZERO,
                                       HNI_K_ATOMIC, HNI_K_DVM,
                                       HNI_K_COPYBACK, HNI_K_CFG_WRITE};
    allocEntry.dbidWithComp = kind inside {HNI_K_WRITE_ZERO, HNI_K_COPYBACK};
    allocEntry.compOwed = kind != HNI_K_COPYBACK;
    allocEntry.compCmoOwed = (kind == HNI_K_WRITE)
                             && (allocEntry.cmo != HNF_CMO_NONE);
    allocEntry.compAckOwed = incomingReq.expCompAck
                             && !(kind inside {HNI_K_COPYBACK, HNI_K_DVM});
    allocEntry.wrOwed = kind inside {HNI_K_WRITE, HNI_K_ATOMIC, HNI_K_DVM,
                                     HNI_K_COPYBACK, HNI_K_CFG_WRITE};
  end

  // Granule protection: the request being allocated is checked when it has
  // no other error, otherwise one waiting entry is checked again. A failed
  // check completes with NDERR and sends nothing downstream
  // (IHI 0050H B9.1.1).
  always_comb begin
    logic found;
    int unsigned candidate;
    gpcAllocCheck = (CFG.gpcMode != GPC_NONE) && posAllocValid && !allocEntry.err;
    found = 1'b0;
    gpcRecheckEntry = '0;
    candidate = 0;
    if ((CFG.gpcMode != GPC_NONE) && !gpcAllocCheck)
      for (int unsigned offset = 0; offset < DEPTH; offset++) begin
        candidate = int'(gpcRecheckPointer) + offset;
        if (candidate >= DEPTH)
          candidate = candidate - DEPTH;
        if (!found && posActive[candidate] && entry[candidate].gpcPending) begin
          found = 1'b1;
          gpcRecheckEntry = IDX_W'(candidate);
        end
      end
    gpcRecheckValid = found;
    gpcCheckValid = gpcAllocCheck || gpcRecheckValid;
    gpcCheckAddr = gpcAllocCheck ? incomingReq.addr : entry[gpcRecheckEntry].req.addr;
    gpcCheckPas = gpcAllocCheck ? incomingReq.pas : entry[gpcRecheckEntry].req.pas;
    gpcCheckSrcId = gpcAllocCheck ? incomingReq.srcId
                                  : entry[gpcRecheckEntry].req.srcId;
    allocEntryChecked = allocEntry;
    if (gpcAllocCheck) begin
      if (!gpcCheckDone)
        allocEntryChecked.gpcPending = 1'b1;
      else if (gpcCheckFail)
        allocEntryChecked.err = 1'b1;
    end
  end

  // ---------------------------------------------------------------------
  // Per-entry conditions.
  // ---------------------------------------------------------------------
  always_comb begin
    for (int unsigned i = 0; i < DEPTH; i++) begin
      hni_entry_t e;
      logic olderSameLine;
      logic olderOrderedPending;
      logic ewa;
      e = entry[i];
      ewa = e.req.memAttr[0];

      // Same line: wait for every older entry for the location.
      olderSameLine = 1'b0;
      olderOrderedPending = 1'b0;
      // CleanInvalidPoPA and its Combined forms are ordered against their
      // line in every PAS (IHI 0050H B4.2.2.1).
      for (int unsigned j = 0; j < DEPTH; j++)
        if ((j != i) && posActive[j] && posOlder[i][j]) begin
          if ((posKey[j] == posKey[i])
              || (((entry[i].cmo == HNF_CMO_POPA)
                   || (entry[j].cmo == HNF_CMO_POPA))
                  && (posKey[j][LINE_W-1:0] == posKey[i][LINE_W-1:0])))
            olderSameLine = 1'b1;
          if (entry[j].ordered && !entry[j].dnAccepted
              && (posRequester[j] == posRequester[i]))
            olderOrderedPending = 1'b1;
        end
      eMayStart[i] = posActive[i] && !posStarted[i] && !olderSameLine
                     && !e.gpcPending;
      eEndpointClear[i] = (e.req.order != ORDER_ENDPOINT) || !olderOrderedPending;

      // The monitor sees Exclusive accesses and every write (B6.2.4).
      eExclNeeds[i] = CFG.exclEn && !e.err
                      && ((e.req.exclOrSnoopMeOrCah
                           && (e.req.opcode inside {REQ_READ_NO_SNP,
                                                    REQ_WRITE_NO_SNP_FULL,
                                                    REQ_WRITE_NO_SNP_PTL}))
                          || (e.kind inside {HNI_K_WRITE, HNI_K_WRITE_ZERO,
                                             HNI_K_ATOMIC}));

      // What still has to go downstream. A failing exclusive write sends
      // nothing (IHI 0050H B6.2.4, Table B6.2).
      eNoDownstream[i] = e.err
                         || !(e.kind inside {HNI_K_READ, HNI_K_WRITE,
                                             HNI_K_WRITE_ZERO, HNI_K_ATOMIC})
                         || ((e.kind == HNI_K_WRITE)
                             && (e.wrCancel || (e.exclStore && !e.exclPass)));
      eMainNeeded[i] = posStarted[i] && !e.err && !e.dnMainDone
                       && (e.kind inside {HNI_K_READ, HNI_K_WRITE,
                                          HNI_K_WRITE_ZERO, HNI_K_ATOMIC});
      eCmoNeeded[i] = posStarted[i] && !e.err && !e.dnCmoDone
                      && ((e.kind == HNI_K_CMO)
                          || ((e.kind == HNI_K_WRITE)
                              && (e.cmo != HNF_CMO_NONE)))
                      && cmoForwarded(e.cmo);
      // A cancelled write sends nothing (IHI 0050H B2.3.2.1); a Combined
      // write still performs its CMO.
      eSkipWrite[i] = eMainNeeded[i] && (e.kind == HNI_K_WRITE)
                      && !e.wrOwed && (e.wrCancel || (e.exclStore && !e.exclPass));

      // Configuration writes take effect in arrival order per line, once
      // their data is complete.
      eCfgApply[i] = posStarted[i] && (e.kind == HNI_K_CFG_WRITE) && !e.err
                     && !e.wrOwed && !e.dnMainDone;

      eDbidReady[i] = posActive[i] && e.dbidOwed;
      if (e.dbidWithComp && (e.kind == HNI_K_WRITE_ZERO))
        eDbidReady[i] = eDbidReady[i] && posStarted[i]
                        && (e.err || ewa || e.dnMainDone);

      eCompIsData[i] = (e.kind inside {HNI_K_READ, HNI_K_CFG_READ})
                       || ((e.kind == HNI_K_ATOMIC)
                           && !isAtomicStore(e.req.opcode));
      eCompGranules[i] = (e.kind == HNI_K_ATOMIC)
                         ? messageGranules(CFG, e.req.addr,
                                           (e.req.opcode == REQ_ATOMIC_COMPARE)
                                           ? (e.req.size - 3'd1) : e.req.size)
                         : requestGranules(e.req);
      eCompReady[i] = 1'b0;
      if (posStarted[i] && e.compOwed && !e.dbidOwed && !e.receiptOwed) begin
        case (e.kind)
          HNI_K_READ:
            eCompReady[i] = e.err || e.dnMainDone;
          HNI_K_CFG_READ, HNI_K_DATALESS:
            eCompReady[i] = 1'b1;
          HNI_K_WRITE:
            // Without Early Write Acknowledge, Comp waits for the SN-I's.
            // WriteNoSnpDef always does: its Comp carries the SN-I's answer
            // (IHI 0050H B4.5.1.3.1).
            eCompReady[i] = !e.wrOwed
                            && (e.err || e.wrCancel || e.dnMainDone
                                || (ewa && (e.req.opcode != REQ_WRITE_NO_SNP_DEF)));
          HNI_K_ATOMIC:
            eCompReady[i] = !e.wrOwed && (e.err || e.dnMainDone);
          HNI_K_CMO:
            eCompReady[i] = e.err || !cmoForwarded(e.cmo) || e.dnCmoDone;
          HNI_K_CFG_WRITE:
            eCompReady[i] = !e.wrOwed && (e.err || e.dnMainDone);
          HNI_K_DVM:
            eCompReady[i] = !e.wrOwed;
          default:
            eCompReady[i] = 1'b0;
        endcase
      end
      eCompCmoReady[i] = posStarted[i] && e.compCmoOwed && !e.compOwed
                         && !e.dbidOwed && !e.wrOwed
                         && (e.err
                             || ((e.wrCancel || e.dnMainDone)
                                 && (!cmoForwarded(e.cmo) || e.dnCmoDone)));

      eAllDone[i] = posActive[i] && posStarted[i] && !e.receiptOwed
                    && !e.dbidOwed && !e.compOwed && !e.compCmoOwed
                    && !e.compAckOwed && !e.wrOwed && !e.dnBusy && !dnBusy[i]
                    && !eMainNeeded[i] && !eCmoNeeded[i] && !eCfgApply[i];
    end
  end

  // One monitor commit per cycle: of the entries starting that need it, the
  // lowest starts now and the others next.
  always_comb begin
    exclCommitValid = 1'b0;
    exclCommitEntry = '0;
    for (int unsigned i = 0; i < DEPTH; i++)
      if (!exclCommitValid && eMayStart[i] && eExclNeeds[i]) begin
        exclCommitValid = 1'b1;
        exclCommitEntry = IDX_W'(i);
      end
    posStartMask = eMayStart & ~(eExclNeeds & ~(exclCommitValid
                                                 ? (DEPTH'(1) << exclCommitEntry)
                                                 : '0));
    posFreeMask = eAllDone;
  end

  always_comb begin
    hni_entry_t c;
    c = entry[exclCommitEntry];
    exclCommitLoad = c.req.exclOrSnoopMeOrCah && (c.req.opcode == REQ_READ_NO_SNP);
    exclCommitStore = c.req.exclOrSnoopMeOrCah
                      && (c.req.opcode inside {REQ_WRITE_NO_SNP_FULL,
                                               REQ_WRITE_NO_SNP_PTL});
    exclCommitUpdate = !exclCommitLoad && !exclCommitStore;
    // While a passing exclusive write from another LP waits for CompAck,
    // no other LP registers (B6.2.1).
    exclRegisterBlocked = 1'b0;
    for (int unsigned i = 0; i < DEPTH; i++)
      if (posActive[i] && entry[i].exclStore && entry[i].exclPass
          && entry[i].compAckOwed
          && !((entry[i].req.srcId == c.req.srcId)
               && (entry[i].req.groupIdOrLpid == c.req.groupIdOrLpid)))
        exclRegisterBlocked = 1'b1;
  end

  chi_excl_mon #(
    .CFG(CFG), .NUM_REQUESTERS(NUM_REQUESTERS),
    .REQUESTER_NODE_IDS(REQUESTER_NODE_IDS), .RN_NUM_LP(RN_NUM_LP),
    .NUM_LP(NUM_LP), .ADDR_W(KEY_W)
  ) exclusive_monitor (
    .clk, .resetn,
    .commitValid(exclCommitValid), .commitLoad(exclCommitLoad),
    .commitStore(exclCommitStore), .commitUpdate(exclCommitUpdate),
    .commitSrcId(entry[exclCommitEntry].req.srcId),
    .commitLpid(entry[exclCommitEntry].req.groupIdOrLpid),
    .commitKey(posKey[exclCommitEntry]),
    .registerBlocked(exclRegisterBlocked),
    .pass(exclPass), .registered(exclRegistered),
    .lpKnown(exclLpKnown), .lpIndex(exclLpIndex)
  );

  // ---------------------------------------------------------------------
  // Downstream operations: the read, write or atomic first, then the CMO of
  // a Combined write. Each entry has one in flight at most.
  // ---------------------------------------------------------------------
  always_comb begin
    for (int unsigned i = 0; i < DEPTH; i++) begin
      hni_entry_t e;
      e = entry[i];
      dnStartValid[i] = 1'b0;
      dnStartKind[i] = HNF_DN_READ;
      dnStartSub[i] = e.sub;
      dnStartGranules[i] = requestGranules(e.req);
      dnStartReadGranules[i] = '0;
      dnStartWantReceipt[i] = 1'b0;
      if (!e.dnBusy && !dnBusy[i]) begin
        if (eMainNeeded[i] && !eSkipWrite[i] && eEndpointClear[i]) begin
          case (e.kind)
            HNI_K_READ: begin
              dnStartValid[i] = 1'b1;
              dnStartKind[i] = HNF_DN_READ;
              // An ordered read asks the SN-I for a ReadReceipt, which is
              // what lets the next ordered request go (IHI 0050H B2.7.5.1).
              dnStartWantReceipt[i] = e.ordered;
            end
            HNI_K_WRITE: begin
              // An OWO write becomes visible only after CompAck.
              dnStartValid[i] = !e.wrOwed && !(e.req.expCompAck && e.compAckOwed);
              dnStartKind[i] = HNF_DN_WRITE;
            end
            HNI_K_WRITE_ZERO: begin
              dnStartValid[i] = 1'b1;
              dnStartKind[i] = HNF_DN_WRITE;
              dnStartGranules[i] = 4'hf;
            end
            default: begin
              dnStartValid[i] = !e.wrOwed;
              dnStartKind[i] = HNF_DN_ATOMIC;
              dnStartReadGranules[i] = isAtomicStore(e.req.opcode) ? '0
                                       : eCompGranules[i];
            end
          endcase
        end else if (eCmoNeeded[i]
                     && ((e.kind == HNI_K_CMO) || e.dnMainDone)) begin
          dnStartValid[i] = 1'b1;
          dnStartKind[i] = HNF_DN_CMO;
        end
      end
    end
  end

  chi_sn_tracker #(
    .CFG(CFG), .NUM_OWNERS(DEPTH),
    .NUM_SUB(NUM_SNI), .SUB_NODE_IDS(SNI_NODE_IDS)
  ) sn_tracker (
    .clk, .resetn,
    .startValid(dnStartValid), .startKind(dnStartKind),
    .startSub(dnStartSub), .startGranules(dnStartGranules),
    .startReadGranules(dnStartReadGranules), .startNoData('0),
    .startWantReceipt(dnStartWantReceipt),
    .busy(dnBusy), .waiting(dnWaiting), .done(dnDone),
    .resend(dnResend), .resendCreditType(dnResendType),
    .reqIssueReady(reqFifoReady), .reqIssueValid(dnReqValid),
    .reqIssueOwner(dnReqOwner), .reqIssueCreditReturn(dnReqCreditReturn),
    .reqIssueCreditType(dnReqCreditType),
    .reqIssueCreditSub(dnReqCreditSub),
    .datIssueReady(datTrackerWins && datFifoReady),
    .datIssueValid(dnDatValid), .datIssueOwner(dnDatOwner),
    .datIssueDataId(dnDatDataId), .datIssueTxnId(dnDatTxnId),
    .rspValid(snRspValid), .rsp(incomingRsp),
    .datValid(snDatValid), .dat(incomingDat)
  );

  // The request towards the SN-I keeps the Requester's address, Size and
  // attributes, under the HN-I's own SrcID and TxnID (IHI 0050H B2.3.9).
  // Order is passed on for the read, write or atomic itself; SnpAttr and
  // ExpCompAck are zero towards a Subordinate (IHI 0050H B2.8.6).
  always_comb begin
    chi_req_flit_t request;
    hni_entry_t e;
    e = entry[dnReqOwner];
    request = e.req;
    request.tgtId = CHI_MAX_NODEID_W'(SNI_NODE_IDS[e.sub]);
    request.srcId = HN_NODE_ID;
    request.txnId = CHI_TXNID_FLIT_W'(dnReqOwner);
    request.returnNidOrStashNidOrDataTarget = HN_NODE_ID;
    request.returnTxnIdOrStashLpid = CHI_RTNTXNID_SLOT_W'(dnReqOwner);
    request.allowRetry = !dnResend[dnReqOwner];
    request.pCrdType = dnResend[dnReqOwner] ? dnResendType[dnReqOwner] : '0;
    request.expCompAck = 1'b0;
    request.snpAttrOrDoDwt = 1'b0;
    request.likelyShared = 1'b0;
    request.multiReq = 1'b0;
    request.numReq = '0;
    request.tagOp = chi_tag_op_e'('0);
    request.order = e.ordered ? e.req.order : ORDER_NONE;
    // The monitor is here; the SN-I sees an ordinary access.
    request.exclOrSnoopMeOrCah = 1'b0;
    case (e.dnKind)
      HNF_DN_READ: begin
        request.opcode = REQ_READ_NO_SNP;
        request.stashNidValidOrEndianOrDeep = 1'b0;
      end
      HNF_DN_WRITE: begin
        request.stashNidValidOrEndianOrDeep = 1'b0;
        if (e.kind == HNI_K_WRITE_ZERO) begin
          request.opcode = REQ_WRITE_NO_SNP_FULL;
          request.addr = {e.req.addr[CHI_MAX_ADDR_W-1:6], 6'b0};
          request.size = 3'd6;
        end else if (e.req.opcode == REQ_WRITE_NO_SNP_DEF) begin
          request.opcode = REQ_WRITE_NO_SNP_DEF;
        end else begin
          request.opcode = isFullLineWrite(e.req.opcode)
                           ? REQ_WRITE_NO_SNP_FULL : REQ_WRITE_NO_SNP_PTL;
        end
      end
      HNF_DN_ATOMIC: begin
        // Endian travels with the atomic; SnoopMe is inapplicable here.
        request.exclOrSnoopMeOrCah = 1'b0;
      end
      default: begin
        request.opcode = cmoDownstreamOpcode(e.cmo);
        request.order = ORDER_NONE;
        request.size = 3'd6;
        request.exclOrSnoopMeOrCah = 1'b0;
        request.returnTxnIdOrStashLpid = '0;
        // The SN-I sends Persist straight to the Requester, under the
        // Requester's PGroupID (IHI 0050H B2.3.5 alt 3c, B2.4.13).
        if (e.cmo == HNF_CMO_PERSIST_SEP)
          request.returnNidOrStashNidOrDataTarget = e.req.srcId;
        else
          request.returnNidOrStashNidOrDataTarget = '0;
      end
    endcase
    if (dnReqCreditReturn) begin
      request = '0;
      request.tgtId = CHI_MAX_NODEID_W'(SNI_NODE_IDS[dnReqCreditSub]);
      request.srcId = HN_NODE_ID;
      request.opcode = REQ_PCRD_RETURN;
      request.pCrdType = dnReqCreditType;
    end
    dnReqFlit = '0;
    dnReqFlit.channel = CHI_CHANNEL_REQ;
    dnReqFlit.qos = request.qos;
    dnReqFlit.targetNodeId = request.tgtId;
    dnReqFlit.payload[CHI_MAX_REQ_FLIT_W-1:0] = packReqFlit(CFG, request);
  end

  // Write data and atomic operands towards the SN-I.
  always_comb begin
    chi_dat_flit_t data;
    hni_entry_t e;
    e = entry[dnDatOwner];
    data = '0;
    data.qos = e.req.qos;
    data.tgtId = CHI_MAX_NODEID_W'(SNI_NODE_IDS[e.sub]);
    data.srcId = HN_NODE_ID;
    data.txnId = CHI_TXNID_FLIT_W'(dnDatTxnId);
    data.opcode = DAT_NON_COPY_BACK_WR_DATA;
    data.resp = RESP_I;
    data.respErr = bufReqErr[dnDatOwner] ? RESP_ERR_DERR : RESP_ERR_OK;
    data.dataId = dnDatDataId;
    data.ccId = (e.kind == HNI_K_WRITE_ZERO) ? '0 : e.req.addr[5:4];
    data.data[CFG.dataW-1:0] = bufReq[dnDatOwner][int'(dnDatDataId)*128 +: CFG.dataW];
    for (int unsigned b = 0; b < DAT_BYTES; b++)
      data.be[b] = bufReqBe[dnDatOwner][int'(dnDatDataId)*16 + b];
    data.dataCheck = dataCheckOf(data.data);
    data.poison[POISON_PER_BEAT-1:0] =
      bufReqPoison[dnDatOwner][int'(dnDatDataId)*2 +: POISON_PER_BEAT];
    dnDatFlit = '0;
    dnDatFlit.channel = CHI_CHANNEL_DAT;
    dnDatFlit.qos = data.qos;
    dnDatFlit.targetNodeId = data.tgtId;
    dnDatFlit.payload = packDatFlit(CFG, data);
  end

  // ---------------------------------------------------------------------
  // Input classification. RSP and DAT are always accepted.
  // ---------------------------------------------------------------------
  always_comb begin
    rspInReady = 1'b1;
    datInReady = 1'b1;
  end

  always_comb begin
    logic rspFromRequester;
    rspFromRequester = incomingRsp.opcode == RSP_COMP_ACK;
    compAckValid = rspInValid && rspFromRequester
                   && (int'(incomingRsp.txnId) < DEPTH);
    compAckEntry = IDX_W'(incomingRsp.txnId);
    // Everything else on RSP comes from an SN-I.
    snRspValid = rspInValid && !rspFromRequester;
    snRspForEntry = snRspValid && (int'(incomingRsp.txnId) < DEPTH)
                    && !(incomingRsp.opcode inside {RSP_RETRY_ACK,
                                                    RSP_PCRD_GRANT});
    snRspEntry = IDX_W'(incomingRsp.txnId);

    snDatValid = datInValid && ((incomingDat.opcode == DAT_COMP_DATA)
                                || (incomingDat.opcode == DAT_DATA_SEP_RESP));
    snDatForEntry = snDatValid && (int'(incomingDat.txnId) < DEPTH);
    snDatEntry = IDX_W'(incomingDat.txnId);

    wrDatValid = datInValid && isRequesterData(incomingDat.opcode)
                 && (int'(incomingDat.txnId) < DEPTH);
    wrDatEntry = IDX_W'(incomingDat.txnId);
    wrDatGranules = '0;
    for (int unsigned g = 0; g < 4; g++)
      if ((g >= int'(incomingDat.dataId))
          && (g < (int'(incomingDat.dataId) + (int'(incomingDat.numDat) + 1) * STEP)))
        wrDatGranules[g] = 1'b1;
  end

  // One configuration write takes effect per cycle.
  always_comb begin
    cfgApplyValid = 1'b0;
    cfgApplyEntry = '0;
    for (int unsigned i = 0; i < DEPTH; i++)
      if (!cfgApplyValid && eCfgApply[i]) begin
        cfgApplyValid = 1'b1;
        cfgApplyEntry = IDX_W'(i);
      end
    cfgCommitAllowed = othersQuiescent
                       && ((posActive & ~(DEPTH'(1) << cfgApplyEntry)) == '0);
  end

  // ---------------------------------------------------------------------
  // Responses to Requesters: RetryAck first, then PCrdGrant, then entries in
  // round-robin order; within an entry ReadReceipt, DBIDResp, Comp, CompCMO.
  // ---------------------------------------------------------------------
  always_comb begin
    logic found;
    int unsigned candidate;
    for (int unsigned i = 0; i < DEPTH; i++)
      rspWant[i] = posActive[i]
                   && (entry[i].receiptOwed || eDbidReady[i]
                       || (eCompReady[i] && !eCompIsData[i])
                       || eCompCmoReady[i]);
    found = 1'b0;
    rspEntry = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < DEPTH; offset++) begin
      candidate = int'(rspPointer) + offset;
      if (candidate >= DEPTH)
        candidate = candidate - DEPTH;
      if (!found && rspWant[candidate]) begin
        found = 1'b1;
        rspEntry = IDX_W'(candidate);
      end
    end
    rspEntryValid = found;
    rspGrantSend = !retryAckWant && retryGrantValid && rspFifoReady;
    rspEntrySend = !retryAckWant && !retryGrantValid && rspEntryValid
                   && rspFifoReady;
    retryGrantReady = rspGrantSend;
  end

  always_comb begin
    chi_rsp_flit_t response;
    hni_entry_t e;
    e = entry[rspEntry];
    response = '0;
    response.srcId = HN_NODE_ID;
    if (retryAckWant) begin
      response.qos = incomingReq.qos;
      response.tgtId = incomingReq.srcId;
      response.txnId = incomingReq.txnId;
      response.opcode = RSP_RETRY_ACK;
      response.pCrdType = retryClass;
    end else if (retryGrantValid) begin
      // PCrdGrant names the Requester and carries no TxnID or DBID
      // (IHI 0050H B2.5.5).
      response.tgtId = retryGrantTgtId;
      response.opcode = RSP_PCRD_GRANT;
      response.pCrdType = retryGrantClass;
    end else begin
      response.qos = e.req.qos;
      response.tgtId = e.req.srcId;
      response.txnId = e.req.txnId;
      response.dbIdOrGroupId = CHI_RSP_DBID_SLOT_W'(rspEntry);
      response.respErr = e.err ? RESP_ERR_NDERR
                         : ((e.exclStore && e.exclPass) ? RESP_ERR_EXOK : e.dnErr);
      if (e.receiptOwed) begin
        response.opcode = RSP_READ_RECEIPT;
        response.respErr = RESP_ERR_OK;
      end else if (eDbidReady[rspEntry]) begin
        response.opcode = e.dbidWithComp ? RSP_COMP_DBID_RESP : RSP_DBID_RESP;
        if (!e.dbidWithComp)
          response.respErr = RESP_ERR_OK;
      end else if (eCompReady[rspEntry] && !eCompIsData[rspEntry]) begin
        response.opcode = RSP_COMP;
        // WriteNoSnpDef: the SN-I's OK/Unsupported/Defer answer
        // (IHI 0050H Table B4.29).
        if ((e.req.opcode == REQ_WRITE_NO_SNP_DEF) && !e.err)
          response.resp = e.dnResp;
        if (e.req.opcode inside {REQ_STASH_ONCE_SEP_SHARED,
                                 REQ_STASH_ONCE_SEP_UNIQUE}) begin
          response.opcode = RSP_COMP_STASH_DONE;
          response.dbIdOrGroupId = CHI_RSP_DBID_SLOT_W'(e.req.groupIdOrLpid);
        end
      end else begin
        response.opcode = RSP_COMP_CMO;
      end
    end
    rspPushValid = retryAckWant || retryGrantValid || rspEntryValid;
    rspPushFlit = '0;
    rspPushFlit.channel = CHI_CHANNEL_RSP;
    rspPushFlit.qos = response.qos;
    rspPushFlit.targetNodeId = response.tgtId;
    rspPushFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] = packRspFlit(CFG, response);
  end

  // ---------------------------------------------------------------------
  // CompData to Requesters and write data to SN-Is share the DAT output;
  // whichever did not go last has priority when both are waiting.
  // ---------------------------------------------------------------------
  always_comb begin
    logic found;
    int unsigned candidate;
    logic [3:0] remaining;
    for (int unsigned i = 0; i < DEPTH; i++)
      datWant[i] = posActive[i] && eCompReady[i] && eCompIsData[i];
    found = 1'b0;
    datEntry = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < DEPTH; offset++) begin
      candidate = int'(datPointer) + offset;
      if (candidate >= DEPTH)
        candidate = candidate - DEPTH;
      if (!found && datWant[candidate]) begin
        found = 1'b1;
        datEntry = IDX_W'(candidate);
      end
    end
    datEntryValid = found;
    remaining = eCompGranules[datEntry] & ~entry[datEntry].compGranSent;
    datEntryDataId = '0;
    for (int unsigned g = 4; g > 0; g--)
      if (remaining[g-1])
        datEntryDataId = 2'((g - 1) & ~(STEP - 1));
    datTrackerWins = dnDatValid && (datTrackerTurn || !datEntryValid);
    datTrackerSend = datTrackerWins && datFifoReady;
    datEntrySend = datEntryValid && !datTrackerWins && datFifoReady;
  end

  always_comb begin
    chi_dat_flit_t data;
    hni_entry_t e;
    logic [511:0] line;
    e = entry[datEntry];
    data = '0;
    data.qos = e.req.qos;
    data.tgtId = e.req.srcId;
    data.srcId = HN_NODE_ID;
    data.txnId = e.req.txnId;
    data.homeNidOrPbha = HN_NODE_ID;
    data.dbId = CHI_DAT_DBID_SLOT_W'(datEntry);
    data.opcode = DAT_COMP_DATA;
    data.dataId = datEntryDataId;
    data.ccId = e.req.addr[5:4];
    data.resp = RESP_I;
    data.respErr = e.err ? RESP_ERR_NDERR
                   : ((e.dnErr != RESP_ERR_OK) ? e.dnErr
                      : (e.exclLoad ? RESP_ERR_EXOK : RESP_ERR_OK));
    line = bufRsp[datEntry];
    if (e.kind == HNI_K_CFG_READ) begin
      line = '0;
      line[int'(e.req.addr[5:3])*64 +: 64] = configValue(e.req.addr[7:0]);
    end
    // ReadNoSnp passes on the state the SN-I gave; ReadOnce* and atomic
    // return data is never cached (IHI 0050H B4.5.1.1).
    if ((e.kind == HNI_K_READ) && (e.req.opcode == REQ_READ_NO_SNP) && !e.err)
      data.resp = e.dnResp;
    if (!e.err) begin
      data.data[CFG.dataW-1:0] = line[int'(datEntryDataId)*128 +: CFG.dataW];
      if (e.kind != HNI_K_CFG_READ)
        data.poison[POISON_PER_BEAT-1:0] =
          bufRspPoison[datEntry][int'(datEntryDataId)*2 +: POISON_PER_BEAT];
    end
    for (int unsigned b = 0; b < DAT_BYTES; b++)
      data.be[b] = 1'b1;
    data.dataCheck = dataCheckOf(data.data);
    datPushFlit = '0;
    datPushFlit.channel = CHI_CHANNEL_DAT;
    if (datTrackerWins) begin
      datPushFlit = dnDatFlit;
    end else begin
      datPushFlit.qos = data.qos;
      datPushFlit.targetNodeId = data.tgtId;
      datPushFlit.payload = packDatFlit(CFG, data);
    end
    datPushValid = dnDatValid || datEntryValid;
  end

  // ---------------------------------------------------------------------
  // Output stages.
  // ---------------------------------------------------------------------
  chi_flit_fifo req_fifo (
    .clk, .resetn, .pushValid(dnReqValid), .pushReady(reqFifoReady),
    .pushFlit(dnReqFlit), .outValid(reqOutValid), .outReady(reqOutReady),
    .outFlit(reqOutFlit), .count(reqFifoCount)
  );
  chi_flit_fifo rsp_fifo (
    .clk, .resetn, .pushValid(rspPushValid), .pushReady(rspFifoReady),
    .pushFlit(rspPushFlit), .outValid(rspOutValid), .outReady(rspOutReady),
    .outFlit(rspOutFlit), .count(rspFifoCount)
  );
  chi_flit_fifo dat_fifo (
    .clk, .resetn, .pushValid(datPushValid), .pushReady(datFifoReady),
    .pushFlit(datPushFlit), .outValid(datOutValid), .outReady(datOutReady),
    .outFlit(datOutFlit), .count(datFifoCount)
  );

  always_comb begin
    idle = (posActive == '0) && (reqFifoCount == '0) && (rspFifoCount == '0)
           && (datFifoCount == '0) && !retryGrantsOwed
           && (retryCreditsOutstanding == '0);
  end

  // Per-entry views for the bound assertions.
  logic [DEPTH-1:0] eOrdered;
  logic [DEPTH-1:0] eAccepted;
  logic [DEPTH-1:0] eOwoWrite;
  logic [DEPTH-1:0] eCompAckOwed;
  logic [DEPTH-1:0] eReceiptOwed;
  logic [DEPTH-1:0] eErr;
  logic [DEPTH-1:0] eGpcPending;
  logic [DEPTH-1:0] liveWaitDownstream;
  logic [DEPTH-1:0] liveWaitRequester;

  // A Requester owes write data once it has the DBID, and CompAck once it
  // has DBIDResp (an OWO write) or every response (anything else).
  always_comb begin
    for (int unsigned i = 0; i < DEPTH; i++) begin
      eOrdered[i] = entry[i].ordered;
      eAccepted[i] = entry[i].dnAccepted;
      eOwoWrite[i] = (entry[i].kind == HNI_K_WRITE) && entry[i].req.expCompAck;
      eCompAckOwed[i] = entry[i].compAckOwed;
      eReceiptOwed[i] = entry[i].receiptOwed;
      eErr[i] = posActive[i] && entry[i].err;
      eGpcPending[i] = posActive[i] && entry[i].gpcPending;
      liveWaitDownstream[i] = dnWaiting[i];
      liveWaitRequester[i] = (entry[i].wrOwed && !entry[i].dbidOwed)
                             || (entry[i].compAckOwed && !entry[i].dbidOwed
                                 && (eOwoWrite[i] || !entry[i].compOwed));
    end
  end

  // ---------------------------------------------------------------------
  // Sequential state.
  // ---------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned i = 0; i < DEPTH; i++)
        entry[i] <= '0;
      rspPointer <= '0;
      datPointer <= '0;
      datTrackerTurn <= 1'b0;
      gpcRecheckPointer <= '0;
      selectedRegion <= '0;
      mmioRegionUpdate <= 1'b0;
      mmioRegionUpdateIndex <= '0;
      mmioRegionUpdateBase <= '0;
      mmioRegionUpdateLimit <= '0;
      mmioRegionUpdateTarget <= '0;
      mmioRegionUpdateAttributes <= '0;
      for (int unsigned region = 0; region < NUM_REGIONS; region++) begin
        stagedBase[region] <= REGION_BASE[region];
        stagedLimit[region] <= REGION_LIMIT[region];
        stagedTarget[region] <= REGION_TARGET[region];
        stagedAttributes[region] <= REGION_ATTRIBUTES[region];
      end
    end else begin
      mmioRegionUpdate <= 1'b0;
      if (regionUpdate) begin
        stagedBase[regionUpdateIndex] <= regionUpdateBase;
        stagedLimit[regionUpdateIndex] <= regionUpdateLimit;
        stagedTarget[regionUpdateIndex] <= regionUpdateTarget;
        stagedAttributes[regionUpdateIndex] <= regionUpdateAttributes;
      end

      // Allocation.
      if (posAllocValid && posAllocReady)
        entry[posAllocIndex] <= allocEntryChecked;

      // The monitor's answer, recorded as the entry starts. A failing
      // exclusive write then sends nothing.
      if (exclCommitValid) begin
        entry[exclCommitEntry].exclLoad <= exclCommitLoad && exclRegistered;
        entry[exclCommitEntry].exclStore <= exclCommitStore;
        entry[exclCommitEntry].exclPass <= exclCommitStore && exclPass;
        if (exclCommitStore && !exclPass)
          entry[exclCommitEntry].dnAccepted <= 1'b1;
      end

      if (gpcRecheckValid && gpcCheckDone) begin
        entry[gpcRecheckEntry].gpcPending <= 1'b0;
        if (gpcCheckFail)
          entry[gpcRecheckEntry].err <= 1'b1;
        gpcRecheckPointer <= (int'(gpcRecheckEntry) == (DEPTH - 1))
                             ? '0 : (gpcRecheckEntry + 1'b1);
      end

      for (int unsigned i = 0; i < DEPTH; i++) begin
        // Start: an entry with nothing to send downstream counts as
        // accepted, so it never holds back an Endpoint-ordered request.
        if (posStartMask[i] && eNoDownstream[i] && !eExclNeeds[i])
          entry[i].dnAccepted <= 1'b1;
        if (eSkipWrite[i]) begin
          entry[i].dnMainDone <= 1'b1;
          entry[i].dnAccepted <= 1'b1;
        end
        if (dnStartValid[i]) begin
          entry[i].dnBusy <= 1'b1;
          entry[i].dnKind <= dnStartKind[i];
        end
        if (dnDone[i]) begin
          entry[i].dnBusy <= 1'b0;
          if (entry[i].dnKind == HNF_DN_CMO)
            entry[i].dnCmoDone <= 1'b1;
          else
            entry[i].dnMainDone <= 1'b1;
        end
      end

      // The SN-I's responses: any but RetryAck accepts the request, and its
      // state and error are kept for the Requester.
      if (snRspForEntry) begin
        entry[snRspEntry].dnAccepted <= 1'b1;
        if (incomingRsp.respErr != RESP_ERR_OK)
          entry[snRspEntry].dnErr <= incomingRsp.respErr;
        if ((incomingRsp.opcode == RSP_COMP)
            || (incomingRsp.opcode == RSP_COMP_DBID_RESP))
          entry[snRspEntry].dnResp <= incomingRsp.resp;
      end
      if (snDatForEntry) begin
        entry[snDatEntry].dnAccepted <= 1'b1;
        entry[snDatEntry].dnResp <= incomingDat.resp;
        if (incomingDat.respErr != RESP_ERR_OK)
          entry[snDatEntry].dnErr <= incomingDat.respErr;
      end

      // Requester data.
      if (wrDatValid && entry[wrDatEntry].wrOwed) begin
        if ((entry[wrDatEntry].kind == HNI_K_DVM)
            || (((entry[wrDatEntry].wrGranules | wrDatGranules)
                 & requestGranules(entry[wrDatEntry].req))
                == requestGranules(entry[wrDatEntry].req)))
          entry[wrDatEntry].wrOwed <= 1'b0;
        entry[wrDatEntry].wrGranules <= entry[wrDatEntry].wrGranules | wrDatGranules;
        if (incomingDat.opcode == DAT_WRITE_DATA_CANCEL)
          entry[wrDatEntry].wrCancel <= 1'b1;
        if (incomingDat.opcode == DAT_NCB_WR_DATA_COMP_ACK)
          entry[wrDatEntry].compAckOwed <= 1'b0;
      end

      // CompAck.
      if (compAckValid && (incomingRsp.srcId == entry[compAckEntry].req.srcId))
        entry[compAckEntry].compAckOwed <= 1'b0;

      // Configuration writes: the register named by the request address
      // takes the bytes at their natural position.
      if (cfgApplyValid) begin
        logic [7:0] offset;
        logic [63:0] value;
        offset = entry[cfgApplyEntry].req.addr[7:0];
        value = bufReq[cfgApplyEntry][int'(entry[cfgApplyEntry].req.addr[5:3])*64 +: 64];
        entry[cfgApplyEntry].dnMainDone <= 1'b1;
        // A commit takes effect only on a quiescent fabric: every other Home
        // idle and nothing else at this HN-I. Otherwise it changes nothing
        // and completes with NDERR.
        if (((offset & 8'hf8) == 8'h28) && !cfgCommitAllowed)
          entry[cfgApplyEntry].err <= 1'b1;
        else if (!entry[cfgApplyEntry].wrCancel) begin
          case (offset & 8'hf8)
            8'h00:
              if ((value[63:REG_W] == '0)
                  && ({1'b0, value[REG_W-1:0]} < (REG_W+1)'(NUM_REGIONS)))
                selectedRegion <= value[REG_W-1:0];
            8'h08: stagedBase[selectedRegion] <= value[CFG.addrW-1:0];
            8'h10: stagedLimit[selectedRegion] <= value[CFG.addrW-1:0];
            8'h18: stagedTarget[selectedRegion] <= value[CHI_NODEID_SLOT_W-1:0];
            8'h20: stagedAttributes[selectedRegion] <= value[CHI_SAM_ATTR_W-1:0];
            8'h28: begin
              mmioRegionUpdate <= 1'b1;
              mmioRegionUpdateIndex <= selectedRegion;
              mmioRegionUpdateBase <= stagedBase[selectedRegion];
              mmioRegionUpdateLimit <= stagedLimit[selectedRegion];
              mmioRegionUpdateTarget <= stagedTarget[selectedRegion];
              mmioRegionUpdateAttributes <= stagedAttributes[selectedRegion];
            end
            default: begin
            end
          endcase
        end
      end

      // Responses sent.
      if (rspEntrySend) begin
        if (entry[rspEntry].receiptOwed) begin
          entry[rspEntry].receiptOwed <= 1'b0;
        end else if (eDbidReady[rspEntry]) begin
          entry[rspEntry].dbidOwed <= 1'b0;
          if (entry[rspEntry].dbidWithComp)
            entry[rspEntry].compOwed <= 1'b0;
        end else if (eCompReady[rspEntry] && !eCompIsData[rspEntry]) begin
          entry[rspEntry].compOwed <= 1'b0;
        end else begin
          entry[rspEntry].compCmoOwed <= 1'b0;
        end
        rspPointer <= (int'(rspEntry) == (DEPTH - 1)) ? '0 : (rspEntry + 1'b1);
      end

      // Data sent.
      if (datEntrySend) begin
        for (int unsigned g = 0; g < 4; g++)
          if ((g >= int'(datEntryDataId)) && (g < (int'(datEntryDataId) + STEP)))
            entry[datEntry].compGranSent[g] <= 1'b1;
        if (((entry[datEntry].compGranSent | beatGranules(CFG, datEntryDataId))
             & eCompGranules[datEntry]) == eCompGranules[datEntry])
          entry[datEntry].compOwed <= 1'b0;
        datPointer <= (int'(datEntry) == (DEPTH - 1)) ? '0 : (datEntry + 1'b1);
      end
      if (datTrackerSend)
        datTrackerTurn <= 1'b0;
      else if (datEntrySend)
        datTrackerTurn <= 1'b1;
    end
  end

  // Buffers. Requester data is written over a cleared buffer; SN-I data lands
  // at its natural position.
  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned i = 0; i < DEPTH; i++) begin
        bufReq[i] <= '0;
        bufReqBe[i] <= '0;
        bufReqPoison[i] <= '0;
        bufRsp[i] <= '0;
        bufRspPoison[i] <= '0;
      end
      bufReqErr <= '0;
    end else begin
      if (posAllocValid && posAllocReady) begin
        bufReq[posAllocIndex] <= '0;
        bufReqBe[posAllocIndex] <= (allocEntry.kind == HNI_K_WRITE_ZERO)
                                   ? ALL_BYTES : '0;
        bufReqPoison[posAllocIndex] <= '0;
        bufReqErr[posAllocIndex] <= 1'b0;
        bufRspPoison[posAllocIndex] <= '0;
      end
      if (wrDatValid && entry[wrDatEntry].wrOwed
          && (incomingDat.opcode != DAT_WRITE_DATA_CANCEL)) begin
        for (int unsigned b = 0; b < DAT_BYTES; b++)
          if (incomingDat.be[b])
            bufReq[wrDatEntry][(int'(incomingDat.dataId)*16 + b)*8 +: 8] <=
              incomingDat.data[b*8 +: 8];
        for (int unsigned b = 0; b < DAT_BYTES; b++)
          bufReqBe[wrDatEntry][int'(incomingDat.dataId)*16 + b] <= incomingDat.be[b];
        bufReqPoison[wrDatEntry][int'(incomingDat.dataId)*2 +: POISON_PER_BEAT] <=
          incomingDat.poison[POISON_PER_BEAT-1:0];
        if (incomingDat.respErr == RESP_ERR_DERR)
          bufReqErr[wrDatEntry] <= 1'b1;
      end
      if (snDatForEntry) begin
        bufRsp[snDatEntry][int'(incomingDat.dataId)*128 +: CFG.dataW] <=
          incomingDat.data[CFG.dataW-1:0];
        bufRspPoison[snDatEntry][int'(incomingDat.dataId)*2 +: POISON_PER_BEAT] <=
          incomingDat.poison[POISON_PER_BEAT-1:0];
      end
    end
  end
endmodule
