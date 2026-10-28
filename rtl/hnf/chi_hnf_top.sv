// Coherent Home Node (HN-F).
//
// Every request the Home accepts gets its own POS entry, and every entry runs
// its own transaction: there is no global FSM. Transactions to different
// locations proceed together; transactions to one location run one at a time
// in arrival order, held back by chi_hazard until the older one frees
// (IHI 0050H B4.11.2). An entry is a set of obligations — responses it owes
// the Requester, snoops it must send and collect, data it must receive,
// memory operations it must have performed — and it frees once every
// obligation is met and the directory is updated.
//
// Owners. The snoop engine, the downstream trackers and the line buffers are
// shared by POS entries (owners 0 .. POS_DEPTH-1) and victim-buffer entries
// (owners POS_DEPTH ..). A victim entry holds a location the directory had to
// evict; it snoops the location out with SnpCleanInvalid and writes back any
// Dirty data, and while it does so the location is hazarded like a POS entry.
//
// Identifiers. Towards a Requester the Home uses the entry index as DBID, so
// write data and CompAck index the entry directly (IHI 0050H B2.4.3). Towards
// an RN-F a snoop carries the owner index as TxnID, and towards the
// Subordinate a request carries the owner index as TxnID; neither ever carries
// a Requester's TxnID. An owner snoops each RN-F at most once, so no Snoopee
// ever holds two snoops from this Home with one TxnID (IHI 0050H B2.4.2).
//
// Snoops. An owner's snoops leave back to back and are collected in any
// order, up to maxOutstandingSnoops in flight across the Home. Each Snoopee's
// data packets are counted on their own, so several Snoopees can return data
// for one transaction at once; valid copies of a line hold the same data, so
// they merge into one buffer. A forwarded response (SnpRespFwded,
// SnpRespDataFwded) means the Snoopee sent CompData to the Requester itself
// in the state FwdState names, and the entry then owes no data of its own
// (IHI 0050H B4.5.3).
//
// Data. Each owner has a 64-byte line buffer with three byte-valid masks:
// bytes written by the Requester, bytes from a snoop, bytes from memory. A
// later source never overwrites a more recent one, so a partial write merges
// over Dirty snoop data, which merges over memory data.
//
// Direct transfers (IHI 0050H B2.3.1.1, B2.3.2.1, B2.5.1): DCT sends a
// forwarding snoop to a DCT-capable owner, DMT has the SN-F return a read's
// data to the Requester (CompData, or with dmtSepEn DataSepResp after the
// Home's RespSepData), and DWT has the Requester send write data straight
// to the SN-F. Each is chosen per transaction from the global enable, the
// node capability, the run-time policy and the rules of the transaction; see
// the design specification, Section 9.14.
module chi_hnf_top #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] HN_NODE_ID = '0,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0] SN_NODE_ID = '0,
  parameter int unsigned NUM_RNF = (CFG.numRnf > 0) ? CFG.numRnf : 1,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    RNF_NODE_IDS [NUM_RNF] = '{default:'0},
  // Every Requester that may send to this Home, for Request Retry and the
  // exclusive monitor, with its exclusive-capable LPs and their sum.
  parameter int unsigned NUM_REQUESTERS = NUM_RNF,
  parameter logic [chi_cfg_pkg::CHI_MAX_NODEID_W-1:0]
    REQUESTER_NODE_IDS [NUM_REQUESTERS] = '{default:'0},
  parameter int unsigned RN_NUM_LP [NUM_REQUESTERS] = '{default:1},
  parameter int unsigned NUM_LP = NUM_REQUESTERS,
  // Capabilities of the SN-F this Home is striped to and of every RN-F as a
  // DCT forwarder (IHI 0050H B16.1.3, B16.1.5).
  parameter bit SN_DMT_CAP = 1'b1,
  parameter bit SN_DWT_CAP = 1'b1,
  parameter logic [NUM_RNF-1:0] RNF_DCT_CAP = '1,
  // Victim-buffer entries for directory evictions.
  parameter int unsigned VICTIM_DEPTH = 2
) (
  input  logic clk,
  input  logic resetn,
  // Run-time policy, committed over APB while the fabric is quiescent.
  input  chi_cfg_pkg::chi_hnf_policy_t policy,
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
  output logic snpOutValid,
  input  logic snpOutReady,
  output chi_pkg::chi_noc_flit_t snpOutFlit,
  output logic datOutValid,
  input  logic datOutReady,
  output chi_pkg::chi_noc_flit_t datOutFlit,
  output logic idle,
  // SLC maintenance from the Root-only register: write back every dirty
  // line, and with invalidate also drop every line; busy until it is done
  // and every write-back has completed.
  input  logic slcMaintStart,
  input  logic slcMaintInvalidate,
  output logic slcMaintBusy,
  // Granule Protection Check (chi_gpc): every request the Home admits is
  // checked before it starts; done is combinational, fail means NDERR.
  output logic gpcCheckValid,
  output logic [chi_pkg::CHI_MAX_ADDR_W-1:0] gpcCheckAddr,
  output chi_pkg::chi_pas_e gpcCheckPas,
  output logic [chi_cfg_pkg::CHI_NODEID_SLOT_W-1:0] gpcCheckSrcId,
  input  logic gpcCheckDone,
  input  logic gpcCheckFail,
  // GPT reads for the walker, of lines this HN-F owns, through a tracker
  // reserved for them.
  input  logic gptReadValid,
  input  logic [chi_pkg::CHI_MAX_ADDR_W-1:0] gptReadAddr,
  output logic gptReadDone,
  output logic [511:0] gptReadData,
  output logic gptReadError
);
  import chi_cfg_pkg::*;
  import chi_pkg::*;
  import chi_hnf_pkg::*;

  localparam int unsigned POS_DEPTH = (CFG.posEntries > 0) ? CFG.posEntries : 1;
  localparam int unsigned NUM_VB = (VICTIM_DEPTH > 0) ? VICTIM_DEPTH : 1;
  localparam int unsigned NUM_OWNERS = POS_DEPTH + NUM_VB;
  localparam int unsigned OWNER_W = clog2Min1(NUM_OWNERS);
  // With a GPT walker, one more downstream tracker serves its reads.
  localparam bit GPT_READS = CFG.gpcMode == GPC_WALK;
  localparam int unsigned TRK_OWNERS = NUM_OWNERS + (GPT_READS ? 1 : 0);
  localparam int unsigned TRK_W = clog2Min1(TRK_OWNERS);
  localparam int unsigned GPT_OWNER = NUM_OWNERS;
  // An index that is in range whether or not the walker's tracker exists.
  localparam int unsigned GPT_IDX = GPT_READS ? GPT_OWNER : 0;
  localparam int unsigned POS_W = clog2Min1(POS_DEPTH);
  localparam int unsigned VB_W = clog2Min1(NUM_VB);
  localparam int unsigned RNF_W = clog2Min1(NUM_RNF);
  localparam int unsigned SNP_COUNT_W = clog2Min1(CFG.maxOutstandingSnoops + 1);
  // A location is a 64-byte line in one Physical Address Space: PAS is part
  // of the address for every snoopable access (IHI 0050H B2.8.2), so it is
  // part of every key the Home compares, stores or snoops with.
  localparam int unsigned LINE_W = CFG.addrW - 6;
  localparam int unsigned KEY_W = LINE_W + CHI_PAS_W;
  localparam int unsigned RETRY_RECORDS =
    (CFG.retryRecords > 0) ? CFG.retryRecords : 1;
  localparam int unsigned RESERVE_W = 16;
  localparam int unsigned DAT_BYTES = CFG.dataW / 8;
  localparam int unsigned STEP = datIdStep(CFG);
  localparam int unsigned POISON_PER_BEAT = CFG.dataW / 64;
  localparam int unsigned SF_WAYS =
    (CFG.snpFilterWays > 0) ? CFG.snpFilterWays : 1;
  localparam logic [63:0] ALL_BYTES = '1;

  generate
    begin : chi_cfg_check
      initial begin
        if (NUM_REQUESTERS == 0)
          $fatal(1, "chi_hnf_top NUM_REQUESTERS must be at least 1: Request Retry has to know whom it owes a P-Credit");
        if (VICTIM_DEPTH == 0)
          $fatal(1, "chi_hnf_top VICTIM_DEPTH must be at least 1: a directory eviction needs a victim entry to snoop out and write back the evicted line");
        // The owner index is the TxnID of every snoop and every downstream
        // request, and the POS index is the DBID, so both must fit TxnID.
        if (TRK_OWNERS > (1 << CFG.txnIdW))
          $fatal(1, "posEntries (%0d) plus VICTIM_DEPTH (%0d) owners, and the GPT walker's tracker with gpcMode WALK, do not fit the %0d-bit TxnID the Home uses for snoops, downstream requests and DBID",
                 CFG.posEntries, VICTIM_DEPTH, CFG.txnIdW);
      end
    end
  endgenerate

  // ---------------------------------------------------------------------
  // Per-entry transaction state. Fields are grouped by what owns them:
  // the request and its decode never change after allocation; the
  // directory snapshot and the plan are written once when the entry
  // starts; the rest moves as messages arrive and leave.
  // ---------------------------------------------------------------------
  typedef struct packed {
    // Life cycle.
    chi_hnf_phase_e     phase;
    // Request as received, and its decode.
    chi_req_flit_t      req;
    chi_hnf_kind_e      kind;
    chi_hnf_cmo_e       cmo;
    chi_hnf_err_e       err;         // NDERR cause, decided before start
    logic               reqIsRnf;    // the Requester is a tracked RN-F
    logic [RNF_W-1:0]   reqRnf;      // its RN-F index
    // Directory snapshot taken when the entry starts.
    logic               sfHit;
    logic [NUM_RNF-1:0] sfSharers;
    logic               sfOwnerValid;
    logic [RNF_W-1:0]   sfOwner;
    // Exclusive result, decided when the entry starts.
    logic               exclLoad;    // an Exclusive Load the monitor accepted
    logic               exclStore;   // an Exclusive Store transaction
    logic               exclPass;    // the Exclusive Store passed
    // Snoops.
    logic [NUM_RNF-1:0] snpTargets;  // every RN-F this entry snoops
    logic [NUM_RNF-1:0] snpToSend;   // not yet sent
    logic [NUM_RNF-1:0] snpPending;  // sent, response outstanding
    logic [NUM_RNF-1:0] snpKeep;     // Snoopee kept a copy
    logic [NUM_RNF-1:0] snpOwns;     // Snoopee kept UC, UD or SD
    chi_snp_opcode_e    snpOpcode;   // snoop for every target but the stash target
    logic               snpRetToSrc;
    logic [NUM_RNF-1:0][3:0] snpGranules; // data granules, per Snoopee
    logic               snpDirty;    // snoop data carried PassDirty
    logic               snpPtl;      // the Dirty data was partial
    logic               snpErr;      // a snoop response reported an error
    logic               snpFwded;    // a Snoopee sent CompData to the Requester
    chi_resp_e          snpFwdState; // the state it sent (FwdState)
    // Stashing.
    logic               stashValid;  // a stash snoop goes to stashTarget
    logic [RNF_W-1:0]   stashTarget;
    chi_snp_opcode_e    stashOpcode;
    logic               stashLpidValid;
    logic [CHI_MAX_LPID_W-1:0] stashLpid;
    logic               stashUnique;
    chi_resp_e          pullResp;    // state the Data Pull CompData grants
    logic               pullValid;   // the stash target asked for a Data Pull
    logic [CHI_TXNID_FLIT_W-1:0] pullTxnId;
    logic [3:0]         pullGranSent;
    logic               pullAckOwed; // CompAck owed by the stash target
    // Requester data.
    logic               wrOwed;      // write data still owed by the Requester
    logic [3:0]         wrGranules;
    logic               wrCancel;    // WriteDataCancel or CopyBackWriteData_I
    chi_resp_e          wrResp;      // CopyBack data state
    logic [CFG.dataW-1:0] atomicBeat;   // the packet carrying the operand
    logic [1:0]         atomicBeatId;
    // Atomic result.
    logic               atomicDone;
    logic               atomicUpdate; // the operation changed the location
    logic [63:0]        atomicOrig;   // value returned to the Requester
    // Downstream.
    logic               dnBusy;      // an operation is with the SN tracker
    chi_hnf_dn_e        dnKind;      // the one in flight
    logic               dnReadDone;
    logic               dnWriteDone;
    logic               dnCmoDone;
    // Responses owed to the Requester.
    logic               receiptOwed; // ReadReceipt
    logic               dbidOwed;    // DBIDResp, or CompDBIDResp if dbidWithComp
    logic               dbidWithComp;
    logic               compOwed;    // Comp, CompData or CompStashDone
    logic [3:0]         compGranSent;
    logic               compCmoOwed; // CompCMO of a Combined write
    logic               compAckOwed; // CompAck from the Requester
    logic               sfUpdOwed;   // directory write at retirement
    // System Level Cache, decided when the entry starts.
    logic               slcHit;      // the line was in the SLC
    logic               slcDirty;    // and dirty there
    logic               slcKeep;     // the line ends in the SLC
    logic               slcRemove;   // the line leaves the SLC at retirement
    logic               slcKeepDirty; // recorded when the entry finishes
    logic               slcUpdOwed;  // SLC write or removal at retirement
    // Granule Protection Check still to be answered; the entry cannot start.
    logic               gpcPending;
    // Direct transfers.
    logic               dctPlanned;  // the owner gets a forwarding snoop
    chi_snp_opcode_e    dctOpcode;
    logic               dmtUsed;     // memory returns the data to the Requester
    logic               dmtSep;      // by ReadNoSnpSep; the Home owes RespSepData
    logic               dwtUsed;     // write data goes straight to the SN-F
  } entry_t;

  // Victim-buffer entry. The key holds the evicted location, PAS included.
  typedef struct packed {
    logic               valid;
    logic [KEY_W-1:0]   key;
    logic [NUM_RNF-1:0] snpToSend;
    logic [NUM_RNF-1:0] snpPending;
    logic [NUM_RNF-1:0][3:0] snpGranules;
    logic               snpDirty;
    logic               dnBusy;
    logic               dnWriteDone;
  } victim_t;

  // ---------------------------------------------------------------------
  // Decode of the three inputs.
  // ---------------------------------------------------------------------
  chi_req_flit_t incomingReq;
  chi_rsp_flit_t incomingRsp;
  chi_dat_flit_t incomingDat;
  logic [KEY_W-1:0] incomingKey;

  function automatic logic [KEY_W-1:0] locationKey(
    input logic [CHI_MAX_ADDR_W-1:0] addr,
    input chi_pas_e pas
  );
    return {pas, addr[CFG.addrW-1:6]};
  endfunction

  function automatic logic [LINE_W-1:0] keyLine(input logic [KEY_W-1:0] key);
    return key[LINE_W-1:0];
  endfunction

  function automatic chi_pas_e keyPas(input logic [KEY_W-1:0] key);
    return chi_pas_e'(key[KEY_W-1:LINE_W]);
  endfunction

  function automatic logic isRnf(input logic [CHI_NODEID_SLOT_W-1:0] nodeId);
    logic match;
    match = 1'b0;
    for (int unsigned i = 0; i < NUM_RNF; i++)
      if ((i < CFG.numRnf) && (nodeId == RNF_NODE_IDS[i]))
        match = 1'b1;
    return match;
  endfunction

  function automatic logic [RNF_W-1:0] rnfIndex(
    input logic [CHI_NODEID_SLOT_W-1:0] nodeId
  );
    logic [RNF_W-1:0] index;
    index = '0;
    for (int unsigned i = 0; i < NUM_RNF; i++)
      if (nodeId == RNF_NODE_IDS[i])
        index = RNF_W'(i);
    return index;
  endfunction

  // Line-buffer byte positions of one DAT packet.
  function automatic logic [63:0] beatBytes(input logic [1:0] dataId);
    logic [63:0] mask;
    mask = '0;
    for (int unsigned b = 0; b < DAT_BYTES; b++)
      mask[int'(dataId) * 16 + b] = 1'b1;
    return mask;
  endfunction

  function automatic logic [63:0] beatEnables(
    input logic [1:0] dataId,
    input logic [63:0] be
  );
    logic [63:0] mask;
    mask = '0;
    for (int unsigned b = 0; b < DAT_BYTES; b++)
      mask[int'(dataId) * 16 + b] = be[b];
    return mask;
  endfunction

  // Granules one received packet accounts for, including the packets that
  // Limited Data Elision lets it stand in for (IHI 0050H B2.9.5).
  function automatic logic [3:0] packetGranules(
    input logic [1:0] dataId,
    input logic [1:0] numDat
  );
    logic [3:0] mask;
    mask = '0;
    for (int unsigned g = 0; g < 4; g++)
      if ((g >= int'(dataId))
          && (g < (int'(dataId) + (int'(numDat) + 1) * STEP)))
        mask[g] = 1'b1;
    return mask;
  endfunction

  function automatic logic [63:0] transferBytes(
    input logic [CHI_MAX_ADDR_W-1:0] addr,
    input logic [2:0] size
  );
    logic [63:0] mask;
    int unsigned bytes;
    int unsigned first;
    bytes = 32'd1 << size;
    first = 32'(addr[5:0]) & ~(bytes - 1);
    mask = '0;
    for (int unsigned b = 0; b < 64; b++)
      if ((b >= first) && (b < (first + bytes)))
        mask[b] = 1'b1;
    return mask;
  endfunction

  // A write that is not cancelled and not a failing exclusive will be
  // written; Comp and CompCMO wait for it when they have to.
  function automatic logic eNeedWritebackPossible(
    input entry_t e,
    input logic [63:0] wrBe
  );
    if (e.kind == HNF_KIND_COPYBACK)
      return respPassDirty(e.wrResp) && !e.wrCancel;
    if (e.kind == HNF_KIND_WRITE)
      return !e.wrCancel && !(e.exclStore && !e.exclPass);
    return 1'b0;
  endfunction

  // A WriteNoSnp is forwarded with its own address, Size and attributes,
  // because the location may be Device or Non-cacheable; everything else the
  // Home writes is a whole line.
  function automatic logic dnExactWrite(input entry_t e);
    return (e.kind == HNF_KIND_WRITE) && !isWriteUnique(e.req.opcode);
  endfunction

  // The forwarding snoop for a read (IHI 0050H B4.4, Table B4.26), or
  // SNP_SHARED when the read has none.
  function automatic chi_snp_opcode_e fwdSnoopFor(input chi_req_opcode_e op);
    case (op)
      REQ_READ_SHARED:           return SNP_SHARED_FWD;
      REQ_READ_CLEAN:            return SNP_CLEAN_FWD;
      REQ_READ_NOT_SHARED_DIRTY: return SNP_NOT_SHARED_DIRTY_FWD;
      REQ_READ_UNIQUE:           return SNP_UNIQUE_FWD;
      REQ_READ_PREFER_UNIQUE:    return SNP_PREFER_UNIQUE_FWD;
      REQ_READ_ONCE:             return SNP_ONCE_FWD;
      default:                   return SNP_SHARED;
    endcase
  endfunction

  // MemAttr[2] is Cacheable and MemAttr[1] Device (IHI 0050H B2.8.3); only
  // Cacheable, non-Device lines live in the SLC.
  function automatic logic slcCacheable(input chi_req_flit_t req);
    return req.memAttr[2] && !req.memAttr[1];
  endfunction

  // MemAttr[3] is the Allocate hint; slcAllocPolicy may ignore it.
  function automatic logic slcAllocHint(input chi_req_flit_t req);
    return slcCacheable(req)
           && ((CFG.slcAllocPolicy == SLC_ALLOC_CACHEABLE) || req.memAttr[3]);
  endfunction

  // Transactions the SLC gives the line up for before they start: cache
  // maintenance (it must reach memory or beyond), a read that asks for the
  // line to be dropped, and any access that may not be cached.
  function automatic logic slcBypass(input entry_t e);
    return (e.kind == HNF_KIND_CMO) || (e.cmo != HNF_CMO_NONE)
           || (e.req.opcode inside {REQ_READ_ONCE_CLEAN_INVALID,
                                    REQ_READ_ONCE_MAKE_INVALID})
           || ((e.kind inside {HNF_KIND_READ_ONCE, HNF_KIND_READ_NOSNP,
                               HNF_KIND_WRITE, HNF_KIND_WRITE_ZERO,
                               HNF_KIND_COPYBACK, HNF_KIND_ATOMIC})
               && !slcCacheable(e.req));
  endfunction

  always_comb begin
    incomingReq = unpackReqFlit(CFG, reqInFlit.payload[CHI_MAX_REQ_FLIT_W-1:0]);
    incomingRsp = unpackRspFlit(CFG, rspInFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    incomingDat = unpackDatFlit(CFG, datInFlit.payload[CHI_MAX_DAT_FLIT_W-1:0]);
    incomingKey = locationKey(incomingReq.addr, incomingReq.pas);
  end

  // ---------------------------------------------------------------------
  // State.
  // ---------------------------------------------------------------------
  entry_t entry [POS_DEPTH];
  victim_t victim [NUM_VB];
  logic [511:0] bufData [NUM_OWNERS];
  logic [63:0] bufWrBe [NUM_OWNERS];
  logic [63:0] bufSnpBe [NUM_OWNERS];
  logic [63:0] bufMemBe [NUM_OWNERS];
  logic [7:0] bufPoison [NUM_OWNERS];
  logic [NUM_OWNERS-1:0] bufDataErr;

  // chi_pos.
  logic posAllocValid;
  logic posAllocReady;
  logic [POS_W-1:0] posAllocIndex;
  logic [POS_DEPTH-1:0] posStartMask;
  logic [POS_DEPTH-1:0] posFreeMask;
  logic [POS_DEPTH-1:0] posActive;
  logic [POS_DEPTH-1:0] posStarted;
  logic [POS_W:0] posFreeCount;
  logic [POS_DEPTH-1:0][KEY_W-1:0] posKey;
  logic [POS_DEPTH-1:0][CHI_NODEID_SLOT_W-1:0] posRequester;
  logic [POS_DEPTH-1:0][CHI_TXNID_FLIT_W-1:0] posTxnId;
  chi_req_opcode_e [POS_DEPTH-1:0] posOpcode;
  chi_order_e [POS_DEPTH-1:0] posOrder;
  logic [POS_DEPTH-1:0][POS_DEPTH-1:0] posOlder;

  // chi_hazard.
  logic [NUM_VB-1:0] victimActive;
  logic [NUM_VB-1:0][KEY_W-1:0] victimKey;
  logic [POS_DEPTH-1:0] hazardLine;
  logic [POS_DEPTH-1:0] hazardOrder;
  logic [POS_DEPTH-1:0] hazardVictim;
  logic [POS_DEPTH-1:0] mayStart;

  // Admission and Request Retry.
  logic dropRequest;
  logic resourcesAvailable;
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
  logic [POS_W:0] posUnreservedCount;
  logic requestHandshake;
  entry_t allocEntry;

  // System Level Cache.
  localparam int unsigned NUM_LOCKS = POS_DEPTH + NUM_VB;
  logic slcLookupHit;
  logic slcLookupDirty;
  logic slcReadValid;
  logic [POS_W-1:0] slcReadEntry;
  logic [511:0] slcReadData;
  logic [7:0] slcReadPoison;
  logic slcReadCorrected;
  logic slcUpdateValid;
  logic [KEY_W-1:0] slcUpdateKey;
  logic slcUpdateRemove;
  logic slcUpdateDiscard;
  logic slcUpdateDirty;
  logic [511:0] slcUpdateData;
  logic [7:0] slcUpdatePoison;
  logic slcUpdateReady;
  logic slcUpdateFromRetire;
  logic [POS_W-1:0] slcUpdateEntry;
  logic [POS_W-1:0] slcUpdatePointer;
  logic slcVictimReady;
  logic slcVictimValid;
  logic [KEY_W-1:0] slcVictimKey;
  logic [511:0] slcVictimData;
  logic [7:0] slcVictimPoison;
  logic slcMaintWalking;
  logic slcEventFill;
  logic slcEventDirtyEviction;
  logic slcEventUncorrectable;
  logic [NUM_LOCKS-1:0] slcLockValid;
  logic [NUM_LOCKS-1:0][KEY_W-1:0] slcLockKey;
  // A start candidate the SLC must give up first: a CMO, a Combined write,
  // a ReadOnce*Invalid, or a Device or Non-cacheable access.
  logic slcFlushWant;
  logic [POS_DEPTH-1:0] eNeedSlcRead;
  logic [POS_DEPTH-1:0] eRawWriteback;
  // For the bound SLC assertions.
  logic slcUpdateCacheable;
  logic slcUpdateWroteBack;
  logic slcStartIsCmo;

  // Start (directory lookup and plan).
  logic startValid;
  logic [POS_W-1:0] startIndex;
  logic [POS_W-1:0] startPointer;
  entry_t planEntry;
  logic sfLookupHit;
  logic [NUM_RNF-1:0] sfLookupSharers;
  logic sfLookupOwnerValid;
  logic [RNF_W-1:0] sfLookupOwner;
  logic sfLookupAliasValid;
  logic [KEY_W-1:0] sfLookupAliasKey;
  // A physical-aliasing CMO first moves its line's other PASs to victim
  // entries, one per cycle, through the directory update port.
  logic sfAliasEvict;
  logic sfUpdateEvict;
  logic [POS_DEPTH-1:0] eAllPas;

  // Exclusive monitor.
  logic exclCommitValid;
  logic exclCommitLoad;
  logic exclCommitStore;
  logic exclCommitUpdate;
  logic exclRegisterBlocked;
  logic exclPass;
  logic exclRegistered;
  logic exclLpKnown;
  logic [clog2Min1(NUM_LP)-1:0] exclLpIndex;
  logic [POS_DEPTH-1:0] eMruFail;
  // Direct transfers.
  logic [POS_DEPTH-1:0] eDmtOk;
  logic [POS_DEPTH-1:0] eDctFwded;
  // For the bound direct-transfer assertions.
  logic [POS_DEPTH-1:0] eDmtUsed;
  logic [POS_DEPTH-1:0] eDmtSep;
  logic [POS_DEPTH-1:0] eDnReadDone;
  logic [POS_DEPTH-1:0] eDwtUsed;
  logic [POS_DEPTH-1:0] eDnWriting;
  logic [POS_DEPTH-1:0] eDctPlanned;
  logic [POS_DEPTH-1:0] eExclLoad;
  logic [POS_DEPTH-1:0] eExclStore;
  logic [POS_DEPTH-1:0] eSlcLine;

  // Stash decode of the starting entry.
  logic stashIsStash;
  logic stashIndependent;
  logic stashSeparateDone;
  logic stashUniqueDec;
  logic stashTargetValidDec;
  logic [NUM_RNF-1:0] stashTargetMaskDec;
  chi_snp_opcode_e stashTargetSnoopDec;
  logic stashLpidValidDec;
  logic [CHI_MAX_LPID_W-1:0] stashLpidDec;
  chi_req_opcode_e stashPullOpcodeDec;
  chi_resp_e stashPullRespDec;

  // Per-entry derived conditions.
  logic [POS_DEPTH-1:0] eSnpDone;
  logic [POS_DEPTH-1:0] eLineComplete;
  logic [POS_DEPTH-1:0] eOthersKeep;
  logic [POS_DEPTH-1:0] eMruHold;
  logic [POS_DEPTH-1:0] eDataPath;
  logic [POS_DEPTH-1:0] eNeedMemRead;
  logic [POS_DEPTH-1:0] eNeedWriteback;
  logic [POS_DEPTH-1:0] eNeedCmoFwd;
  logic [POS_DEPTH-1:0] eCompReady;
  logic [POS_DEPTH-1:0] eCompIsData;
  logic [POS_DEPTH-1:0] eCompCmoReady;
  logic [POS_DEPTH-1:0] eDbidReady;
  logic [POS_DEPTH-1:0] ePullReady;
  logic [POS_DEPTH-1:0] eAtomicReady;
  logic [POS_DEPTH-1:0] eAllDone;
  logic [POS_DEPTH-1:0] eReceiptOwed;
  logic [POS_DEPTH-1:0] eCompOwed;
  logic [POS_DEPTH-1:0][63:0] eWriteBe;
  logic [POS_DEPTH-1:0][3:0] eCompGranules;
  chi_resp_e [POS_DEPTH-1:0] eGrant;

  // Snoop engine.
  logic [NUM_OWNERS-1:0][NUM_RNF-1:0] ownerToSend;
  logic [NUM_OWNERS-1:0][NUM_RNF-1:0] ownerPending;
  logic snpIssueValid;
  logic snpIssueFire;
  logic [OWNER_W-1:0] snpIssueOwner;
  logic [RNF_W-1:0] snpIssueTarget;
  logic [SNP_COUNT_W-1:0] snpOutstanding;
  chi_noc_flit_t snpIssueFlit;
  // Per owner, for the snoop assertions: its location, whether it is live,
  // and which Snoopees have returned data to it.
  logic [NUM_OWNERS-1:0][KEY_W-1:0] ownerKey;
  logic [NUM_OWNERS-1:0] ownerLive;
  logic [NUM_OWNERS-1:0][NUM_RNF-1:0] ownerDataFrom;

  // Snoop responses.
  logic snpRspValid;
  logic [OWNER_W-1:0] snpRspOwner;
  logic [RNF_W-1:0] snpRspTarget;
  logic snpDatValid;
  logic [OWNER_W-1:0] snpDatOwner;
  logic [RNF_W-1:0] snpDatTarget;
  logic [3:0] snpDatGranules;
  logic snpDatLast;
  logic snpDatExpected;
  logic snpRspComplete;
  logic snpDatComplete;

  // Requester data and CompAck.
  logic wrDatValid;
  logic [POS_W-1:0] wrDatEntry;
  logic [3:0] wrDatGranules;
  logic compAckValid;
  logic [POS_W-1:0] compAckEntry;

  // Downstream trackers.
  logic [TRK_OWNERS-1:0] dnStartValid;
  chi_hnf_dn_e [TRK_OWNERS-1:0] dnStartKind;
  logic [TRK_OWNERS-1:0][3:0] dnStartGranules;
  logic [TRK_OWNERS-1:0] dnStartNoData;
  logic [TRK_OWNERS-1:0] dnStartWantReceipt;
  logic [TRK_OWNERS-1:0] dnBusy;
  logic [TRK_OWNERS-1:0] dnWaiting;
  logic [TRK_OWNERS-1:0] dnDone;
  // What each POS entry waits for from outside the Home, for the bound
  // completion assertions.
  logic [POS_DEPTH-1:0] liveWaitSnoop;
  logic [POS_DEPTH-1:0] liveWaitDownstream;
  logic [POS_DEPTH-1:0] liveWaitRequester;
  logic [TRK_OWNERS-1:0] dnResend;
  logic [TRK_OWNERS-1:0][3:0] dnResendType;
  logic dnReqValid;
  logic [TRK_W-1:0] dnReqOwner;
  logic dnReqCreditReturn;
  logic [3:0] dnReqCreditType;
  logic dnDatValid;
  logic [TRK_W-1:0] dnDatOwner;
  // GPT walker reads.
  logic [chi_pkg::CHI_MAX_ADDR_W-1:0] gptAddr;
  logic [511:0] gptBuf;
  logic gptErr;
  logic gptDatValid;
  // Granule Protection Check port.
  logic gpcAllocCheck;
  logic gpcRecheckValid;
  logic [POS_W-1:0] gpcRecheckEntry;
  logic [POS_W-1:0] gpcRecheckPointer;
  chi_hnf_err_e allocBaseErr;
  // For the bound GPC assertions.
  logic [POS_DEPTH-1:0] eGpcFailed;
  logic [POS_DEPTH-1:0] eGpcPending;
  logic [1:0] dnDatDataId;
  logic [CHI_RSP_DBID_SLOT_W-1:0] dnDatTxnId;
  logic snRspValid;
  logic snDatValid;
  logic memDatValid;
  logic [OWNER_W-1:0] memDatOwner;
  chi_noc_flit_t dnReqFlit;
  chi_noc_flit_t dnDatFlit;

  // Output stages.
  logic reqFifoReady;
  logic rspFifoReady;
  logic snpFifoReady;
  logic datFifoReady;
  logic rspPushValid;
  chi_noc_flit_t rspPushFlit;
  logic datPushValid;
  chi_noc_flit_t datPushFlit;
  logic [1:0] reqFifoCount;
  logic [1:0] rspFifoCount;
  logic [1:0] snpFifoCount;
  logic [1:0] datFifoCount;

  // Response arbitration.
  logic [POS_DEPTH-1:0] rspWant;
  logic rspEntryValid;
  logic [POS_W-1:0] rspEntry;
  logic [POS_W-1:0] rspPointer;
  logic rspGrantSend;
  logic rspEntrySend;
  logic [POS_DEPTH-1:0] datWant;
  logic datEntryValid;
  logic [POS_W-1:0] datEntry;
  logic [POS_W-1:0] datPointer;
  logic datTrackerTurn;
  logic datTrackerWins;
  logic datEntrySend;
  logic datTrackerSend;
  logic datEntryToPull;
  logic [1:0] datEntryDataId;

  // Atomic execution.
  logic atomicValid;
  logic [POS_W-1:0] atomicEntry;
  logic [2:0] atomicOperandSize;
  logic [63:0] atomicInitialWord;
  logic [63:0] atomicTransactionWord;
  logic [63:0] atomicCompareWord;
  logic atomicOpValid;
  logic atomicReturnsData;
  logic atomicUpdateEnable;
  logic [63:0] atomicUpdateWord;
  logic [63:0] atomicOriginalWord;

  // Directory update and victims.
  logic sfUpdateValid;
  logic [POS_W-1:0] sfUpdateEntry;
  logic [POS_W-1:0] sfUpdatePointer;
  logic [KEY_W-1:0] sfUpdateKey;
  logic [NUM_RNF-1:0] sfUpdateSharers;
  logic sfUpdateOwnerValid;
  logic [RNF_W-1:0] sfUpdateOwner;
  logic [SF_WAYS-1:0][KEY_W-1:0] sfUpdateSetKeys;
  logic [SF_WAYS-1:0] sfUpdateSetValid;
  logic [SF_WAYS-1:0] sfUpdateLockedWays;
  logic sfUpdateReady;
  logic sfVictimValid;
  logic [KEY_W-1:0] sfVictimKey;
  logic [NUM_RNF-1:0] sfVictimSharers;
  logic sfVictimOwnerValid;
  logic [RNF_W-1:0] sfVictimOwner;
  logic victimFree;
  logic [VB_W-1:0] victimFreeIndex;

  // ---------------------------------------------------------------------
  // Transaction table, hazards, directory, exclusive monitor, stash decode.
  // ---------------------------------------------------------------------
  chi_pos #(
    .CFG(CFG), .DEPTH(POS_DEPTH), .KEY_W(KEY_W), .RESERVE_W(RESERVE_W)
  ) pos (
    .clk, .resetn,
    .allocValid(posAllocValid), .allocCredited(!incomingReq.allowRetry),
    .reserved(retryCreditsOutstanding),
    .allocReady(posAllocReady), .allocIndex(posAllocIndex),
    .allocKey(incomingKey), .allocRequester(incomingReq.srcId),
    .allocTxnId(incomingReq.txnId), .allocOpcode(incomingReq.opcode),
    .allocOrder(incomingReq.order),
    .startMask(posStartMask), .freeMask(posFreeMask),
    .active(posActive), .started(posStarted), .freeCount(posFreeCount),
    .unreservedCount(posUnreservedCount), .key(posKey), .requester(posRequester), .txnId(posTxnId),
    .opcode(posOpcode), .order(posOrder), .older(posOlder)
  );

  always_comb begin
    for (int unsigned v = 0; v < NUM_VB; v++) begin
      victimActive[v] = victim[v].valid;
      victimKey[v] = victim[v].key;
    end
  end

  // CleanInvalidPoPA and its Combined forms act on their line in every PAS
  // (IHI 0050H B4.2.2.1).
  always_comb begin
    for (int unsigned i = 0; i < POS_DEPTH; i++)
      eAllPas[i] = posActive[i] && (entry[i].cmo == HNF_CMO_POPA)
                   && (entry[i].err == HNF_ERR_NONE);
  end

  chi_hazard #(
    .CFG(CFG), .DEPTH(POS_DEPTH), .KEY_W(KEY_W), .LINE_W(LINE_W),
    .NUM_VB(NUM_VB)
  ) hazard (
    .active(posActive), .key(posKey), .allPas(eAllPas),
    .requester(posRequester),
    .order(posOrder), .older(posOlder),
    .victimActive, .victimKey,
    .lineHazard(hazardLine), .orderHazard(hazardOrder),
    .victimHazard(hazardVictim), .mayStart
  );

  chi_snoop_filter #(
    .CFG(CFG),
    .ENTRIES((CFG.snpFilterEntries > 0) ? CFG.snpFilterEntries : 1),
    .WAYS(SF_WAYS), .NUM_RNF(NUM_RNF), .KEY_W(KEY_W), .LINE_W(LINE_W)
  ) snoop_filter (
    .clk, .resetn,
    .lookupKey(posKey[startIndex]),
    .lookupHit(sfLookupHit), .lookupSharers(sfLookupSharers),
    .lookupOwnerValid(sfLookupOwnerValid), .lookupOwner(sfLookupOwner),
    .lookupAliasValid(sfLookupAliasValid), .lookupAliasKey(sfLookupAliasKey),
    .updateValid(sfUpdateValid), .updateEvict(sfUpdateEvict),
    .updateKey(sfUpdateKey),
    .updateSharers(sfUpdateSharers), .updateOwnerValid(sfUpdateOwnerValid),
    .updateOwner(sfUpdateOwner),
    .updateSetKeys(sfUpdateSetKeys), .updateSetValid(sfUpdateSetValid),
    .updateLockedWays(sfUpdateLockedWays), .victimReady(victimFree),
    .updateReady(sfUpdateReady),
    .victimValid(sfVictimValid), .victimKey(sfVictimKey),
    .victimSharers(sfVictimSharers), .victimOwnerValid(sfVictimOwnerValid),
    .victimOwner(sfVictimOwner)
  );

  // Every location a transaction or a victim entry holds is locked in the
  // SLC, so what an entry learnt at its start stays true until it retires.
  always_comb begin
    for (int unsigned i = 0; i < POS_DEPTH; i++) begin
      slcLockValid[i] = posActive[i];
      slcLockKey[i] = posKey[i];
    end
    for (int unsigned v = 0; v < NUM_VB; v++) begin
      slcLockValid[POS_DEPTH + v] = victim[v].valid;
      slcLockKey[POS_DEPTH + v] = victim[v].key;
    end
  end

  if (CFG.slcEn) begin : slc_slice
    chi_slc #(
      .CFG(CFG), .KEY_W(KEY_W), .NUM_LOCKS(NUM_LOCKS)
    ) slc (
      .clk, .resetn,
      .lookupKey(posKey[startIndex]),
      .lookupHit(slcLookupHit), .lookupDirty(slcLookupDirty),
      .readValid(slcReadValid), .readKey(posKey[slcReadEntry]),
      .readData(slcReadData), .readPoison(slcReadPoison),
      .readCorrected(slcReadCorrected),
      .updateValid(slcUpdateValid), .updateKey(slcUpdateKey),
      .updateRemove(slcUpdateRemove), .updateDiscard(slcUpdateDiscard),
      .updateDirty(slcUpdateDirty), .updateData(slcUpdateData),
      .updatePoison(slcUpdatePoison), .updateReady(slcUpdateReady),
      .lockValid(slcLockValid), .lockKey(slcLockKey),
      .victimReady(slcVictimReady), .victimValid(slcVictimValid),
      .victimKey(slcVictimKey), .victimData(slcVictimData),
      .victimPoison(slcVictimPoison),
      .maintStart(slcMaintStart), .maintInvalidate(slcMaintInvalidate),
      .maintWalking(slcMaintWalking),
      .eventFill(slcEventFill), .eventDirtyEviction(slcEventDirtyEviction),
      .eventUncorrectable(slcEventUncorrectable)
    );
  end else begin : no_slc
    always_comb begin
      slcLookupHit = 1'b0;
      slcLookupDirty = 1'b0;
      slcReadData = '0;
      slcReadPoison = '0;
      slcReadCorrected = 1'b0;
      slcUpdateReady = 1'b1;
      slcVictimValid = 1'b0;
      slcVictimKey = '0;
      slcVictimData = '0;
      slcVictimPoison = '0;
      slcMaintWalking = 1'b0;
      slcEventFill = 1'b0;
      slcEventDirtyEviction = 1'b0;
      slcEventUncorrectable = 1'b0;
    end
  end

  // SLC read port: one entry per cycle takes the whole line into its buffer
  // as memory-level data.
  always_comb begin
    slcReadValid = 1'b0;
    slcReadEntry = '0;
    for (int unsigned i = 0; i < POS_DEPTH; i++)
      if (!slcReadValid && eNeedSlcRead[i]) begin
        slcReadValid = 1'b1;
        slcReadEntry = POS_W'(i);
      end
  end

  // SLC update port: a start candidate the SLC must give its line up for
  // first, else one retiring entry in rotation; the maintenance walk uses
  // the port when neither does. A dirty line leaving the SLC needs a victim
  // entry the directory is not taking this cycle.
  always_comb begin
    logic found;
    int unsigned candidate;
    entry_t e;
    found = 1'b0;
    slcUpdateEntry = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < POS_DEPTH; offset++) begin
      candidate = int'(slcUpdatePointer) + offset;
      if (candidate >= POS_DEPTH)
        candidate = candidate - POS_DEPTH;
      if (!found && (entry[candidate].phase == PH_RETIRE)
          && entry[candidate].slcUpdOwed) begin
        found = 1'b1;
        slcUpdateEntry = POS_W'(candidate);
      end
    end
    e = entry[slcUpdateEntry];
    slcUpdateFromRetire = found && !slcFlushWant;
    slcUpdateValid = slcFlushWant || found;
    slcUpdateKey = slcFlushWant ? posKey[startIndex] : posKey[slcUpdateEntry];
    // A flush writes the SLC's own line back; a retiring entry that removes
    // the line has already written the latest data to memory itself.
    slcUpdateRemove = slcFlushWant || e.slcRemove;
    slcUpdateDiscard = !slcFlushWant && e.slcRemove;
    slcUpdateDirty = e.slcKeepDirty;
    slcUpdateData = bufData[slcUpdateEntry];
    slcUpdatePoison = bufPoison[slcUpdateEntry];
    slcVictimReady = victimFree && !(sfVictimValid && sfUpdateValid && sfUpdateReady);
    slcUpdateCacheable = slcCacheable(e.req);
    slcUpdateWroteBack = e.dnWriteDone || !e.slcKeepDirty;
    slcStartIsCmo = entry[startIndex].kind == HNF_KIND_CMO;
  end

  // The monitor commits once per start, after chi_hazard has ordered the
  // entry behind every older transaction to its location (IHI 0050H B6.2).
  // Exclusive Loads register, Exclusive Stores are checked, and a write to a
  // Non-snoopable location by another LP resets the System monitors of the
  // location (B6.2.4). Excl is the SnoopMe bit in an atomic.
  always_comb begin
    entry_t starting;
    logic excl;
    logic noSnpWrite;
    starting = entry[startIndex];
    excl = starting.req.exclOrSnoopMeOrCah && (starting.kind != HNF_KIND_ATOMIC);
    noSnpWrite = ((starting.kind == HNF_KIND_WRITE)
                  && !isWriteUnique(starting.req.opcode))
                 || (starting.req.opcode inside {REQ_WRITE_NO_SNP_ZERO,
                                                 REQ_WRITE_NO_SNP_DEF})
                 || ((starting.kind == HNF_KIND_ATOMIC)
                     && !starting.req.snpAttrOrDoDwt);
    exclCommitLoad = excl
                     && (starting.req.opcode inside {
                           REQ_READ_SHARED, REQ_READ_CLEAN,
                           REQ_READ_NOT_SHARED_DIRTY, REQ_READ_PREFER_UNIQUE,
                           REQ_READ_NO_SNP});
    exclCommitStore = excl
                      && (starting.req.opcode inside {
                            REQ_CLEAN_UNIQUE, REQ_MAKE_READ_UNIQUE,
                            REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL});
    exclCommitUpdate = !excl && noSnpWrite;
    exclCommitValid = startValid && (starting.err == HNF_ERR_NONE) && CFG.exclEn
                      && (exclCommitLoad || exclCommitStore || exclCommitUpdate);
    // While a passing Exclusive Store from another LP waits for CompAck, no
    // other LP registers (B6.2.1).
    exclRegisterBlocked = 1'b0;
    for (int unsigned i = 0; i < POS_DEPTH; i++)
      if (posActive[i] && entry[i].exclStore && entry[i].exclPass
          && entry[i].compAckOwed
          && !((entry[i].req.srcId == starting.req.srcId)
               && (entry[i].req.groupIdOrLpid == starting.req.groupIdOrLpid)))
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
    .commitSrcId(entry[startIndex].req.srcId),
    .commitLpid(entry[startIndex].req.groupIdOrLpid),
    .commitKey(posKey[startIndex]),
    .registerBlocked(exclRegisterBlocked),
    .pass(exclPass), .registered(exclRegistered),
    .lpKnown(exclLpKnown), .lpIndex(exclLpIndex)
  );

  chi_stash_ctrl #(
    .CFG(CFG), .NUM_RNF(NUM_RNF), .RNF_NODE_IDS(RNF_NODE_IDS)
  ) stash_ctrl (
    .requestOpcode(entry[startIndex].req.opcode),
    .requestStashNidValid(entry[startIndex].req.stashNidValidOrEndianOrDeep),
    .requestStashNid(entry[startIndex].req.returnNidOrStashNidOrDataTarget),
    .requestStashLpidSlot(entry[startIndex].req.returnTxnIdOrStashLpid),
    .homeHasLatestCopy(!sfLookupOwnerValid),
    .isStash(stashIsStash), .isIndependentStash(stashIndependent),
    .isSeparateStashDone(stashSeparateDone), .isUniqueStash(stashUniqueDec),
    .targetValid(stashTargetValidDec), .targetMask(stashTargetMaskDec),
    .targetSnoopOpcode(stashTargetSnoopDec),
    .stashLpidValid(stashLpidValidDec), .stashLpid(stashLpidDec),
    .dataPullOpcode(stashPullOpcodeDec), .dataPullResp(stashPullRespDec)
  );

  // ---------------------------------------------------------------------
  // Admission. A request is allocated, dropped, or given RetryAck. A
  // location conflict is no reason to refuse it: it is allocated and waits
  // in chi_hazard, so requests to other locations behind it keep flowing.
  // ---------------------------------------------------------------------
  always_comb begin
    // PCrdReturn carries no transaction, and PrefetchTgt has no response and
    // must never be retried (IHI 0050H B2.5.6, B2.10.2.1).
    dropRequest = (incomingReq.opcode == REQ_PCRD_RETURN)
                  || (incomingReq.opcode == REQ_PREFETCH_TGT);
    resourcesAvailable = dropRequest || posAllocReady;
    if (isAtomicOpcode(incomingReq.opcode))
      retryCategory = 2'd3;
    else if (hnfKind(incomingReq.opcode) inside {
               HNF_KIND_WRITE, HNF_KIND_WRITE_ZERO, HNF_KIND_WRITE_DEF,
               HNF_KIND_COPYBACK})
      retryCategory = 2'd1;
    else if (hnfKind(incomingReq.opcode) inside {
               HNF_KIND_READ, HNF_KIND_DATALESS, HNF_KIND_CMO,
               HNF_KIND_STASH_ONCE})
      retryCategory = 2'd2;
    else
      retryCategory = 2'd0;
    // A request that finds no entry it may use is retried, so the REQ input
    // is always consumed (design specification, Section 9.7). Only a request
    // from a node outside REQUESTER_NODE_IDS, or one claiming a P-Credit the
    // Home never granted, is held with back-pressure instead.
    retryAckWant = reqInValid && !resourcesAvailable && retryAck;
    retryHandshake = retryAckWant && rspFifoReady;
    requestHandshake = reqInValid && resourcesAvailable;
    posAllocValid = requestHandshake && !dropRequest;
  end

  always_comb begin
    reqInReady = resourcesAvailable || retryHandshake;
  end

  // A request the Requester-side SAM refused, or one in a PAS this
  // configuration does not support, completes with NDERR and touches
  // nothing (IHI 0050H B9.1.1, Table B13.47).
  always_comb begin
    if (reqInFlit.decodeErr == NOC_ERR_ADDRESS)
      allocBaseErr = HNF_ERR_ADDRESS;
    else if ((reqInFlit.decodeErr == NOC_ERR_PAS)
             || !pasLegal(CFG, incomingReq.pas))
      allocBaseErr = HNF_ERR_PAS;
    else if (hnfKind(incomingReq.opcode) == HNF_KIND_ILLEGAL)
      allocBaseErr = HNF_ERR_UNSUPPORTED;
    else
      allocBaseErr = HNF_ERR_NONE;
  end

  // The GPC port checks the request being allocated, and otherwise one
  // waiting entry whose answer the walker did not have yet.
  always_comb begin
    logic found;
    int unsigned candidate;
    gpcAllocCheck = (CFG.gpcMode != GPC_NONE) && posAllocValid
                    && (allocBaseErr == HNF_ERR_NONE);
    found = 1'b0;
    gpcRecheckEntry = '0;
    candidate = 0;
    if ((CFG.gpcMode != GPC_NONE) && !gpcAllocCheck)
      for (int unsigned offset = 0; offset < POS_DEPTH; offset++) begin
        candidate = int'(gpcRecheckPointer) + offset;
        if (candidate >= POS_DEPTH)
          candidate = candidate - POS_DEPTH;
        if (!found && posActive[candidate] && entry[candidate].gpcPending) begin
          found = 1'b1;
          gpcRecheckEntry = POS_W'(candidate);
        end
      end
    gpcRecheckValid = found;
    gpcCheckValid = gpcAllocCheck || gpcRecheckValid;
    gpcCheckAddr = gpcAllocCheck ? incomingReq.addr : entry[gpcRecheckEntry].req.addr;
    gpcCheckPas = gpcAllocCheck ? incomingReq.pas : entry[gpcRecheckEntry].req.pas;
    gpcCheckSrcId = gpcAllocCheck ? incomingReq.srcId
                                  : entry[gpcRecheckEntry].req.srcId;
  end

  // The entry a request starts as.
  always_comb begin
    chi_hnf_kind_e kind;
    allocEntry = '0;
    kind = hnfKind(incomingReq.opcode);
    allocEntry.phase = PH_WAIT;
    allocEntry.req = incomingReq;
    allocEntry.kind = kind;
    allocEntry.cmo = hnfCmo(incomingReq.opcode);
    allocEntry.err = allocBaseErr;
    // Granule protection is checked for every request without another error
    // (IHI 0050H B9.1.1: a protected granule is an illegal access). An
    // answer not yet available holds the entry until the walker has it.
    if (gpcAllocCheck) begin
      if (!gpcCheckDone)
        allocEntry.gpcPending = 1'b1;
      else if (gpcCheckFail)
        allocEntry.err = HNF_ERR_GPC;
    end
    allocEntry.reqIsRnf = isRnf(incomingReq.srcId);
    allocEntry.reqRnf = rnfIndex(incomingReq.srcId);
    allocEntry.snpOpcode = SNP_SHARED;
    allocEntry.stashOpcode = SNP_STASH_SHARED;
    allocEntry.wrResp = RESP_I;
    allocEntry.pullResp = RESP_I;
    allocEntry.dnKind = HNF_DN_READ;
    // An ordered ReadNoSnp or ReadOnce* learns from ReadReceipt that the
    // Home has accepted it and will keep it in order (IHI 0050H B2.7.5.1).
    // The POS is that ordering point, so the receipt goes out as soon as the
    // request is allocated.
    allocEntry.receiptOwed =
      ((kind == HNF_KIND_READ_NOSNP) || (kind == HNF_KIND_READ_ONCE))
      && ((incomingReq.order == ORDER_REQUEST_ORDER)
          || (incomingReq.order == ORDER_ENDPOINT));
  end

  // A grant reserves an entry for the request it invites. It needs an
  // unreserved free entry beyond any an uncredited request takes this cycle,
  // and the Home keeps at most retryRecords credits outstanding.
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

  // ---------------------------------------------------------------------
  // Start: one waiting entry per cycle reads the directory and is given its
  // plan. Round-robin among entries that chi_hazard lets start.
  // ---------------------------------------------------------------------
  always_comb begin
    logic found;
    int unsigned candidate;
    found = 1'b0;
    startIndex = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < POS_DEPTH; offset++) begin
      candidate = int'(startPointer) + offset;
      if (candidate >= POS_DEPTH)
        candidate = candidate - POS_DEPTH;
      if (!found && (entry[candidate].phase == PH_WAIT) && mayStart[candidate]
          && !entry[candidate].gpcPending) begin
        found = 1'b1;
        startIndex = POS_W'(candidate);
      end
    end
    // A physical-aliasing CMO starts only once no other PAS of its line is
    // in the directory; until then it evicts one per cycle instead.
    sfAliasEvict = found && eAllPas[startIndex] && sfLookupAliasValid;
    slcFlushWant = found && !sfAliasEvict && CFG.slcEn
                   && (entry[startIndex].err == HNF_ERR_NONE)
                   && slcLookupHit && slcBypass(entry[startIndex]);
    startValid = found && !sfAliasEvict && !slcFlushWant;
    posStartMask = '0;
    if (startValid)
      posStartMask[startIndex] = 1'b1;
  end

  // The plan of the starting entry: who to snoop and with which snoop,
  // which responses are owed, and the exclusive and stash outcome. Memory
  // reads and writes are not planned here; they follow from what the snoops
  // return (see the derived conditions below).
  always_comb begin
    entry_t e;
    logic [NUM_RNF-1:0] reqBit;
    logic [NUM_RNF-1:0] others;
    logic [NUM_RNF-1:0] ownerBit;
    logic [NUM_RNF-1:0] targets;
    logic ownerElsewhere;
    logic stashOk;
    e = entry[startIndex];
    reqBit = '0;
    if (e.reqIsRnf)
      reqBit[e.reqRnf] = 1'b1;
    others = sfLookupHit ? (sfLookupSharers & ~reqBit) : '0;
    ownerBit = '0;
    if (sfLookupHit && sfLookupOwnerValid)
      ownerBit[sfLookupOwner] = 1'b1;
    ownerElsewhere = sfLookupHit && sfLookupOwnerValid
                     && !(e.reqIsRnf && (sfLookupOwner == e.reqRnf));

    e.phase = PH_RUN;
    e.sfHit = sfLookupHit;
    e.sfSharers = sfLookupHit ? sfLookupSharers : '0;
    e.sfOwnerValid = sfLookupHit && sfLookupOwnerValid;
    e.sfOwner = sfLookupOwner;
    e.snpOpcode = snoopForRequest(e.req.opcode, CFG.mteEn);
    e.snpRetToSrc = 1'b0;
    e.exclLoad = exclCommitValid && exclCommitLoad && exclRegistered;
    e.exclStore = exclCommitValid && exclCommitStore;
    e.exclPass = exclCommitValid && exclCommitStore && exclPass;
    targets = '0;

    if (e.err == HNF_ERR_NONE) begin
      case (e.kind)
        HNF_KIND_READ: begin
          if ((e.req.opcode == REQ_MAKE_READ_UNIQUE) && e.exclStore
              && !e.exclPass) begin
            // A failing MakeReadUnique(Excl) upgrades nothing and
            // invalidates nothing: Comp_SC if the Requester still holds the
            // line, otherwise its data in SC got with a non-invalidating
            // snoop of a possible owner (IHI 0050H B6.3.1.1).
            targets = (e.reqIsRnf && sfLookupHit && sfLookupSharers[e.reqRnf])
                      ? '0 : (ownerElsewhere ? ownerBit : '0);
            e.snpOpcode = SNP_SHARED;
            e.snpRetToSrc = 1'b1;
          end else if ((e.req.opcode == REQ_MAKE_READ_UNIQUE) && e.reqIsRnf
              && sfLookupHit && sfLookupSharers[e.reqRnf]) begin
            // The Requester still holds the line, so the other copies are
            // invalidated and a Comp without data upgrades it
            // (IHI 0050H B2.3.1.1 alt 6).
            targets = others;
          end else if ((e.req.opcode == REQ_READ_UNIQUE)
                       || (e.req.opcode == REQ_MAKE_READ_UNIQUE)) begin
            targets = others;
            e.snpOpcode = SNP_UNIQUE;
            e.snpRetToSrc = 1'b1;
          end else begin
            // A shared read only needs the copy that may be Dirty or
            // Unique; Shared Clean copies stay as they are
            // (IHI 0050H B4.4.1).
            targets = ownerElsewhere ? ownerBit : '0;
            e.snpRetToSrc = 1'b1;
          end
          e.compOwed = 1'b1;
          e.compAckOwed = e.req.expCompAck;
        end
        HNF_KIND_READ_ONCE: begin
          targets = ownerElsewhere ? ownerBit : '0;
          e.snpRetToSrc = 1'b1;
          e.compOwed = 1'b1;
          e.compAckOwed = e.req.expCompAck;
        end
        HNF_KIND_READ_NOSNP: begin
          e.compOwed = 1'b1;
          e.compAckOwed = e.req.expCompAck;
        end
        HNF_KIND_DATALESS: begin
          // A failing Exclusive CleanUnique propagates nothing: no snoop and
          // no upgrade (IHI 0050H B6.2.1, Table B6.2).
          if ((e.req.opcode != REQ_EVICT) && !(e.exclStore && !e.exclPass))
            targets = others;
          e.compOwed = 1'b1;
          e.compAckOwed = e.req.expCompAck;
        end
        HNF_KIND_CMO: begin
          // Only a copy that may be Dirty needs cleaning; an invalidating
          // CMO removes every copy but the Requester's, which the Requester
          // has already dealt with (IHI 0050H B4.2.2.1, Table B4.11).
          if (cmoInvalidates(e.cmo))
            targets = others;
          else
            targets = ownerElsewhere ? ownerBit : '0;
          e.compOwed = 1'b1;
        end
        HNF_KIND_STASH_ONCE: begin
          // Stash only when memory holds the latest copy, so the implied
          // read of a Data Pull can be served from memory; a Unique stash
          // also needs no other copy to exist. Stashing is a hint, so
          // skipping it is always legal (IHI 0050H B7.4).
          stashOk = stashTargetValidDec && !ownerElsewhere
                    && (!stashUniqueDec
                        || ((others & ~stashTargetMaskDec) == '0));
          e.stashValid = stashOk;
          e.stashTarget = rnfIndex(e.req.returnNidOrStashNidOrDataTarget);
          e.stashOpcode = stashTargetSnoopDec;
          e.stashLpidValid = stashLpidValidDec;
          e.stashLpid = stashLpidDec;
          e.stashUnique = stashUniqueDec;
          e.pullResp = stashPullRespDec;
          targets = stashOk ? stashTargetMaskDec : '0;
          e.compOwed = 1'b1;
        end
        HNF_KIND_WRITE: begin
          if (isWriteUnique(e.req.opcode))
            targets = others;
          if (isStashWrite(e.req.opcode) && stashTargetValidDec) begin
            e.stashValid = 1'b1;
            e.stashTarget = rnfIndex(e.req.returnNidOrStashNidOrDataTarget);
            e.stashOpcode = stashTargetSnoopDec;
            e.stashLpidValid = stashLpidValidDec;
            e.stashLpid = stashLpidDec;
            e.stashUnique = 1'b1;
            e.pullResp = RESP_UC_UD;
            targets = targets | stashTargetMaskDec;
          end
          e.dbidOwed = 1'b1;
          // With nothing to snoop and an early write acknowledge allowed,
          // the Home is the point of serialization and can combine the
          // completion with the data request (IHI 0050H B2.3.2.1 alt 2a2).
          e.dbidWithComp = (targets == '0) && e.req.memAttr[0]
                           && (e.cmo == HNF_CMO_NONE) && !e.stashValid
                           && !e.exclStore;
          e.compOwed = !e.dbidWithComp;
          e.compCmoOwed = e.cmo != HNF_CMO_NONE;
          e.wrOwed = 1'b1;
          e.compAckOwed = e.req.expCompAck;
        end
        HNF_KIND_WRITE_ZERO: begin
          if (isWriteUnique(e.req.opcode))
            targets = others;
          e.dbidOwed = 1'b1;
          e.dbidWithComp = 1'b1;
          e.compAckOwed = e.req.expCompAck;
        end
        HNF_KIND_WRITE_DEF: begin
          // An HN-F does not forward WriteNoSnpDef; it answers
          // OK/Unsupported and the Requester completes the write flow
          // (IHI 0050H B4.5.1.3.1).
          e.dbidOwed = 1'b1;
          e.dbidWithComp = 1'b1;
          e.wrOwed = 1'b1;
          e.compAckOwed = e.req.expCompAck;
        end
        HNF_KIND_COPYBACK: begin
          // The Home completes a CopyBack itself with CompDBIDResp and takes
          // the data (IHI 0050H B2.3.2.3); DWT never applies to it
          // (IHI 0050H B13.10.24).
          e.dbidOwed = 1'b1;
          e.dbidWithComp = 1'b1;
          e.compCmoOwed = e.cmo != HNF_CMO_NONE;
          e.wrOwed = 1'b1;
          e.compAckOwed = e.req.expCompAck;
        end
        HNF_KIND_ATOMIC: begin
          targets = others;
          // SnoopMe asks the Home to snoop the Requester as well
          // (IHI 0050H B13.10.33).
          if (e.req.exclOrSnoopMeOrCah && e.reqIsRnf && sfLookupHit
              && sfLookupSharers[e.reqRnf])
            targets = targets | reqBit;
          e.snpRetToSrc = 1'b1;
          e.dbidOwed = 1'b1;
          e.compOwed = 1'b1;
          e.wrOwed = 1'b1;
        end
        default: begin
          e.compOwed = 1'b1;
        end
      endcase
    end else begin
      // An error completes with the transaction's own message structure and
      // NDERR, and touches nothing else.
      case (e.kind)
        HNF_KIND_WRITE, HNF_KIND_WRITE_DEF, HNF_KIND_COPYBACK: begin
          e.dbidOwed = 1'b1;
          e.dbidWithComp = 1'b1;
          e.compCmoOwed = e.cmo != HNF_CMO_NONE;
          e.wrOwed = 1'b1;
        end
        HNF_KIND_WRITE_ZERO: begin
          e.dbidOwed = 1'b1;
          e.dbidWithComp = 1'b1;
        end
        HNF_KIND_ATOMIC: begin
          e.dbidOwed = 1'b1;
          e.compOwed = 1'b1;
          e.wrOwed = 1'b1;
        end
        default:
          e.compOwed = 1'b1;
      endcase
      e.compAckOwed = e.req.expCompAck;
    end

    // System Level Cache (Section 9.10). A start never happens on a line the
    // SLC has to give up first (slcFlushWant), so a hit here is a line the
    // entry may use and update.
    e.slcHit = CFG.slcEn && slcLookupHit;
    e.slcDirty = CFG.slcEn && slcLookupHit && slcLookupDirty;
    e.slcKeep = 1'b0;
    e.slcRemove = 1'b0;
    if (CFG.slcEn && (e.err == HNF_ERR_NONE) && !slcBypass(e)) begin
      case (e.kind)
        HNF_KIND_READ:
          if (e.slcHit) begin
            // Exclusive of RN-F caches, a line an RN-F is given leaves the
            // SLC; otherwise the SLC keeps it.
            e.slcRemove = CFG.slcInclusion == SLC_EXCLUSIVE_OF_RNF;
            e.slcKeep = CFG.slcInclusion == SLC_NON_INCLUSIVE;
          end else begin
            e.slcKeep = (CFG.slcInclusion == SLC_NON_INCLUSIVE)
                        && slcAllocHint(e.req) && policy.slcAllocRead;
          end
        HNF_KIND_READ_ONCE, HNF_KIND_READ_NOSNP:
          e.slcKeep = e.slcHit || (slcAllocHint(e.req) && policy.slcAllocRead);
        HNF_KIND_DATALESS:
          e.slcKeep = e.slcHit;
        HNF_KIND_WRITE:
          // A partial write allocates only on a hit, where the SLC supplies
          // the rest of the line. A stash with no target may allocate
          // instead (IHI 0050H B7.4.2).
          e.slcKeep = !(e.exclStore && !e.exclPass)
                      && (e.slcHit
                          || (isFullLineWrite(e.req.opcode)
                              && ((slcAllocHint(e.req) && policy.slcAllocWrite)
                                  || (isStashWrite(e.req.opcode)
                                      && !e.stashValid && slcCacheable(e.req)
                                      && policy.slcAllocStash))));
        HNF_KIND_WRITE_ZERO:
          e.slcKeep = e.slcHit || (slcAllocHint(e.req) && policy.slcAllocWrite);
        HNF_KIND_COPYBACK:
          e.slcKeep = e.slcHit
                      || (isFullLineWrite(e.req.opcode) && slcCacheable(e.req)
                          && policy.slcAllocEvict);
        HNF_KIND_ATOMIC:
          e.slcKeep = e.slcHit || (slcAllocHint(e.req) && policy.slcAllocWrite);
        HNF_KIND_STASH_ONCE:
          // A StashOnce with no target to stash into may bring the line into
          // the SLC instead (IHI 0050H B7.4.2).
          e.slcKeep = e.slcHit
                      || (!e.stashValid && !ownerElsewhere && slcCacheable(e.req)
                          && policy.slcAllocStash);
        default: begin
        end
      endcase
    end

    // DCT: the owner forwards the line to the Requester (Table B4.26). Not
    // for an Exclusive Load (B6.3.1), an ordered or partial ReadOnce
    // (Table B2.6), or an allocating read that sends no CompAck; never with
    // MTE, whose tags this Home does not carry.
    e.dctPlanned = 1'b0;
    e.dctOpcode = SNP_SHARED;
    if ((e.err == HNF_ERR_NONE) && CFG.dctEn && policy.dctEn && !CFG.mteEn
        && ownerElsewhere && RNF_DCT_CAP[sfLookupOwner] && !e.exclLoad
        && !e.exclStore && !e.stashValid
        && (fwdSnoopFor(e.req.opcode) != SNP_SHARED)
        && (e.req.order == ORDER_NONE)
        && (((e.kind == HNF_KIND_READ) && e.req.expCompAck)
            || ((e.kind == HNF_KIND_READ_ONCE) && (e.req.size == 3'd6)))
        && targets[sfLookupOwner]) begin
      e.dctPlanned = 1'b1;
      e.dctOpcode = fwdSnoopFor(e.req.opcode);
    end

    // DWT: a WriteNoSnp that no exclusive check, SLC line or ordering keeps
    // at the Home sends its data straight to the SN-F (B2.3.2.1 alt 1,
    // B6.3.1). The SN-F asks the Requester for the data; the Home sends Comp.
    e.dwtUsed = (e.err == HNF_ERR_NONE) && CFG.dwtEn && policy.dwtEn && SN_DWT_CAP
                && (e.kind == HNF_KIND_WRITE) && !isWriteUnique(e.req.opcode)
                && (e.cmo == HNF_CMO_NONE) && !e.exclStore && !e.slcHit
                && !e.slcKeep && (e.req.order == ORDER_NONE)
                && !e.req.expCompAck && (targets == '0);
    if (e.dwtUsed) begin
      e.dbidOwed = 1'b0;
      e.dbidWithComp = 1'b0;
      e.compOwed = 1'b1;
      e.wrOwed = 1'b0;
    end

    e.snpTargets = targets;
    e.snpToSend = targets;
    e.snpPending = '0;
    e.sfUpdOwed = (e.err == HNF_ERR_NONE)
                  && (e.kind inside {HNF_KIND_READ, HNF_KIND_READ_ONCE,
                                     HNF_KIND_DATALESS, HNF_KIND_CMO,
                                     HNF_KIND_STASH_ONCE, HNF_KIND_WRITE,
                                     HNF_KIND_WRITE_ZERO, HNF_KIND_COPYBACK,
                                     HNF_KIND_ATOMIC})
                  && (e.sfHit || e.reqIsRnf || e.stashValid);
    planEntry = e;
  end

  // ---------------------------------------------------------------------
  // Derived per-entry conditions. Each obligation becomes ready once the
  // obligations it depends on are met.
  // ---------------------------------------------------------------------
  always_comb begin
    for (int unsigned i = 0; i < POS_DEPTH; i++) begin
      entry_t e;
      logic [63:0] valid;
      logic [63:0] needed;
      logic takesDirty;
      e = entry[i];
      valid = bufWrBe[i] | bufSnpBe[i] | bufMemBe[i];
      needed = (e.kind == HNF_KIND_READ_NOSNP)
               ? transferBytes(e.req.addr, e.req.size) : ALL_BYTES;
      eSnpDone[i] = (e.snpToSend == '0) && (e.snpPending == '0);
      eLineComplete[i] = (needed & ~valid) == '0;
      eOthersKeep[i] = ((e.sfSharers & ~e.snpTargets
                         & ~(e.reqIsRnf ? (NUM_RNF'(1) << e.reqRnf) : '0))
                        != '0)
                       || (e.snpKeep != '0);
      eMruHold[i] = (e.req.opcode == REQ_MAKE_READ_UNIQUE) && e.reqIsRnf
                    && e.sfHit && e.sfSharers[e.reqRnf];
      eMruFail[i] = (e.req.opcode == REQ_MAKE_READ_UNIQUE) && e.exclStore
                    && !e.exclPass;
      // The Home supplies read data unless a Snoopee forwarded it.
      eDataPath[i] = (e.err == HNF_ERR_NONE) && !e.snpFwded
                     && (((e.kind == HNF_KIND_READ) && !eMruHold[i])
                         || (e.kind == HNF_KIND_READ_ONCE)
                         || (e.kind == HNF_KIND_READ_NOSNP));
      // A forwarding Snoopee chose the Requester's state and settled the
      // Dirty responsibility with it (FwdState[2]); Dirty data it returned
      // to the Home is the Home's to write back.
      takesDirty = !e.snpFwded && !eMruFail[i]
                   && readTakesDirty(e.req.opcode, eOthersKeep[i]);
      eGrant[i] = e.snpFwded ? e.snpFwdState
                  : (eMruFail[i] ? RESP_SC
                                 : readCompResp(e.req.opcode, eOthersKeep[i],
                                                e.snpDirty && takesDirty));
      eDctFwded[i] = e.dctPlanned && e.snpFwded;

      // DMT: memory's CompData or DataSepResp is always UC (IHI 0050H
      // B4.7.1, B4.5.1.1), so only a read the Requester may hold Unique uses
      // it, once its snoops are done, with nothing at the Home to merge, a
      // CompAck to close it, no Exclusive (B6.3.1; conservatively also no
      // MakeReadUnique(Excl)), and no SLC copy or fill the policy keeps
      // (slcFillOnDmtMiss).
      eDmtOk[i] = (e.err == HNF_ERR_NONE) && CFG.dmtEn && policy.dmtEn && SN_DMT_CAP
                  && (e.kind == HNF_KIND_READ) && !eMruHold[i] && !eMruFail[i]
                  && e.req.expCompAck && (e.req.order == ORDER_NONE)
                  && !e.exclLoad && !e.exclStore && !e.slcHit
                  && (!e.slcKeep || !CFG.slcFillOnDmtMiss)
                  && ((bufWrBe[i] | bufSnpBe[i]) == '0) && !e.snpFwded
                  && !e.pullValid && (eGrant[i] == RESP_UC_UD);

      // Memory is read when the snoops did not bring a whole line: for a
      // read, for the initial value of an atomic, and for the line a Data
      // Pull asks for.
      eNeedMemRead[i] = (e.phase == PH_RUN) && !e.dnReadDone && eSnpDone[i]
                        && !eLineComplete[i]
                        && (eDataPath[i]
                            || ((e.kind == HNF_KIND_ATOMIC)
                                && (e.err == HNF_ERR_NONE))
                            || (e.pullValid
                                && ((e.kind == HNF_KIND_STASH_ONCE)
                                    || e.dnWriteDone))
                            // An SLC fill for a StashOnce with no target.
                            || (e.slcKeep && !e.slcHit
                                && (e.kind == HNF_KIND_STASH_ONCE))
                            // The SLC line completes a partial update of it.
                            || (e.slcKeep && e.slcHit
                                && ((bufWrBe[i] | bufSnpBe[i]) != '0))
                            // A removal writes the SLC's data back itself.
                            || (e.slcRemove && e.slcDirty));
      eNeedSlcRead[i] = eNeedMemRead[i] && e.slcHit && !e.dnBusy;

      // Data that has to reach memory: Dirty snoop data the Requester does
      // not take, the data of a write, the result of an atomic.
      eWriteBe[i] = bufSnpBe[i];
      eNeedWriteback[i] = 1'b0;
      if ((e.phase == PH_RUN) && (e.err == HNF_ERR_NONE) && !e.dnWriteDone) begin
        case (e.kind)
          HNF_KIND_READ, HNF_KIND_READ_ONCE, HNF_KIND_READ_NOSNP:
            eNeedWriteback[i] = eSnpDone[i] && e.snpDirty && !takesDirty
                                && (!e.snpPtl || eLineComplete[i]);
          HNF_KIND_DATALESS:
            // MakeUnique lets the Dirty copy be discarded; CleanUnique and
            // Evict do not (IHI 0050H B4.2.2).
            eNeedWriteback[i] = eSnpDone[i] && e.snpDirty
                                && (e.req.opcode != REQ_MAKE_UNIQUE);
          HNF_KIND_CMO:
            // MakeInvalid permits Dirty data to be discarded.
            eNeedWriteback[i] = eSnpDone[i] && e.snpDirty
                                && (e.cmo != HNF_CMO_MAKE_INVALID);
          HNF_KIND_WRITE: begin
            eWriteBe[i] = bufWrBe[i] | bufSnpBe[i];
            // A failing Exclusive WriteNoSnp writes nothing
            // (IHI 0050H B6.3.4).
            eNeedWriteback[i] = eSnpDone[i] && !e.wrOwed
                                && ((!e.wrCancel && !(e.exclStore && !e.exclPass))
                                    || e.snpDirty);
          end
          HNF_KIND_WRITE_ZERO: begin
            eWriteBe[i] = ALL_BYTES;
            eNeedWriteback[i] = eSnpDone[i];
          end
          HNF_KIND_COPYBACK: begin
            eWriteBe[i] = bufWrBe[i];
            eNeedWriteback[i] = !e.wrOwed && !e.wrCancel
                                && respPassDirty(e.wrResp);
          end
          HNF_KIND_ATOMIC: begin
            eWriteBe[i] = ALL_BYTES;
            eNeedWriteback[i] = e.atomicDone && (e.atomicUpdate || e.snpDirty);
          end
          default:
            eNeedWriteback[i] = 1'b0;
        endcase
      end
      // Data the SLC keeps does not go to memory now. A line leaving the
      // SLC with an entry goes to memory with that entry, whole, before the
      // SLC drops its copy.
      eRawWriteback[i] = eNeedWriteback[i];
      if (e.slcKeep)
        eNeedWriteback[i] = 1'b0;
      if (e.slcRemove && e.slcDirty && (e.phase == PH_RUN) && !e.dnWriteDone
          && eSnpDone[i] && eLineComplete[i]) begin
        eNeedWriteback[i] = 1'b1;
        eWriteBe[i] = ALL_BYTES;
      end

      // Persist and Storage maintenance is forwarded once any write it must
      // follow has reached memory.
      eNeedCmoFwd[i] = (e.phase == PH_RUN) && (e.err == HNF_ERR_NONE)
                       && !e.dnCmoDone && cmoForwarded(e.cmo)
                       && eSnpDone[i] && !e.wrOwed && !eNeedWriteback[i];

      eAtomicReady[i] = (e.phase == PH_RUN) && (e.kind == HNF_KIND_ATOMIC)
                        && (e.err == HNF_ERR_NONE) && !e.atomicDone
                        && eSnpDone[i] && !e.wrOwed && eLineComplete[i];

      // DBIDResp or CompDBIDResp.
      eDbidReady[i] = (e.phase == PH_RUN) && e.dbidOwed;
      if (e.kind == HNF_KIND_WRITE_ZERO)
        eDbidReady[i] = eDbidReady[i]
                        && ((e.err != HNF_ERR_NONE)
                            || (eSnpDone[i]
                                && (e.req.memAttr[0] || e.dnWriteDone
                                    || e.slcKeep)));

      // The completion. Nothing completes while a snoop for the location is
      // outstanding (IHI 0050H B4.11.2), and an ordered read's CompData
      // follows its ReadReceipt.
      eCompIsData[i] = ((eDataPath[i] && !e.dmtSep)
                        || ((e.kind == HNF_KIND_ATOMIC)
                            && !isAtomicStore(e.req.opcode))
                        || ((e.err != HNF_ERR_NONE)
                            && (e.kind inside {HNF_KIND_READ,
                                               HNF_KIND_READ_ONCE,
                                               HNF_KIND_READ_NOSNP})
                            && !eMruHold[i]));
      eCompGranules[i] = (e.kind == HNF_KIND_ATOMIC)
                         ? messageGranules(CFG, e.req.addr,
                                           (e.req.opcode == REQ_ATOMIC_COMPARE)
                                           ? (e.req.size - 3'd1) : e.req.size)
                         : messageGranules(CFG, e.req.addr, e.req.size);
      eCompReady[i] = 1'b0;
      if ((e.phase == PH_RUN) && e.compOwed && !e.receiptOwed && !e.dbidOwed) begin
        if (e.err != HNF_ERR_NONE) begin
          eCompReady[i] = !e.wrOwed || !(e.kind == HNF_KIND_ATOMIC);
        end else begin
          case (e.kind)
            HNF_KIND_READ, HNF_KIND_READ_ONCE, HNF_KIND_READ_NOSNP:
              // A ReadNoSnpSep DMT read: RespSepData once the ReadReceipt
              // shows the SN-F accepted the request, which the Home may wait
              // for (IHI 0050H B2.3.1.1 alt 4).
              eCompReady[i] = e.dmtSep
                              ? (eSnpDone[i] && e.dnReadDone)
                              : (eSnpDone[i] && (eMruHold[i] || eLineComplete[i]));
            HNF_KIND_DATALESS, HNF_KIND_STASH_ONCE:
              eCompReady[i] = eSnpDone[i];
            HNF_KIND_CMO:
              // A CMO completes once every copy is clean and any Dirty data
              // has reached memory, or the forwarded CMO has completed.
              eCompReady[i] = eSnpDone[i] && !eNeedWriteback[i]
                              && (!cmoForwarded(e.cmo) || e.dnCmoDone);
            HNF_KIND_WRITE:
              // Comp once the write is serialized: snoops done and data
              // received; without Early Write Acknowledge only once memory
              // has it (IHI 0050H B2.8.3.1).
              // The Home is the point of coherence, so data the SLC keeps
              // is complete once the Home has it.
              eCompReady[i] = e.dwtUsed
                              ? e.dnWriteDone
                              : (eSnpDone[i] && !e.wrOwed
                                 && (e.req.memAttr[0] || e.dnWriteDone || e.slcKeep
                                     || !eNeedWritebackPossible(e, bufWrBe[i])));
            HNF_KIND_ATOMIC:
              eCompReady[i] = e.atomicDone;
            default:
              eCompReady[i] = 1'b1;
          endcase
        end
      end

      // CompCMO of a Combined write: after the write has reached memory and
      // any forwarded CMO has completed, and after the write's own Comp.
      eCompCmoReady[i] = (e.phase == PH_RUN) && e.compCmoOwed && !e.compOwed
                         && !e.dbidOwed && !e.wrOwed
                         && ((e.err != HNF_ERR_NONE)
                             || (eSnpDone[i] && !eNeedWriteback[i]
                                 && (!cmoForwarded(e.cmo) || e.dnCmoDone)));

      // Data Pull: the stash target is owed the line once the write (if any)
      // is in memory and the line is complete.
      ePullReady[i] = (e.phase == PH_RUN) && e.pullValid
                      && (e.pullGranSent != 4'hf) && eSnpDone[i]
                      && eLineComplete[i] && !e.dnBusy
                      && ((e.kind == HNF_KIND_STASH_ONCE) || e.dnWriteDone);

      eReceiptOwed[i] = e.receiptOwed;
      eCompOwed[i] = e.compOwed;
      eAllDone[i] = (e.phase == PH_RUN) && !e.receiptOwed && !e.dbidOwed
                    && !e.compOwed && !e.compCmoOwed && !e.compAckOwed
                    && !e.wrOwed && eSnpDone[i] && !e.dnBusy
                    && !eNeedMemRead[i] && !eNeedWriteback[i]
                    && !eNeedCmoFwd[i] && !e.pullAckOwed
                    && !(e.pullValid && (e.pullGranSent != 4'hf))
                    && !eAtomicReady[i];
    end
  end


  // ---------------------------------------------------------------------
  // Atomic execution: one ready atomic entry per cycle goes through the
  // ALU. The operand packet was kept whole; the initial value is in the
  // line buffer.
  // ---------------------------------------------------------------------
  always_comb begin
    logic found;
    entry_t e;
    int unsigned offset;
    int unsigned operandBytes;
    int unsigned swapOffset;
    int unsigned beatBase;
    found = 1'b0;
    atomicEntry = '0;
    for (int unsigned i = 0; i < POS_DEPTH; i++)
      if (!found && eAtomicReady[i]) begin
        found = 1'b1;
        atomicEntry = POS_W'(i);
      end
    atomicValid = found;
    e = entry[atomicEntry];
    // AtomicCompare carries the compare and swap values together, so each
    // operand is half of Size (IHI 0050H B2.9.6.1).
    atomicOperandSize = (e.req.opcode == REQ_ATOMIC_COMPARE)
                        ? (e.req.size - 3'd1) : e.req.size;
    operandBytes = 32'd1 << atomicOperandSize;
    offset = 32'(e.req.addr[5:0]);
    // The compare value is at the addressed location and the swap value at
    // the address with bit log2(operand size) inverted (IHI 0050H B2.9.6.2).
    swapOffset = offset ^ operandBytes;
    beatBase = int'(e.atomicBeatId) * 16;
    atomicInitialWord = '0;
    atomicTransactionWord = '0;
    atomicCompareWord = '0;
    for (int unsigned b = 0; b < 8; b++) begin
      if ((offset + b) < 64)
        atomicInitialWord[b*8 +: 8] = bufData[atomicEntry][(offset + b)*8 +: 8];
      if (((offset + b) >= beatBase) && ((offset + b) < (beatBase + DAT_BYTES)))
        atomicTransactionWord[b*8 +: 8] =
          e.atomicBeat[(offset + b - beatBase)*8 +: 8];
      if (((swapOffset + b) >= beatBase)
          && ((swapOffset + b) < (beatBase + DAT_BYTES)))
        atomicCompareWord[b*8 +: 8] =
          e.atomicBeat[(swapOffset + b - beatBase)*8 +: 8];
    end
    // For AtomicCompare the value at the address is compared and the value
    // at the swap location replaces it.
    if (e.req.opcode == REQ_ATOMIC_COMPARE) begin
      logic [63:0] compareValue;
      compareValue = atomicTransactionWord;
      atomicTransactionWord = atomicCompareWord;
      atomicCompareWord = compareValue;
    end
  end

  chi_atomic_alu atomic_alu (
    .opcode(entry[atomicEntry].req.opcode), .size(atomicOperandSize),
    .bigEndian(entry[atomicEntry].req.stashNidValidOrEndianOrDeep),
    .initialData(atomicInitialWord),
    .transactionData(atomicTransactionWord),
    .compareData(atomicCompareWord), .isAtomic(atomicOpValid),
    .returnsData(atomicReturnsData), .updateEnable(atomicUpdateEnable),
    .updateData(atomicUpdateWord), .originalData(atomicOriginalWord)
  );

  // ---------------------------------------------------------------------
  // Snoops.
  // ---------------------------------------------------------------------
  always_comb begin
    for (int unsigned i = 0; i < POS_DEPTH; i++) begin
      ownerToSend[i] = entry[i].snpToSend;
      ownerPending[i] = entry[i].snpPending;
      ownerKey[i] = posKey[i];
      ownerLive[i] = posActive[i];
      for (int unsigned r = 0; r < NUM_RNF; r++)
        ownerDataFrom[i][r] = entry[i].snpGranules[r] != '0;
    end
    for (int unsigned v = 0; v < NUM_VB; v++) begin
      ownerToSend[POS_DEPTH + v] = victim[v].snpToSend;
      ownerPending[POS_DEPTH + v] = victim[v].snpPending;
      ownerKey[POS_DEPTH + v] = victim[v].key;
      ownerLive[POS_DEPTH + v] = victim[v].valid;
      for (int unsigned r = 0; r < NUM_RNF; r++)
        ownerDataFrom[POS_DEPTH + v][r] = victim[v].snpGranules[r] != '0;
    end
  end

  chi_snp_gen #(
    .NUM_OWNERS(NUM_OWNERS), .NUM_RNF(NUM_RNF),
    .MAX_OUTSTANDING(CFG.maxOutstandingSnoops), .COUNT_W(SNP_COUNT_W)
  ) snoop_generator (
    .clk, .resetn, .toSend(ownerToSend),
    .rspComplete(snpRspComplete), .datComplete(snpDatComplete),
    .issueReady(snpFifoReady), .issueValid(snpIssueValid),
    .issueOwner(snpIssueOwner), .issueTarget(snpIssueTarget),
    .outstanding(snpOutstanding)
  );

  always_comb begin
    snpIssueFire = snpIssueValid && snpFifoReady;
  end

  always_comb begin
    chi_snp_flit_t snoop;
    logic isPos;
    logic [POS_W-1:0] posIndex;
    logic [VB_W-1:0] vbIndex;
    isPos = int'(snpIssueOwner) < POS_DEPTH;
    posIndex = POS_W'(snpIssueOwner);
    vbIndex = VB_W'(int'(snpIssueOwner) - POS_DEPTH);
    snoop = '0;
    snoop.qos = isPos ? entry[posIndex].req.qos : '0;
    snoop.srcId = HN_NODE_ID;
    snoop.txnId = CHI_TXNID_FLIT_W'(snpIssueOwner);
    snoop.addr = '0;
    if (isPos) begin
      snoop.addr[CFG.addrW-4:0] = {keyLine(posKey[posIndex]), 3'b000};
      snoop.pas = entry[posIndex].req.pas;
      if (entry[posIndex].stashValid
          && (snpIssueTarget == entry[posIndex].stashTarget)) begin
        snoop.opcode = entry[posIndex].stashOpcode;
        // For a stash snoop the 12-bit slot carries
        // {StashLPIDValid, StashLPID} (IHI 0050H Table B13.8).
        snoop.fwdTxnIdOrStashLpidOrVmidExt =
          {{(CHI_RTNTXNID_SLOT_W - CHI_MAX_LPID_W - 1){1'b0}},
           entry[posIndex].stashLpidValid, entry[posIndex].stashLpid};
      end else if (entry[posIndex].dctPlanned
                   && (snpIssueTarget == entry[posIndex].sfOwner)) begin
        // The forwarding snoop names the Requester and its TxnID; the
        // forwarded CompData carries this snoop's TxnID as DBID
        // (IHI 0050H B2.5.1.3).
        snoop.opcode = entry[posIndex].dctOpcode;
        snoop.fwdNidOrPbha = entry[posIndex].req.srcId;
        snoop.fwdTxnIdOrStashLpidOrVmidExt =
          CHI_RTNTXNID_SLOT_W'(entry[posIndex].req.txnId);
        snoop.retToSrc = 1'b0;
      end else begin
        snoop.opcode = entry[posIndex].snpOpcode;
        // RetToSrc goes to one Request Node only, the one the directory says
        // may hold the line Dirty or Unique, and never on a snoop where it is
        // inapplicable (IHI 0050H B4.9).
        snoop.retToSrc = entry[posIndex].snpRetToSrc
                         && entry[posIndex].sfOwnerValid
                         && (snpIssueTarget == entry[posIndex].sfOwner)
                         && !(entry[posIndex].snpOpcode inside {
                                SNP_CLEAN_SHARED, SNP_CLEAN_INVALID,
                                SNP_MAKE_INVALID});
      end
    end else begin
      snoop.addr[CFG.addrW-4:0] = {keyLine(victim[vbIndex].key), 3'b000};
      snoop.pas = keyPas(victim[vbIndex].key);
      snoop.opcode = SNP_CLEAN_INVALID;
    end
    snpIssueFlit = '0;
    snpIssueFlit.channel = CHI_CHANNEL_SNP;
    snpIssueFlit.qos = snoop.qos;
    snpIssueFlit.targetNodeId = RNF_NODE_IDS[snpIssueTarget];
    snpIssueFlit.payload[CHI_MAX_SNP_FLIT_W-1:0] = packSnpFlit(CFG, snoop);
  end

  // ---------------------------------------------------------------------
  // Input classification. RSP and DAT are always accepted: a Home must sink
  // responses and data without depending on anything else.
  // ---------------------------------------------------------------------
  always_comb begin
    rspInReady = 1'b1;
    datInReady = 1'b1;
  end

  always_comb begin
    logic rspFromSn;
    logic datFromSn;
    rspFromSn = incomingRsp.srcId == SN_NODE_ID;
    datFromSn = incomingDat.srcId == SN_NODE_ID;

    snpRspValid = rspInValid && isSnoopResponse(incomingRsp.opcode)
                  && isRnf(incomingRsp.srcId)
                  && (int'(incomingRsp.txnId) < NUM_OWNERS);
    snpRspOwner = OWNER_W'(incomingRsp.txnId);
    snpRspTarget = rnfIndex(incomingRsp.srcId);

    compAckValid = rspInValid && (incomingRsp.opcode == RSP_COMP_ACK)
                   && (int'(incomingRsp.txnId) < POS_DEPTH);
    compAckEntry = POS_W'(incomingRsp.txnId);

    snRspValid = rspInValid && rspFromSn && !isSnoopResponse(incomingRsp.opcode)
                 && (incomingRsp.opcode != RSP_COMP_ACK);

    snpDatValid = datInValid && isSnoopData(incomingDat.opcode)
                  && isRnf(incomingDat.srcId)
                  && (int'(incomingDat.txnId) < NUM_OWNERS);
    snpDatOwner = OWNER_W'(incomingDat.txnId);
    snpDatTarget = rnfIndex(incomingDat.srcId);
    snpDatGranules = packetGranules(incomingDat.dataId, incomingDat.numDat);

    wrDatValid = datInValid && isRequesterData(incomingDat.opcode)
                 && (int'(incomingDat.txnId) < POS_DEPTH);
    wrDatEntry = POS_W'(incomingDat.txnId);
    wrDatGranules = packetGranules(incomingDat.dataId, incomingDat.numDat);

    snDatValid = datInValid && datFromSn
                 && ((incomingDat.opcode == DAT_COMP_DATA)
                     || (incomingDat.opcode == DAT_DATA_SEP_RESP));
    memDatValid = snDatValid && (int'(incomingDat.txnId) < NUM_OWNERS);
    gptDatValid = GPT_READS && snDatValid && (int'(incomingDat.txnId) == GPT_OWNER);
    memDatOwner = OWNER_W'(incomingDat.txnId);
  end

  // A snoop with data retires on the packet that completes its Snoopee's
  // line. Each Snoopee's packets are counted on their own, because several
  // Snoopees can be returning data to one owner at once, and only a response
  // the owner is waiting for counts.
  always_comb begin
    logic [3:0] received;
    if (int'(snpDatOwner) < POS_DEPTH)
      received = entry[POS_W'(snpDatOwner)].snpGranules[snpDatTarget];
    else
      received = victim[VB_W'(int'(snpDatOwner) - POS_DEPTH)].snpGranules[snpDatTarget];
    snpDatLast = (received | snpDatGranules) == 4'hf;
    snpDatExpected = snpDatValid && ownerPending[snpDatOwner][snpDatTarget];
    snpDatComplete = snpDatExpected && snpDatLast;
    snpRspComplete = snpRspValid && ownerPending[snpRspOwner][snpRspTarget];
  end

  // ---------------------------------------------------------------------
  // Downstream operations. An owner starts at most one at a time; the order
  // within an owner is read, then write, then forwarded CMO, which is the
  // order every transaction kind needs.
  // ---------------------------------------------------------------------
  always_comb begin
    for (int unsigned i = 0; i < POS_DEPTH; i++) begin
      entry_t e;
      e = entry[i];
      dnStartValid[i] = 1'b0;
      dnStartKind[i] = HNF_DN_READ;
      dnStartGranules[i] = 4'hf;
      dnStartNoData[i] = 1'b0;
      dnStartWantReceipt[i] = 1'b0;
      if ((e.phase == PH_RUN) && !e.dnBusy && !dnBusy[i]) begin
        if (eNeedMemRead[i]) begin
          // An SLC hit is read through the SLC read port instead; a line
          // the SLC will keep is always read whole.
          dnStartValid[i] = !e.slcHit;
          dnStartKind[i] = HNF_DN_READ;
          dnStartGranules[i] = ((e.kind == HNF_KIND_READ_NOSNP) && !e.slcKeep)
                               ? messageGranules(CFG, e.req.addr, e.req.size)
                               : 4'hf;
          // With DMT the data goes to the Requester; the ReadReceipt tells
          // the Home the SN-F will not retry the read (Table B2.6).
          dnStartNoData[i] = eDmtOk[i];
          dnStartWantReceipt[i] = eDmtOk[i];
        end else if (eNeedWriteback[i]) begin
          dnStartValid[i] = 1'b1;
          dnStartKind[i] = HNF_DN_WRITE;
          dnStartGranules[i] = dnExactWrite(e)
                               ? messageGranules(CFG, e.req.addr, e.req.size)
                               : 4'hf;
          // With DWT the data goes from the Requester to the SN-F.
          dnStartNoData[i] = e.dwtUsed;
        end else if (eNeedCmoFwd[i]) begin
          dnStartValid[i] = 1'b1;
          dnStartKind[i] = HNF_DN_CMO;
        end
      end
    end
    for (int unsigned v = 0; v < NUM_VB; v++) begin
      int unsigned owner;
      owner = POS_DEPTH + v;
      dnStartValid[owner] = victim[v].valid && !victim[v].dnBusy
                            && !dnBusy[owner] && !victim[v].dnWriteDone
                            && (victim[v].snpToSend == '0)
                            && (victim[v].snpPending == '0)
                            && victim[v].snpDirty;
      dnStartKind[owner] = HNF_DN_WRITE;
      dnStartGranules[owner] = 4'hf;
      dnStartNoData[owner] = 1'b0;
      dnStartWantReceipt[owner] = 1'b0;
    end
    // The walker's read: one at a time, never while one is completing.
    if (GPT_READS) begin
      dnStartValid[GPT_IDX] = gptReadValid && !dnBusy[GPT_IDX] && !gptReadDone;
      dnStartKind[GPT_IDX] = HNF_DN_READ;
      dnStartGranules[GPT_IDX] = 4'hf;
      dnStartNoData[GPT_IDX] = 1'b0;
      dnStartWantReceipt[GPT_IDX] = 1'b0;
    end
  end


  // The HN-F has one Subordinate, so every operation goes to index 0.
  localparam logic [CHI_MAX_NODEID_W-1:0] SN_NODE_ID_TABLE [1] = '{SN_NODE_ID};

  chi_sn_tracker #(
    .CFG(CFG), .NUM_OWNERS(TRK_OWNERS),
    .NUM_SUB(1), .SUB_NODE_IDS(SN_NODE_ID_TABLE)
  ) sn_tracker (
    .clk, .resetn,
    .startValid(dnStartValid), .startKind(dnStartKind),
    .startSub('0), .startGranules(dnStartGranules),
    .startReadGranules('0), .startNoData(dnStartNoData),
    .startWantReceipt(dnStartWantReceipt),
    .busy(dnBusy), .waiting(dnWaiting), .done(dnDone),
    .resend(dnResend), .resendCreditType(dnResendType),
    .reqIssueReady(reqFifoReady), .reqIssueValid(dnReqValid),
    .reqIssueOwner(dnReqOwner), .reqIssueCreditReturn(dnReqCreditReturn),
    .reqIssueCreditType(dnReqCreditType), .reqIssueCreditSub(),
    .datIssueReady(datTrackerWins && datFifoReady),
    .datIssueValid(dnDatValid), .datIssueOwner(dnDatOwner),
    .datIssueDataId(dnDatDataId), .datIssueTxnId(dnDatTxnId),
    .rspValid(snRspValid), .rsp(incomingRsp),
    .datValid(snDatValid), .dat(incomingDat)
  );

  // The request a downstream operation sends (IHI 0050H B2.3.9). SnpAttr is
  // zero and Order is at most Request accepted towards an SN-F
  // (IHI 0050H B2.8.6, Table B2.9); ReturnNID and ReturnTxnID name the Home
  // unless a Persist response belongs to the Requester (B2.4.4, B2.4.10).
  always_comb begin
    chi_req_flit_t request;
    logic isPos;
    logic [POS_W-1:0] posIndex;
    logic [VB_W-1:0] vbIndex;
    entry_t e;
    isPos = int'(dnReqOwner) < POS_DEPTH;
    posIndex = POS_W'(dnReqOwner);
    vbIndex = VB_W'(int'(dnReqOwner) - POS_DEPTH);
    e = entry[posIndex];
    request = '0;
    request.tgtId = SN_NODE_ID;
    request.srcId = HN_NODE_ID;
    request.txnId = CHI_TXNID_FLIT_W'(dnReqOwner);
    request.allowRetry = !dnResend[dnReqOwner];
    request.pCrdType = dnResend[dnReqOwner] ? dnResendType[dnReqOwner] : '0;
    request.order = ORDER_NONE;
    request.size = 3'd6;
    if (dnReqCreditReturn) begin
      request.opcode = REQ_PCRD_RETURN;
      request.txnId = '0;
      request.allowRetry = 1'b0;
      request.pCrdType = dnReqCreditType;
      request.size = 3'd0;
    end else if (isPos) begin
      request.qos = e.req.qos;
      request.pas = e.req.pas;
      request.memAttr = e.req.memAttr;
      request.addr = {keyLine(posKey[posIndex]), 6'b0};
      request.returnNidOrStashNidOrDataTarget = HN_NODE_ID;
      request.returnTxnIdOrStashLpid = CHI_RTNTXNID_SLOT_W'(dnReqOwner);
      case (e.dnKind)
        HNF_DN_READ: begin
          request.opcode = REQ_READ_NO_SNP;
          if ((e.kind == HNF_KIND_READ_NOSNP) && !e.slcKeep) begin
            request.addr = e.req.addr;
            request.size = e.req.size;
          end
          if (e.dmtUsed) begin
            // DMT: the SN-F returns CompData, or DataSepResp for
            // ReadNoSnpSep, to the Requester under its TxnID, with this
            // request's TxnID as DBID and the Home as HomeNID, and confirms
            // acceptance with ReadReceipt (IHI 0050H B2.5.1.1, B2.5.1.2,
            // Table B2.6).
            if (e.dmtSep)
              request.opcode = REQ_READ_NO_SNP_SEP;
            request.returnNidOrStashNidOrDataTarget = e.req.srcId;
            request.returnTxnIdOrStashLpid = CHI_RTNTXNID_SLOT_W'(e.req.txnId);
            request.order = ORDER_REQUEST_ACCEPTED;
          end
        end
        HNF_DN_WRITE: begin
          if (dnExactWrite(e)) begin
            request.addr = e.req.addr;
            request.size = e.req.size;
            request.opcode = isFullLineWrite(e.req.opcode)
                             ? REQ_WRITE_NO_SNP_FULL : REQ_WRITE_NO_SNP_PTL;
            if (e.dwtUsed) begin
              // DWT: the SN-F returns DBIDResp to the Requester, which sends
              // it the data; the SN-F's Comp comes back to the Home
              // (IHI 0050H B2.3.2.1 alt 1, B13.10.24).
              request.snpAttrOrDoDwt = 1'b1;
              request.returnNidOrStashNidOrDataTarget = e.req.srcId;
              request.returnTxnIdOrStashLpid = CHI_RTNTXNID_SLOT_W'(e.req.txnId);
            end
          end else begin
            request.opcode = (eWriteBe[posIndex] == ALL_BYTES)
                             ? REQ_WRITE_NO_SNP_FULL : REQ_WRITE_NO_SNP_PTL;
          end
        end
        default: begin
          request.opcode = cmoDownstreamOpcode(e.cmo);
          request.returnTxnIdOrStashLpid = '0;
          // The Subordinate sends Persist straight to the Requester, under
          // the Requester's PGroupID (IHI 0050H B2.3.5 alt 3c, B2.4.13).
          if (e.cmo == HNF_CMO_PERSIST_SEP) begin
            request.returnNidOrStashNidOrDataTarget = e.req.srcId;
            request.groupIdOrLpid = e.req.groupIdOrLpid;
          end else begin
            request.returnNidOrStashNidOrDataTarget = '0;
          end
          request.stashNidValidOrEndianOrDeep = e.req.stashNidValidOrEndianOrDeep;
        end
      endcase
    end else if (GPT_READS && (int'(dnReqOwner) == GPT_OWNER)) begin
      // A GPT read: the whole line, in the Root PAS, straight from memory
      // below every cache (the GPT is maintained to the PoPA).
      request.opcode = REQ_READ_NO_SNP;
      request.pas = PAS_ROOT;
      request.memAttr = 4'b0100;
      request.addr = {gptAddr[CHI_MAX_ADDR_W-1:6], 6'b0};
      request.returnNidOrStashNidOrDataTarget = HN_NODE_ID;
      request.returnTxnIdOrStashLpid = CHI_RTNTXNID_SLOT_W'(dnReqOwner);
    end else begin
      request.qos = '0;
      request.pas = keyPas(victim[vbIndex].key);
      // A directory eviction writes back a coherent, Normal, Cacheable line.
      request.memAttr = 4'b0101;
      request.addr = {keyLine(victim[vbIndex].key), 6'b0};
      request.returnNidOrStashNidOrDataTarget = HN_NODE_ID;
      request.returnTxnIdOrStashLpid = CHI_RTNTXNID_SLOT_W'(dnReqOwner);
      request.opcode = (bufSnpBe[dnReqOwner] == ALL_BYTES)
                       ? REQ_WRITE_NO_SNP_FULL : REQ_WRITE_NO_SNP_PTL;
    end
    dnReqFlit = '0;
    dnReqFlit.channel = CHI_CHANNEL_REQ;
    dnReqFlit.qos = request.qos;
    dnReqFlit.targetNodeId = SN_NODE_ID;
    dnReqFlit.payload[CHI_MAX_REQ_FLIT_W-1:0] = packReqFlit(CFG, request);
  end

  // Write data towards the Subordinate.
  always_comb begin
    chi_dat_flit_t data;
    logic [63:0] writeBe;
    logic isPos;
    isPos = int'(dnDatOwner) < POS_DEPTH;
    writeBe = isPos ? eWriteBe[POS_W'(dnDatOwner)] : bufSnpBe[dnDatOwner];
    data = '0;
    data.tgtId = SN_NODE_ID;
    data.srcId = HN_NODE_ID;
    data.txnId = CHI_TXNID_FLIT_W'(dnDatTxnId);
    data.opcode = DAT_NON_COPY_BACK_WR_DATA;
    data.resp = RESP_I;
    data.respErr = bufDataErr[dnDatOwner] ? RESP_ERR_DERR : RESP_ERR_OK;
    data.dataId = dnDatDataId;
    // CCID follows the downstream request's address, which is line aligned
    // unless a WriteNoSnp is forwarded as received (IHI 0050H B2.9.7).
    data.ccId = (isPos && dnExactWrite(entry[POS_W'(dnDatOwner)]))
                ? entry[POS_W'(dnDatOwner)].req.addr[5:4] : '0;
    data.data[CFG.dataW-1:0] = bufData[dnDatOwner][int'(dnDatDataId)*128 +: CFG.dataW];
    for (int unsigned b = 0; b < DAT_BYTES; b++)
      data.be[b] = writeBe[int'(dnDatDataId)*16 + b];
    data.dataCheck = dataCheckOf(data.data);
    data.poison[POISON_PER_BEAT-1:0] =
      bufPoison[dnDatOwner][int'(dnDatDataId)*2 +: POISON_PER_BEAT];
    dnDatFlit = '0;
    dnDatFlit.channel = CHI_CHANNEL_DAT;
    dnDatFlit.targetNodeId = SN_NODE_ID;
    dnDatFlit.payload = packDatFlit(CFG, data);
  end

  // ---------------------------------------------------------------------
  // Responses to Requesters. RetryAck goes first so a refused request
  // leaves the REQ channel at once, then PCrdGrant, then the entries in
  // round-robin order. Within an entry: ReadReceipt, DBIDResp, Comp,
  // CompCMO.
  // ---------------------------------------------------------------------
  always_comb begin
    for (int unsigned i = 0; i < POS_DEPTH; i++)
      rspWant[i] = entry[i].receiptOwed
                   || eDbidReady[i]
                   || (eCompReady[i] && !eCompIsData[i])
                   || eCompCmoReady[i];
  end

  always_comb begin
    logic found;
    int unsigned candidate;
    found = 1'b0;
    rspEntry = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < POS_DEPTH; offset++) begin
      candidate = int'(rspPointer) + offset;
      if (candidate >= POS_DEPTH)
        candidate = candidate - POS_DEPTH;
      if (!found && rspWant[candidate]) begin
        found = 1'b1;
        rspEntry = POS_W'(candidate);
      end
    end
    rspEntryValid = found;
    rspGrantSend = !retryAckWant && retryGrantValid && rspFifoReady;
    rspEntrySend = !retryAckWant && !retryGrantValid && rspEntryValid
                   && rspFifoReady;
    retryGrantReady = rspGrantSend;
  end

  // The response flit for the RSP channel this cycle.
  always_comb begin
    chi_rsp_flit_t response;
    entry_t e;
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
      // PCrdGrant names the recorded Requester and carries no TxnID or DBID
      // (IHI 0050H B2.5.5).
      response.tgtId = retryGrantTgtId;
      response.opcode = RSP_PCRD_GRANT;
      response.pCrdType = retryGrantClass;
    end else begin
      response.qos = e.req.qos;
      response.tgtId = e.req.srcId;
      response.txnId = e.req.txnId;
      response.dbIdOrGroupId = CHI_RSP_DBID_SLOT_W'(rspEntry);
      response.respErr = (e.err != HNF_ERR_NONE) ? RESP_ERR_NDERR
                                                  : RESP_ERR_OK;
      if (e.receiptOwed) begin
        response.opcode = RSP_READ_RECEIPT;
        response.respErr = RESP_ERR_OK;
      end else if (eDbidReady[rspEntry]) begin
        response.opcode = e.dbidWithComp ? RSP_COMP_DBID_RESP : RSP_DBID_RESP;
        // WriteNoSnpDef is unsupported at an HN-F: OK/Unsupported
        // (IHI 0050H Table B4.29).
        if ((e.kind == HNF_KIND_WRITE_DEF) && (e.err == HNF_ERR_NONE))
          response.resp = RESP_SC;
        if (!e.dbidWithComp)
          response.respErr = RESP_ERR_OK;
      end else if (eCompReady[rspEntry] && !eCompIsData[rspEntry]) begin
        response.opcode = RSP_COMP;
        case (e.kind)
          HNF_KIND_DATALESS:
            // A failing Exclusive CleanUnique keeps the Requester Shared
            // (IHI 0050H B6.3.3.3).
            response.resp = (e.req.opcode == REQ_EVICT) ? RESP_I
                            : ((e.exclStore && !e.exclPass) ? RESP_SC
                                                            : RESP_UC_UD);
          HNF_KIND_READ:
            if (e.dmtSep) begin
              // RespSepData carries the state of the SN-F's DataSepResp,
              // always UC, and as DBID the ReadNoSnpSep's TxnID, which the
              // DataSepResp carries too (IHI 0050H B4.5.1.1, B4.7.1,
              // B2.5.1.2).
              response.opcode = RSP_RESP_SEP_DATA;
              response.resp = RESP_UC_UD;
            end else begin
              // MakeReadUnique: Unique on a pass, Shared on an exclusive
              // fail (IHI 0050H B6.3.1.1).
              response.resp = eMruFail[rspEntry] ? RESP_SC : RESP_UC_UD;
            end
          default:
            response.resp = RESP_I;
        endcase
        if ((e.kind == HNF_KIND_STASH_ONCE)
            && (e.req.opcode inside {REQ_STASH_ONCE_SEP_SHARED,
                                     REQ_STASH_ONCE_SEP_UNIQUE})) begin
          // CompStashDone carries the StashGroupID in the DBID slot
          // (IHI 0050H B7.5.3).
          response.opcode = RSP_COMP_STASH_DONE;
          response.dbIdOrGroupId =
            CHI_RSP_DBID_SLOT_W'(e.req.groupIdOrLpid);
        end
        if ((e.err == HNF_ERR_NONE) && e.exclStore && e.exclPass
            && (e.req.opcode != REQ_MAKE_READ_UNIQUE))
          response.respErr = RESP_ERR_EXOK;
      end else begin
        response.opcode = RSP_COMP_CMO;
      end
    end
    // The push valid never looks at the output stage's ready
    // (design specification, Section 2.8).
    rspPushValid = retryAckWant || retryGrantValid || rspEntryValid;
    rspPushFlit = '0;
    rspPushFlit.channel = CHI_CHANNEL_RSP;
    rspPushFlit.qos = response.qos;
    rspPushFlit.targetNodeId = response.tgtId;
    rspPushFlit.payload[CHI_MAX_RSP_FLIT_W-1:0] = packRspFlit(CFG, response);
  end

  // ---------------------------------------------------------------------
  // Data to Requesters: CompData to the Requester and the Data Pull
  // CompData to a stash target. The SN trackers' write data shares the DAT
  // output; it and the entries alternate.
  // ---------------------------------------------------------------------
  always_comb begin
    for (int unsigned i = 0; i < POS_DEPTH; i++)
      datWant[i] = (eCompReady[i] && eCompIsData[i]) || ePullReady[i];
  end

  always_comb begin
    logic found;
    int unsigned candidate;
    entry_t e;
    logic [3:0] remaining;
    found = 1'b0;
    datEntry = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < POS_DEPTH; offset++) begin
      candidate = int'(datPointer) + offset;
      if (candidate >= POS_DEPTH)
        candidate = candidate - POS_DEPTH;
      if (!found && datWant[candidate]) begin
        found = 1'b1;
        datEntry = POS_W'(candidate);
      end
    end
    datEntryValid = found;
    e = entry[datEntry];
    datEntryToPull = !(eCompReady[datEntry] && eCompIsData[datEntry]);
    remaining = datEntryToPull ? (4'hf & ~e.pullGranSent)
                               : (eCompGranules[datEntry] & ~e.compGranSent);
    datEntryDataId = '0;
    for (int unsigned g = 4; g > 0; g--)
      if (remaining[g-1])
        datEntryDataId = 2'((g - 1) & ~(STEP - 1));
    // Downstream write data and the entries' data share the DAT output;
    // whichever did not go last has priority when both are waiting.
    datTrackerWins = dnDatValid && (datTrackerTurn || !datEntryValid);
    datTrackerSend = datTrackerWins && datFifoReady;
    datEntrySend = datEntryValid && !datTrackerWins && datFifoReady;
  end

  always_comb begin
    chi_dat_flit_t data;
    entry_t e;
    e = entry[datEntry];
    data = '0;
    data.qos = e.req.qos;
    data.srcId = HN_NODE_ID;
    data.homeNidOrPbha = HN_NODE_ID;
    data.dbId = CHI_DAT_DBID_SLOT_W'(datEntry);
    data.opcode = DAT_COMP_DATA;
    data.dataId = datEntryDataId;
    data.ccId = e.req.addr[5:4];
    data.data[CFG.dataW-1:0] = bufData[datEntry][int'(datEntryDataId)*128 +: CFG.dataW];
    data.poison[POISON_PER_BEAT-1:0] =
      bufPoison[datEntry][int'(datEntryDataId)*2 +: POISON_PER_BEAT];
    for (int unsigned b = 0; b < DAT_BYTES; b++)
      data.be[b] = 1'b1;
    if (datEntryToPull) begin
      // The Data Pull completes like an Allocating Read under the TxnID the
      // stash target supplied (IHI 0050H B7.1.1, B2.3.4).
      data.tgtId = RNF_NODE_IDS[e.stashTarget];
      data.txnId = CHI_TXNID_FLIT_W'(e.pullTxnId);
      data.resp = e.pullResp;
      data.respErr = bufDataErr[datEntry] ? RESP_ERR_DERR : RESP_ERR_OK;
    end else begin
      data.tgtId = e.req.srcId;
      data.txnId = e.req.txnId;
      if (e.err != HNF_ERR_NONE) begin
        // NDERR in every packet; the data values are not required to be
        // valid (IHI 0050H B9.1.3).
        data.respErr = RESP_ERR_NDERR;
        data.resp = RESP_I;
        data.data = '0;
        data.poison = '0;
      end else if (e.kind == HNF_KIND_ATOMIC) begin
        // The original value at the addressed location, which atomic return
        // data must not be cached from (IHI 0050H B4.2.5).
        data.resp = RESP_I;
        data.respErr = RESP_ERR_OK;
        data.data = '0;
        for (int unsigned b = 0; b < 8; b++) begin
          int unsigned lineByte;
          lineByte = 32'(e.req.addr[5:0]) + b;
          if ((b < (32'd1 << ((e.req.opcode == REQ_ATOMIC_COMPARE)
                              ? (e.req.size - 3'd1) : e.req.size)))
              && (lineByte >= (int'(datEntryDataId) * 16))
              && (lineByte < (int'(datEntryDataId) * 16 + DAT_BYTES)))
            data.data[(lineByte - int'(datEntryDataId) * 16)*8 +: 8] =
              e.atomicOrig[b*8 +: 8];
        end
      end else begin
        data.resp = eGrant[datEntry];
        data.respErr = bufDataErr[datEntry] ? RESP_ERR_DERR
                       : (e.exclLoad && (e.req.opcode != REQ_READ_PREFER_UNIQUE)
                          ? RESP_ERR_EXOK : RESP_ERR_OK);
      end
    end
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
  // Directory update at retirement, one entry per cycle, and the victim it
  // may evict.
  // ---------------------------------------------------------------------
  always_comb begin
    logic found;
    int unsigned candidate;
    entry_t e;
    logic [NUM_RNF-1:0] reqBit;
    logic [NUM_RNF-1:0] targetBit;
    logic [NUM_RNF-1:0] sharers;
    logic ownerValid;
    logic [RNF_W-1:0] owner;
    found = 1'b0;
    sfUpdateEntry = '0;
    candidate = 0;
    for (int unsigned offset = 0; offset < POS_DEPTH; offset++) begin
      candidate = int'(sfUpdatePointer) + offset;
      if (candidate >= POS_DEPTH)
        candidate = candidate - POS_DEPTH;
      if (!found && (entry[candidate].phase == PH_RETIRE)
          && entry[candidate].sfUpdOwed) begin
        found = 1'b1;
        sfUpdateEntry = POS_W'(candidate);
      end
    end
    // An alias eviction takes the port ahead of a retiring entry.
    sfUpdateEvict = sfAliasEvict;
    sfUpdateValid = found || sfAliasEvict;
    e = entry[sfUpdateEntry];
    sfUpdateKey = sfAliasEvict ? sfLookupAliasKey : posKey[sfUpdateEntry];
    reqBit = '0;
    if (e.reqIsRnf)
      reqBit[e.reqRnf] = 1'b1;
    targetBit = '0;
    if (e.stashValid)
      targetBit[e.stashTarget] = 1'b1;

    // Start from the snapshot: an RN-F that was snooped keeps a place only
    // if its response said it kept a copy, and the owner is whichever RN-F
    // still holds an owning state.
    sharers = (e.sfSharers & ~e.snpTargets) | e.snpKeep;
    ownerValid = 1'b0;
    owner = '0;
    for (int unsigned r = 0; r < NUM_RNF; r++)
      if (e.snpOwns[r]) begin
        ownerValid = 1'b1;
        owner = RNF_W'(r);
      end
    if (!ownerValid && e.sfOwnerValid && !e.snpTargets[e.sfOwner]) begin
      ownerValid = 1'b1;
      owner = e.sfOwner;
    end

    case (e.kind)
      HNF_KIND_READ: begin
        if (eMruHold[sfUpdateEntry] || (eGrant[sfUpdateEntry] != RESP_I)) begin
          sharers = sharers | reqBit;
          if ((eMruHold[sfUpdateEntry] && !eMruFail[sfUpdateEntry])
              || ((eGrant[sfUpdateEntry] != RESP_SC)
                  && !eMruHold[sfUpdateEntry])) begin
            ownerValid = e.reqIsRnf;
            owner = e.reqRnf;
          end
        end
      end
      HNF_KIND_DATALESS: begin
        if (e.req.opcode == REQ_EVICT) begin
          sharers = sharers & ~reqBit;
          if (ownerValid && e.reqIsRnf && (owner == e.reqRnf))
            ownerValid = 1'b0;
        end else if (!(e.exclStore && !e.exclPass)) begin
          sharers = reqBit;
          ownerValid = e.reqIsRnf;
          owner = e.reqRnf;
        end
      end
      HNF_KIND_CMO: begin
        if (cmoInvalidates(e.cmo)) begin
          sharers = sharers & ~reqBit;
          if (ownerValid && e.reqIsRnf && (owner == e.reqRnf))
            ownerValid = 1'b0;
        end
      end
      HNF_KIND_WRITE, HNF_KIND_WRITE_ZERO: begin
        if (e.pullValid && (e.pullGranSent == 4'hf)) begin
          sharers = targetBit;
          ownerValid = 1'b1;
          owner = e.stashTarget;
        end
      end
      HNF_KIND_COPYBACK: begin
        if (copyBackDeallocates(e.req.opcode)) begin
          sharers = sharers & ~reqBit;
          if (ownerValid && e.reqIsRnf && (owner == e.reqRnf))
            ownerValid = 1'b0;
        end
      end
      HNF_KIND_ATOMIC: begin
        sharers = sharers & ~reqBit;
        if (ownerValid && e.reqIsRnf && (owner == e.reqRnf))
          ownerValid = 1'b0;
      end
      HNF_KIND_STASH_ONCE: begin
        if (e.pullValid && (e.pullGranSent == 4'hf)) begin
          sharers = sharers | targetBit;
          if (e.stashUnique) begin
            ownerValid = 1'b1;
            owner = e.stashTarget;
          end
        end
      end
      default: begin
      end
    endcase
    if (ownerValid && !sharers[owner])
      ownerValid = 1'b0;
    sfUpdateSharers = sharers;
    sfUpdateOwnerValid = ownerValid;
    sfUpdateOwner = owner;

    // Ways whose location a transaction or a victim entry holds are never
    // evicted.
    for (int unsigned way = 0; way < SF_WAYS; way++) begin
      sfUpdateLockedWays[way] = 1'b0;
      for (int unsigned i = 0; i < POS_DEPTH; i++)
        if (posActive[i] && (posKey[i] == sfUpdateSetKeys[way]))
          sfUpdateLockedWays[way] = 1'b1;
      for (int unsigned v = 0; v < NUM_VB; v++)
        if (victim[v].valid && (victim[v].key == sfUpdateSetKeys[way]))
          sfUpdateLockedWays[way] = 1'b1;
    end

    victimFree = 1'b0;
    victimFreeIndex = '0;
    for (int unsigned v = 0; v < NUM_VB; v++)
      if (!victimFree && !victim[v].valid) begin
        victimFree = 1'b1;
        victimFreeIndex = VB_W'(v);
      end
  end

  // A Requester owes write data once it has the DBID, CompAck once it has
  // every response, and a stash target owes CompAck once it has the line.
  always_comb begin
    for (int unsigned i = 0; i < POS_DEPTH; i++) begin
      eGpcFailed[i] = posActive[i] && (entry[i].err == HNF_ERR_GPC);
      eDmtUsed[i] = posActive[i] && entry[i].dmtUsed;
      eDmtSep[i] = posActive[i] && entry[i].dmtSep;
      eDnReadDone[i] = entry[i].dnReadDone;
      eDwtUsed[i] = posActive[i] && entry[i].dwtUsed;
      eDnWriting[i] = posActive[i] && entry[i].dnBusy
                      && (entry[i].dnKind == HNF_DN_WRITE);
      eDctPlanned[i] = posActive[i] && entry[i].dctPlanned;
      eExclLoad[i] = entry[i].exclLoad;
      eExclStore[i] = entry[i].exclStore;
      eSlcLine[i] = entry[i].slcHit || entry[i].slcKeep;
      eGpcPending[i] = posActive[i] && entry[i].gpcPending;
      liveWaitSnoop[i] = entry[i].snpPending != '0;
      liveWaitDownstream[i] = dnWaiting[i];
      liveWaitRequester[i] = (entry[i].wrOwed && !entry[i].dbidOwed)
                             || (entry[i].compAckOwed && !entry[i].dbidOwed
                                 && !entry[i].compOwed)
                             || (entry[i].pullAckOwed
                                 && (entry[i].pullGranSent == 4'hf));
    end
  end

  always_comb begin
    // An entry frees once its directory and SLC updates are done.
    posFreeMask = '0;
    for (int unsigned i = 0; i < POS_DEPTH; i++)
      if ((entry[i].phase == PH_RETIRE) && !entry[i].sfUpdOwed
          && !entry[i].slcUpdOwed)
        posFreeMask[i] = 1'b1;
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

  chi_flit_fifo snp_fifo (
    .clk, .resetn, .pushValid(snpIssueValid), .pushReady(snpFifoReady),
    .pushFlit(snpIssueFlit), .outValid(snpOutValid), .outReady(snpOutReady),
    .outFlit(snpOutFlit), .count(snpFifoCount)
  );

  chi_flit_fifo dat_fifo (
    .clk, .resetn, .pushValid(datPushValid), .pushReady(datFifoReady),
    .pushFlit(datPushFlit), .outValid(datOutValid), .outReady(datOutReady),
    .outFlit(datOutFlit), .count(datFifoCount)
  );

  // Maintenance is done once the walk has finished and every write-back it
  // started has reached memory.
  always_comb begin
    slcMaintBusy = slcMaintWalking;
    for (int unsigned v = 0; v < NUM_VB; v++)
      if (victim[v].valid)
        slcMaintBusy = 1'b1;
  end

  always_comb begin
    idle = (posActive == '0) && (reqFifoCount == '0) && (rspFifoCount == '0)
           && (snpFifoCount == '0) && (datFifoCount == '0)
           && (dnBusy == '0) && !slcMaintWalking;
    for (int unsigned v = 0; v < NUM_VB; v++)
      if (victim[v].valid)
        idle = 1'b0;
  end

  // The walker's GPT line, delivered whole when its read completes.
  if (GPT_READS) begin : gpt_reads
    always_ff @(posedge clk) begin
      if (!resetn) begin
        gptAddr <= '0;
        gptBuf <= '0;
        gptErr <= 1'b0;
      end else begin
        if (dnStartValid[GPT_IDX]) begin
          gptAddr <= gptReadAddr;
          gptErr <= 1'b0;
        end
        if (gptDatValid) begin
          gptBuf[int'(incomingDat.dataId)*128 +: CFG.dataW] <=
            incomingDat.data[CFG.dataW-1:0];
          if (incomingDat.respErr != RESP_ERR_OK)
            gptErr <= 1'b1;
        end
      end
    end
    always_comb begin
      gptReadDone = dnDone[GPT_IDX];
      gptReadData = gptBuf;
      gptReadError = gptErr;
    end
  end else begin : no_gpt_reads
    always_comb begin
      gptAddr = '0;
      gptBuf = '0;
      gptErr = 1'b0;
      gptReadDone = 1'b0;
      gptReadData = '0;
      gptReadError = 1'b0;
    end
  end

  // ---------------------------------------------------------------------
  // Sequential state.
  // ---------------------------------------------------------------------
  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned i = 0; i < POS_DEPTH; i++) begin
        entry[i] <= '0;
        entry[i].phase <= PH_FREE;
      end
      for (int unsigned v = 0; v < NUM_VB; v++)
        victim[v] <= '0;
      startPointer <= '0;
      rspPointer <= '0;
      datPointer <= '0;
      sfUpdatePointer <= '0;
      slcUpdatePointer <= '0;
      gpcRecheckPointer <= '0;
      datTrackerTurn <= 1'b0;
    end else begin
      // Allocation.
      if (posAllocValid && posAllocReady)
        entry[posAllocIndex] <= allocEntry;

      // Start.
      if (startValid) begin
        entry[startIndex] <= planEntry;
        startPointer <= (int'(startIndex) == (POS_DEPTH - 1))
                        ? '0 : (startIndex + 1'b1);
      end

      // Snoop issue.
      if (snpIssueFire) begin
        if (int'(snpIssueOwner) < POS_DEPTH) begin
          entry[POS_W'(snpIssueOwner)].snpToSend[snpIssueTarget] <= 1'b0;
          entry[POS_W'(snpIssueOwner)].snpPending[snpIssueTarget] <= 1'b1;
        end else begin
          victim[VB_W'(int'(snpIssueOwner) - POS_DEPTH)].snpToSend[snpIssueTarget] <= 1'b0;
          victim[VB_W'(int'(snpIssueOwner) - POS_DEPTH)].snpPending[snpIssueTarget] <= 1'b1;
        end
      end

      // Snoop responses without data.
      if (snpRspComplete) begin
        if (int'(snpRspOwner) < POS_DEPTH) begin
          entry[POS_W'(snpRspOwner)].snpPending[snpRspTarget] <= 1'b0;
          if (snoopeeKeeps(incomingRsp.resp))
            entry[POS_W'(snpRspOwner)].snpKeep[snpRspTarget] <= 1'b1;
          if (snoopeeOwns(incomingRsp.resp))
            entry[POS_W'(snpRspOwner)].snpOwns[snpRspTarget] <= 1'b1;
          if (incomingRsp.respErr != RESP_ERR_OK)
            entry[POS_W'(snpRspOwner)].snpErr <= 1'b1;
          // SnpRespFwded: the Snoopee sent CompData to the Requester in the
          // state FwdState names, so the Home owes it no data
          // (IHI 0050H B4.5.3, B13.10.47).
          if (incomingRsp.opcode == RSP_SNP_RESP_FWDED) begin
            entry[POS_W'(snpRspOwner)].snpFwded <= 1'b1;
            entry[POS_W'(snpRspOwner)].snpFwdState <= chi_resp_e'(incomingRsp.fwdState);
            entry[POS_W'(snpRspOwner)].compOwed <= 1'b0;
          end
          // DataPull rides in FwdState[0] and the implied read's TxnID in
          // DBID (IHI 0050H Table B13.7, B7.5.3).
          if (entry[POS_W'(snpRspOwner)].stashValid
              && (snpRspTarget == entry[POS_W'(snpRspOwner)].stashTarget)
              && incomingRsp.fwdState[0]) begin
            entry[POS_W'(snpRspOwner)].pullValid <= 1'b1;
            entry[POS_W'(snpRspOwner)].pullTxnId <=
              CHI_TXNID_FLIT_W'(incomingRsp.dbIdOrGroupId);
            entry[POS_W'(snpRspOwner)].pullAckOwed <= 1'b1;
          end
        end else begin
          victim[VB_W'(int'(snpRspOwner) - POS_DEPTH)].snpPending[snpRspTarget] <= 1'b0;
        end
      end

      // Snoop responses with data. Each Snoopee's packets are counted on
      // their own, and its snoop retires on the packet completing its line.
      if (snpDatExpected) begin
        if (int'(snpDatOwner) < POS_DEPTH) begin
          entry[POS_W'(snpDatOwner)].snpGranules[snpDatTarget] <=
            entry[POS_W'(snpDatOwner)].snpGranules[snpDatTarget] | snpDatGranules;
          if (respPassDirty(incomingDat.resp))
            entry[POS_W'(snpDatOwner)].snpDirty <= 1'b1;
          if (incomingDat.opcode == DAT_SNP_RESP_DATA_PTL)
            entry[POS_W'(snpDatOwner)].snpPtl <= 1'b1;
          if (incomingDat.respErr != RESP_ERR_OK)
            entry[POS_W'(snpDatOwner)].snpErr <= 1'b1;
          if (snpDatLast) begin
            entry[POS_W'(snpDatOwner)].snpPending[snpDatTarget] <= 1'b0;
            if (snoopeeKeeps(incomingDat.resp))
              entry[POS_W'(snpDatOwner)].snpKeep[snpDatTarget] <= 1'b1;
            if (snoopeeOwns(incomingDat.resp))
              entry[POS_W'(snpDatOwner)].snpOwns[snpDatTarget] <= 1'b1;
            // SnpRespDataFwded: CompData went to the Requester as well, and
            // FwdState rides in DataSource[2:0] (IHI 0050H B4.5.3, B13.9.4).
            if (incomingDat.opcode == DAT_SNP_RESP_DATA_FWDED) begin
              entry[POS_W'(snpDatOwner)].snpFwded <= 1'b1;
              entry[POS_W'(snpDatOwner)].snpFwdState <=
                chi_resp_e'(incomingDat.dataSourceOrFwdState[2:0]);
              entry[POS_W'(snpDatOwner)].compOwed <= 1'b0;
            end
            if (entry[POS_W'(snpDatOwner)].stashValid
                && (snpDatTarget == entry[POS_W'(snpDatOwner)].stashTarget)
                && incomingDat.dataPull) begin
              entry[POS_W'(snpDatOwner)].pullValid <= 1'b1;
              entry[POS_W'(snpDatOwner)].pullTxnId <=
                CHI_TXNID_FLIT_W'(incomingDat.dbId);
              entry[POS_W'(snpDatOwner)].pullAckOwed <= 1'b1;
            end
          end
        end else begin
          victim[VB_W'(int'(snpDatOwner) - POS_DEPTH)].snpGranules[snpDatTarget] <=
            victim[VB_W'(int'(snpDatOwner) - POS_DEPTH)].snpGranules[snpDatTarget]
            | snpDatGranules;
          if (respPassDirty(incomingDat.resp))
            victim[VB_W'(int'(snpDatOwner) - POS_DEPTH)].snpDirty <= 1'b1;
          if (snpDatLast)
            victim[VB_W'(int'(snpDatOwner) - POS_DEPTH)].snpPending[snpDatTarget] <= 1'b0;
        end
      end

      // Requester data.
      if (wrDatValid && entry[wrDatEntry].wrOwed) begin
        if (((entry[wrDatEntry].wrGranules | wrDatGranules)
             & messageGranules(CFG, entry[wrDatEntry].req.addr,
                               entry[wrDatEntry].req.size))
            == messageGranules(CFG, entry[wrDatEntry].req.addr,
                               entry[wrDatEntry].req.size))
          entry[wrDatEntry].wrOwed <= 1'b0;
        entry[wrDatEntry].wrGranules <=
          entry[wrDatEntry].wrGranules | wrDatGranules;
        if (incomingDat.opcode == DAT_WRITE_DATA_CANCEL)
          entry[wrDatEntry].wrCancel <= 1'b1;
        if (incomingDat.opcode == DAT_COPY_BACK_WR_DATA) begin
          entry[wrDatEntry].wrResp <= incomingDat.resp;
          // CopyBackWriteData_I: the line was snooped away while the CopyBack
          // waited, and the data is not valid (IHI 0050H B2.9.5).
          if (incomingDat.resp == RESP_I)
            entry[wrDatEntry].wrCancel <= 1'b1;
        end
        if (incomingDat.opcode == DAT_NCB_WR_DATA_COMP_ACK)
          entry[wrDatEntry].compAckOwed <= 1'b0;
        if (entry[wrDatEntry].kind == HNF_KIND_ATOMIC) begin
          entry[wrDatEntry].atomicBeat <= incomingDat.data[CFG.dataW-1:0];
          entry[wrDatEntry].atomicBeatId <= incomingDat.dataId;
        end
      end

      // CompAck from the Requester or from the stash target.
      if (compAckValid) begin
        if (incomingRsp.srcId == entry[compAckEntry].req.srcId)
          entry[compAckEntry].compAckOwed <= 1'b0;
        if (entry[compAckEntry].pullAckOwed
            && (incomingRsp.srcId
                == RNF_NODE_IDS[entry[compAckEntry].stashTarget]))
          entry[compAckEntry].pullAckOwed <= 1'b0;
      end

      // Downstream operations.
      for (int unsigned i = 0; i < POS_DEPTH; i++) begin
        if (dnStartValid[i]) begin
          entry[i].dnBusy <= 1'b1;
          entry[i].dnKind <= dnStartKind[i];
          // A DMT read owes the Requester only RespSepData, with dmtSepEn,
          // and the SLC is not filled.
          if ((dnStartKind[i] == HNF_DN_READ) && eDmtOk[i]) begin
            entry[i].dmtUsed <= 1'b1;
            entry[i].dmtSep <= CFG.dmtSepEn;
            entry[i].compOwed <= CFG.dmtSepEn;
            entry[i].slcKeep <= 1'b0;
          end
        end
        if (dnDone[i]) begin
          entry[i].dnBusy <= 1'b0;
          case (entry[i].dnKind)
            HNF_DN_READ:  entry[i].dnReadDone <= 1'b1;
            HNF_DN_WRITE: entry[i].dnWriteDone <= 1'b1;
            default:      entry[i].dnCmoDone <= 1'b1;
          endcase
        end
      end

      // Atomic execution.
      if (atomicValid) begin
        entry[atomicEntry].atomicDone <= 1'b1;
        entry[atomicEntry].atomicUpdate <= atomicUpdateEnable;
        entry[atomicEntry].atomicOrig <= atomicOriginalWord;
      end

      // Responses sent.
      if (rspEntrySend) begin
        if (entry[rspEntry].receiptOwed)
          entry[rspEntry].receiptOwed <= 1'b0;
        else if (eDbidReady[rspEntry])
          entry[rspEntry].dbidOwed <= 1'b0;
        else if (eCompReady[rspEntry] && !eCompIsData[rspEntry])
          entry[rspEntry].compOwed <= 1'b0;
        else
          entry[rspEntry].compCmoOwed <= 1'b0;
        rspPointer <= (int'(rspEntry) == (POS_DEPTH - 1))
                      ? '0 : (rspEntry + 1'b1);
      end

      // Data sent.
      if (datEntrySend) begin
        if (datEntryToPull) begin
          for (int unsigned g = 0; g < 4; g++)
            if ((g >= int'(datEntryDataId)) && (g < (int'(datEntryDataId) + STEP)))
              entry[datEntry].pullGranSent[g] <= 1'b1;
        end else begin
          for (int unsigned g = 0; g < 4; g++)
            if ((g >= int'(datEntryDataId)) && (g < (int'(datEntryDataId) + STEP)))
              entry[datEntry].compGranSent[g] <= 1'b1;
          if (((entry[datEntry].compGranSent | beatGranules(CFG, datEntryDataId))
               & eCompGranules[datEntry]) == eCompGranules[datEntry])
            entry[datEntry].compOwed <= 1'b0;
        end
        datPointer <= (int'(datEntry) == (POS_DEPTH - 1))
                      ? '0 : (datEntry + 1'b1);
      end
      if (datTrackerSend)
        datTrackerTurn <= 1'b0;
      else if (datEntrySend)
        datTrackerTurn <= 1'b1;

      // Retirement and free.
      for (int unsigned i = 0; i < POS_DEPTH; i++) begin
        if (eAllDone[i]) begin
          entry[i].phase <= PH_RETIRE;
          // What the SLC is left holding: the latest line, dirty if it was
          // or if the entry did not write it to memory. Cancelled write data
          // never reaches the SLC.
          entry[i].slcKeepDirty <= entry[i].slcDirty || eRawWriteback[i];
          entry[i].slcUpdOwed <= entry[i].slcRemove
                                 || (entry[i].slcKeep && !entry[i].wrCancel
                                     && (!entry[i].slcHit || eRawWriteback[i]));
        end
        if (posFreeMask[i])
          entry[i].phase <= PH_FREE;
      end
      if (sfUpdateValid && sfUpdateReady && !sfUpdateEvict)
        entry[sfUpdateEntry].sfUpdOwed <= 1'b0;
      if (slcUpdateValid && slcUpdateReady && slcUpdateFromRetire) begin
        entry[slcUpdateEntry].slcUpdOwed <= 1'b0;
        slcUpdatePointer <= (int'(slcUpdateEntry) == (POS_DEPTH - 1))
                            ? '0 : (slcUpdateEntry + 1'b1);
      end
      // The SLC read port fills the buffer as memory would.
      if (slcReadValid)
        entry[slcReadEntry].dnReadDone <= 1'b1;
      // A waiting entry's granule protection answer.
      if (gpcRecheckValid && gpcCheckDone) begin
        entry[gpcRecheckEntry].gpcPending <= 1'b0;
        if (gpcCheckFail)
          entry[gpcRecheckEntry].err <= HNF_ERR_GPC;
        gpcRecheckPointer <= (int'(gpcRecheckEntry) == (POS_DEPTH - 1))
                             ? '0 : (gpcRecheckEntry + 1'b1);
      end
      if (sfUpdateValid && sfUpdateReady && !sfUpdateEvict)
        sfUpdatePointer <= (int'(sfUpdateEntry) == (POS_DEPTH - 1))
                           ? '0 : (sfUpdateEntry + 1'b1);

      // Victim buffer.
      for (int unsigned v = 0; v < NUM_VB; v++) begin
        int unsigned owner;
        owner = POS_DEPTH + v;
        if (dnStartValid[owner])
          victim[v].dnBusy <= 1'b1;
        if (dnDone[owner]) begin
          victim[v].dnBusy <= 1'b0;
          victim[v].dnWriteDone <= 1'b1;
        end
        if (victim[v].valid && (victim[v].snpToSend == '0)
            && (victim[v].snpPending == '0) && !victim[v].dnBusy
            && (!victim[v].snpDirty || victim[v].dnWriteDone))
          victim[v].valid <= 1'b0;
      end
      if (sfVictimValid && sfUpdateValid && sfUpdateReady) begin
        victim[victimFreeIndex] <= '0;
        victim[victimFreeIndex].valid <= 1'b1;
        victim[victimFreeIndex].key <= sfVictimKey;
        victim[victimFreeIndex].snpToSend <= sfVictimSharers;
      end
      // A dirty line leaving the SLC is written back by a victim entry,
      // which holds the location until memory has it.
      if (slcVictimValid && slcVictimReady) begin
        victim[victimFreeIndex] <= '0;
        victim[victimFreeIndex].valid <= 1'b1;
        victim[victimFreeIndex].key <= slcVictimKey;
        victim[victimFreeIndex].snpDirty <= 1'b1;
      end
    end
  end

  // Line buffers. One DAT packet arrives per cycle, so one owner is written
  // from the input at most; the atomic ALU writes an entry no packet can be
  // arriving for. A newer source never yields to an older one: Requester data
  // over snoop data over memory data.
  always_ff @(posedge clk) begin
    if (!resetn) begin
      for (int unsigned o = 0; o < NUM_OWNERS; o++) begin
        bufData[o] <= '0;
        bufWrBe[o] <= '0;
        bufSnpBe[o] <= '0;
        bufMemBe[o] <= '0;
        bufPoison[o] <= '0;
      end
      bufDataErr <= '0;
    end else begin
      if (posAllocValid && posAllocReady) begin
        bufWrBe[posAllocIndex] <= '0;
        bufSnpBe[posAllocIndex] <= '0;
        bufMemBe[posAllocIndex] <= '0;
        bufPoison[posAllocIndex] <= '0;
        bufDataErr[posAllocIndex] <= 1'b0;
      end
      if (startValid && (entry[startIndex].kind == HNF_KIND_WRITE_ZERO)) begin
        bufData[startIndex] <= '0;
        bufWrBe[startIndex] <= ALL_BYTES;
      end
      if (sfVictimValid && sfUpdateValid && sfUpdateReady) begin
        bufWrBe[POS_DEPTH + victimFreeIndex] <= '0;
        bufSnpBe[POS_DEPTH + victimFreeIndex] <= '0;
        bufMemBe[POS_DEPTH + victimFreeIndex] <= '0;
        bufPoison[POS_DEPTH + victimFreeIndex] <= '0;
        bufDataErr[POS_DEPTH + victimFreeIndex] <= 1'b0;
      end
      if (slcVictimValid && slcVictimReady) begin
        bufData[POS_DEPTH + victimFreeIndex] <= slcVictimData;
        bufWrBe[POS_DEPTH + victimFreeIndex] <= '0;
        bufSnpBe[POS_DEPTH + victimFreeIndex] <= ALL_BYTES;
        bufMemBe[POS_DEPTH + victimFreeIndex] <= '0;
        bufPoison[POS_DEPTH + victimFreeIndex] <= slcVictimPoison;
        bufDataErr[POS_DEPTH + victimFreeIndex] <= 1'b0;
      end
      // SLC data lands below anything the Requester or a snoop supplied.
      if (slcReadValid) begin
        for (int unsigned b = 0; b < 64; b++)
          if (!bufWrBe[slcReadEntry][b] && !bufSnpBe[slcReadEntry][b])
            bufData[slcReadEntry][b*8 +: 8] <= slcReadData[b*8 +: 8];
        bufMemBe[slcReadEntry] <= ALL_BYTES;
        bufPoison[slcReadEntry] <= bufPoison[slcReadEntry] | slcReadPoison;
      end

      if (wrDatValid && entry[wrDatEntry].wrOwed
          && (entry[wrDatEntry].kind != HNF_KIND_ATOMIC)
          && (incomingDat.opcode != DAT_WRITE_DATA_CANCEL)
          && !((incomingDat.opcode == DAT_COPY_BACK_WR_DATA)
               && (incomingDat.resp == RESP_I))) begin
        for (int unsigned b = 0; b < DAT_BYTES; b++)
          if (incomingDat.be[b])
            bufData[wrDatEntry][(int'(incomingDat.dataId)*16 + b)*8 +: 8] <=
              incomingDat.data[b*8 +: 8];
        bufWrBe[wrDatEntry] <= bufWrBe[wrDatEntry]
                               | beatEnables(incomingDat.dataId, incomingDat.be);
        bufPoison[wrDatEntry][int'(incomingDat.dataId)*2 +: POISON_PER_BEAT] <=
          incomingDat.poison[POISON_PER_BEAT-1:0];
        if (incomingDat.respErr == RESP_ERR_DERR)
          bufDataErr[wrDatEntry] <= 1'b1;
      end

      // Valid copies of a line agree, so the data of several Snoopees
      // merges into one buffer; a poisoned copy keeps the line poisoned.
      if (snpDatExpected) begin
        for (int unsigned b = 0; b < DAT_BYTES; b++)
          if (incomingDat.be[b]
              && !bufWrBe[snpDatOwner][int'(incomingDat.dataId)*16 + b])
            bufData[snpDatOwner][(int'(incomingDat.dataId)*16 + b)*8 +: 8] <=
              incomingDat.data[b*8 +: 8];
        bufSnpBe[snpDatOwner] <= bufSnpBe[snpDatOwner]
                                 | beatEnables(incomingDat.dataId, incomingDat.be);
        bufPoison[snpDatOwner][int'(incomingDat.dataId)*2 +: POISON_PER_BEAT] <=
          bufPoison[snpDatOwner][int'(incomingDat.dataId)*2 +: POISON_PER_BEAT]
          | incomingDat.poison[POISON_PER_BEAT-1:0];
        if (incomingDat.respErr == RESP_ERR_DERR)
          bufDataErr[snpDatOwner] <= 1'b1;
      end

      if (memDatValid) begin
        for (int unsigned b = 0; b < DAT_BYTES; b++)
          if (!bufWrBe[memDatOwner][int'(incomingDat.dataId)*16 + b]
              && !bufSnpBe[memDatOwner][int'(incomingDat.dataId)*16 + b])
            bufData[memDatOwner][(int'(incomingDat.dataId)*16 + b)*8 +: 8] <=
              incomingDat.data[b*8 +: 8];
        bufMemBe[memDatOwner] <= bufMemBe[memDatOwner]
                                 | beatBytes(incomingDat.dataId);
        bufPoison[memDatOwner][int'(incomingDat.dataId)*2 +: POISON_PER_BEAT] <=
          bufPoison[memDatOwner][int'(incomingDat.dataId)*2 +: POISON_PER_BEAT]
          | incomingDat.poison[POISON_PER_BEAT-1:0];
        if (incomingDat.respErr != RESP_ERR_OK)
          bufDataErr[memDatOwner] <= 1'b1;
      end

      if (atomicValid && atomicUpdateEnable) begin
        for (int unsigned b = 0; b < 8; b++)
          if ((b < (32'd1 << atomicOperandSize))
              && ((32'(entry[atomicEntry].req.addr[5:0]) + b) < 64))
            bufData[atomicEntry][(32'(entry[atomicEntry].req.addr[5:0]) + b)*8 +: 8] <=
              atomicUpdateWord[b*8 +: 8];
      end
    end
  end
endmodule
