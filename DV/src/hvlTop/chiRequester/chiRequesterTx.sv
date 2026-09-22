// A requester sequence item states intent. The opcode is not the
// sequence's decision: the driver reads the cache model at issue time
// and records the opcode it actually sent in issuedOpcode.
// [SPEC:IHI0050H B4.2] [ASSUMPTION:7] [ASSUMPTION:15]

typedef enum int unsigned {
  CHI_INTENT_READ_SHARED,
  CHI_INTENT_READ_CLEAN,
  CHI_INTENT_READ_ONCE,
  CHI_INTENT_READ_NO_SNP,
  CHI_INTENT_READ_UNIQUE,
  CHI_INTENT_CLEAN_UNIQUE,
  CHI_INTENT_MAKE_UNIQUE,
  CHI_INTENT_EVICT,
  CHI_INTENT_WRITE_BACK,
  CHI_INTENT_WRITE_CLEAN,
  CHI_INTENT_WRITE_UNIQUE,
  CHI_INTENT_WRITE_NO_SNP,
  CHI_INTENT_WRITE_UNIQUE_ZERO,
  CHI_INTENT_WRITE_NO_SNP_ZERO,
  CHI_INTENT_ATOMIC_LOAD,
  CHI_INTENT_ATOMIC_STORE,
  CHI_INTENT_ATOMIC_SWAP,
  CHI_INTENT_ATOMIC_COMPARE,
  CHI_INTENT_CLEAN_SHARED,
  CHI_INTENT_CLEAN_INVALID,
  CHI_INTENT_MAKE_INVALID,
  CHI_INTENT_DVM_OP,
  CHI_INTENT_PREFETCH_TGT,
  CHI_INTENT_STASH_ONCE,
  CHI_INTENT_EXCLUSIVE_LOAD,
  CHI_INTENT_EXCLUSIVE_STORE,
  CHI_INTENT_PCRD_RETURN
} chiRequesterIntentE;

class chiRequesterTx extends uvm_sequence_item;
  chiNodeClassE nodeClass;

  rand chiRequesterIntentE intent;
  rand chiAddrT addr;
  rand logic [SIZE_W-1:0] size;
  rand logic [QOS_W-1:0] qos;
  rand logic [ORDER_W-1:0] order;
  rand logic [PAS_W-1:0] pas;
  rand logic [MEM_ATTR_W-1:0] memAttr;
  rand bit snpAttr;
  rand logic [REQ_SHARED_SLOT_W-1:0] sharedSlot;
  rand bit excl;
  rand bit expCompAck;
  rand bit allowRetry;
  rand chiNodeIdT tgtId;
  rand logic [P_CRD_TYPE_W-1:0] pCrdType;
  rand chiReqOpcodeE atomicOpcode;
  rand logic [511:0] data;
  rand logic [63:0] be;
  rand logic [63:0] dataCheck;
  rand logic [7:0] poison;

  chiReqOpcodeE issuedOpcode;
  chiCacheStateE initialState;
  bit localOnly;

  `uvm_object_utils(chiRequesterTx)

  function new(string name = "chiRequesterTx");
    super.new(name);
    nodeClass = RN_F;
    issuedOpcode = REQ_READ_NO_SNP;
    initialState = CACHE_I;
    localOnly = 1'b0;
  endfunction

  function void chiCopyFrom(chiRequesterTx src);
    nodeClass = src.nodeClass;
    intent = src.intent;
    addr = src.addr;
    size = src.size;
    qos = src.qos;
    order = src.order;
    pas = src.pas;
    memAttr = src.memAttr;
    snpAttr = src.snpAttr;
    sharedSlot = src.sharedSlot;
    excl = src.excl;
    expCompAck = src.expCompAck;
    allowRetry = src.allowRetry;
    tgtId = src.tgtId;
    pCrdType = src.pCrdType;
    atomicOpcode = src.atomicOpcode;
    data = src.data;
    be = src.be;
    dataCheck = src.dataCheck;
    poison = src.poison;
    issuedOpcode = src.issuedOpcode;
    initialState = src.initialState;
    localOnly = src.localOnly;
  endfunction

  function string convert2string();
    return {$sformatf("intent=%s addr=%0h size=%0d opcode=%s state=%s local=%0b",
      intent.name(), addr, size, issuedOpcode.name(), initialState.name(), localOnly)};
  endfunction

  constraint chiLegalIntent {
    poison == '0;
    dataCheck == '0;
    size inside {[3'd0:3'd6]};
    // Issue H replaced the NS and NSE bits with a three-bit PAS naming one of
    // six Physical Address Spaces [SPEC:IHI0050H B13.10.68]. Stimulus stays in
    // the Non-secure space: the address map's secure-only regions reject
    // anything else, and a rejected request gets no error response from this
    // DUT at all (finding F-7).
    soft pas == chiGlobalsPkg::PAS_NON_SECURE;
    soft qos == '0;
    addr <= COHERENT_REGION_LIMIT;

    if (nodeClass != RN_F) {
      !(intent inside {
        CHI_INTENT_READ_SHARED, CHI_INTENT_READ_CLEAN, CHI_INTENT_READ_UNIQUE,
        CHI_INTENT_CLEAN_UNIQUE, CHI_INTENT_MAKE_UNIQUE, CHI_INTENT_EVICT,
        CHI_INTENT_WRITE_BACK, CHI_INTENT_WRITE_CLEAN, CHI_INTENT_PREFETCH_TGT,
        CHI_INTENT_STASH_ONCE, CHI_INTENT_EXCLUSIVE_LOAD,
        CHI_INTENT_EXCLUSIVE_STORE
      });
    }
    if (nodeClass == RN_I) {
      !(intent inside {
        CHI_INTENT_READ_ONCE, CHI_INTENT_WRITE_UNIQUE, CHI_INTENT_WRITE_UNIQUE_ZERO
      });
    }
    if (!CHI_CFG.atomicEn) {
      !(intent inside {
        CHI_INTENT_ATOMIC_LOAD, CHI_INTENT_ATOMIC_STORE,
        CHI_INTENT_ATOMIC_SWAP, CHI_INTENT_ATOMIC_COMPARE
      });
    }
    if (!CHI_CFG.dvmEn)
      intent != CHI_INTENT_DVM_OP;
    if (!CHI_CFG.stashEn)
      intent != CHI_INTENT_STASH_ONCE;
    if (!CHI_CFG.exclEn) {
      intent != CHI_INTENT_EXCLUSIVE_LOAD;
      intent != CHI_INTENT_EXCLUSIVE_STORE;
      excl == 1'b0;
    }
    if (intent == CHI_INTENT_EXCLUSIVE_LOAD || intent == CHI_INTENT_EXCLUSIVE_STORE)
      excl == 1'b1;
    else
      excl == 1'b0;

    if (intent == CHI_INTENT_PCRD_RETURN)
      allowRetry == 1'b0;
    else
      tgtId == '0;

    if (intent inside {
      CHI_INTENT_READ_SHARED, CHI_INTENT_READ_CLEAN, CHI_INTENT_READ_UNIQUE,
      CHI_INTENT_CLEAN_UNIQUE, CHI_INTENT_MAKE_UNIQUE, CHI_INTENT_EVICT,
      CHI_INTENT_WRITE_BACK, CHI_INTENT_WRITE_CLEAN, CHI_INTENT_WRITE_UNIQUE_ZERO,
      CHI_INTENT_WRITE_NO_SNP_ZERO, CHI_INTENT_STASH_ONCE, CHI_INTENT_PREFETCH_TGT
    })
      addr[5:0] == 6'h0;

    if (intent inside {
      CHI_INTENT_ATOMIC_LOAD, CHI_INTENT_ATOMIC_STORE,
      CHI_INTENT_ATOMIC_SWAP, CHI_INTENT_ATOMIC_COMPARE
    })
      size inside {[3'd0:3'd3]};

    if (size == SIZE_W'(1))
      addr[0] == 1'b0;
    if (size == SIZE_W'(2))
      addr[1:0] == 2'b0;
    if (size == SIZE_W'(3))
      addr[2:0] == 3'b0;
    if (size == SIZE_W'(4))
      addr[3:0] == 4'b0;
    if (size == SIZE_W'(5))
      addr[4:0] == 5'b0;
    if (size == SIZE_W'(6))
      addr[5:0] == 6'h0;

    if (intent == CHI_INTENT_ATOMIC_LOAD)
      atomicOpcode inside {
        REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR,
        REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN,
        REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_LOAD_UMIN
      };
    if (intent == CHI_INTENT_ATOMIC_STORE)
      atomicOpcode inside {
        REQ_ATOMIC_STORE_ADD, REQ_ATOMIC_STORE_CLR, REQ_ATOMIC_STORE_EOR,
        REQ_ATOMIC_STORE_SET, REQ_ATOMIC_STORE_SMAX, REQ_ATOMIC_STORE_SMIN,
        REQ_ATOMIC_STORE_UMAX, REQ_ATOMIC_STORE_UMIN
      };

    // [SPEC:IHI0050H B13.10] MemAttr is {Allocate, Cacheable, Device, EWA}.
    if (intent inside {
      CHI_INTENT_READ_SHARED, CHI_INTENT_READ_CLEAN, CHI_INTENT_READ_UNIQUE,
      CHI_INTENT_CLEAN_UNIQUE, CHI_INTENT_MAKE_UNIQUE, CHI_INTENT_WRITE_BACK,
      CHI_INTENT_WRITE_CLEAN, CHI_INTENT_EVICT
    }) {
      memAttr[2] == 1'b1;
      memAttr[1] == 1'b0;
      snpAttr == 1'b1;
    }
    if (intent inside {CHI_INTENT_DVM_OP, CHI_INTENT_PCRD_RETURN})
      expCompAck == 1'b0;
  }
endclass
