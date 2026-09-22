// RN-F cache image used only to choose a legal opcode at issue time
// and to answer snoops. It is not the scoreboard's directory.
// [SPEC:IHI0050H B4.1] [ASSUMPTION:7]

class chiRequesterCacheModel extends uvm_object;
  chiCacheStateE stateByLine[chiAddrT];
  logic [511:0] dataByLine[chiAddrT];

  `uvm_object_utils(chiRequesterCacheModel)

  function new(string name = "chiRequesterCacheModel");
    super.new(name);
  endfunction

  function chiAddrT chiLineAddr(input chiAddrT addr);
    return lineAlign(addr);
  endfunction

  function chiCacheStateE chiLookup(input chiAddrT addr);
    chiAddrT line;
    line = chiLineAddr(addr);
    if (stateByLine.exists(line))
      return stateByLine[line];
    return CACHE_I;
  endfunction

  function bit chiHoldsData(input chiCacheStateE state);
    return (state != CACHE_I);
  endfunction

  function bit chiIsDirty(input chiCacheStateE state);
    return (state == CACHE_UD) || (state == CACHE_SD);
  endfunction

  function void chiStoreLine(
    input chiAddrT addr,
    input chiCacheStateE state,
    input logic [511:0] data
  );
    chiAddrT line;
    line = chiLineAddr(addr);
    if (state == CACHE_I) begin
      stateByLine.delete(line);
      dataByLine.delete(line);
    end else begin
      stateByLine[line] = state;
      dataByLine[line] = data;
    end
  endfunction

  function void chiApplyLocal(input chiRequesterIntentE intent, input chiAddrT addr);
    chiAddrT line;
    line = chiLineAddr(addr);
    if (intent == CHI_INTENT_EVICT || intent == CHI_INTENT_WRITE_BACK
        || intent == CHI_INTENT_WRITE_CLEAN) begin
      stateByLine.delete(line);
      dataByLine.delete(line);
    end
  endfunction

  // Issue-time opcode. localOnly means the cache already satisfies the
  // intent, so no request is sent. Exclusive ops are never completed
  // locally: the exclusive monitor does not see the LPID, and a local
  // completion would hide that. [ASSUMPTION:7]
  function void chiPickOpcode(
    input chiRequesterTx item,
    input chiCacheStateE state,
    output chiReqOpcodeE opcode,
    output bit localOnly
  );
    localOnly = 1'b0;
    opcode = REQ_READ_NO_SNP;
    case (item.intent)
      CHI_INTENT_READ_SHARED: begin
        if (chiHoldsData(state))
          localOnly = 1'b1;
        else
          opcode = REQ_READ_SHARED;
      end
      CHI_INTENT_READ_CLEAN: begin
        if ((state == CACHE_SC) || (state == CACHE_UC))
          localOnly = 1'b1;
        else
          opcode = REQ_READ_CLEAN;
      end
      CHI_INTENT_READ_UNIQUE: begin
        if ((state == CACHE_UC) || (state == CACHE_UD))
          localOnly = 1'b1;
        else
          opcode = REQ_READ_UNIQUE;
      end
      CHI_INTENT_READ_ONCE: opcode = REQ_READ_ONCE;
      CHI_INTENT_READ_NO_SNP: opcode = REQ_READ_NO_SNP;
      CHI_INTENT_CLEAN_UNIQUE: begin
        if ((state == CACHE_UC) || (state == CACHE_UD))
          localOnly = 1'b1;
        else
          opcode = REQ_CLEAN_UNIQUE;
      end
      CHI_INTENT_MAKE_UNIQUE: begin
        if ((state == CACHE_UC) || (state == CACHE_UD))
          localOnly = 1'b1;
        else
          opcode = REQ_MAKE_UNIQUE;
      end
      CHI_INTENT_EVICT: begin
        if (state == CACHE_UD || state == CACHE_SD)
          opcode = REQ_WRITE_BACK_FULL;
        else if (state == CACHE_UC)
          opcode = REQ_EVICT;
        else
          localOnly = 1'b1;
      end
      CHI_INTENT_WRITE_BACK: begin
        if (chiIsDirty(state))
          opcode = REQ_WRITE_BACK_FULL;
        else
          localOnly = 1'b1;
      end
      CHI_INTENT_WRITE_CLEAN: begin
        if (chiIsDirty(state))
          opcode = REQ_WRITE_CLEAN_FULL;
        else
          localOnly = 1'b1;
      end
      CHI_INTENT_WRITE_UNIQUE: begin
        if (item.size == SIZE_W'(6))
          opcode = REQ_WRITE_UNIQUE_FULL;
        else
          opcode = REQ_WRITE_UNIQUE_PTL;
      end
      CHI_INTENT_WRITE_NO_SNP: begin
        if (item.size == SIZE_W'(6))
          opcode = REQ_WRITE_NO_SNP_FULL;
        else
          opcode = REQ_WRITE_NO_SNP_PTL;
      end
      CHI_INTENT_WRITE_UNIQUE_ZERO: opcode = REQ_WRITE_UNIQUE_ZERO;
      CHI_INTENT_WRITE_NO_SNP_ZERO: opcode = REQ_WRITE_NO_SNP_ZERO;
      CHI_INTENT_ATOMIC_LOAD, CHI_INTENT_ATOMIC_STORE: opcode = item.atomicOpcode;
      CHI_INTENT_ATOMIC_SWAP: opcode = REQ_ATOMIC_SWAP;
      CHI_INTENT_ATOMIC_COMPARE: opcode = REQ_ATOMIC_COMPARE;
      CHI_INTENT_CLEAN_SHARED: opcode = REQ_CLEAN_SHARED;
      CHI_INTENT_CLEAN_INVALID: opcode = REQ_CLEAN_INVALID;
      CHI_INTENT_MAKE_INVALID: opcode = REQ_MAKE_INVALID;
      CHI_INTENT_DVM_OP: opcode = REQ_DVM_OP;
      CHI_INTENT_PREFETCH_TGT: opcode = REQ_PREFETCH_TGT;
      CHI_INTENT_STASH_ONCE: opcode = REQ_STASH_ONCE_SHARED;
      CHI_INTENT_EXCLUSIVE_LOAD: opcode = REQ_READ_SHARED;
      CHI_INTENT_EXCLUSIVE_STORE: opcode = REQ_CLEAN_UNIQUE;
      CHI_INTENT_PCRD_RETURN: opcode = REQ_P_CRD_RETURN;
      default: opcode = REQ_READ_NO_SNP;
    endcase
  endfunction

  function bit chiExpectsWriteData(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_WRITE_BACK_FULL, REQ_WRITE_CLEAN_FULL,
      REQ_WRITE_UNIQUE_FULL, REQ_WRITE_UNIQUE_PTL,
      REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL,
      REQ_ATOMIC_STORE_ADD, REQ_ATOMIC_STORE_CLR, REQ_ATOMIC_STORE_EOR,
      REQ_ATOMIC_STORE_SET, REQ_ATOMIC_STORE_SMAX, REQ_ATOMIC_STORE_SMIN,
      REQ_ATOMIC_STORE_UMAX, REQ_ATOMIC_STORE_UMIN,
      REQ_ATOMIC_LOAD_ADD, REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR,
      REQ_ATOMIC_LOAD_SET, REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN,
      REQ_ATOMIC_LOAD_UMAX, REQ_ATOMIC_LOAD_UMIN,
      REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function bit chiExpectsReadData(input chiReqOpcodeE opcode);
    case (opcode)
      REQ_READ_SHARED, REQ_READ_CLEAN, REQ_READ_ONCE,
      REQ_READ_NO_SNP, REQ_READ_UNIQUE, REQ_ATOMIC_LOAD_ADD,
      REQ_ATOMIC_LOAD_CLR, REQ_ATOMIC_LOAD_EOR, REQ_ATOMIC_LOAD_SET,
      REQ_ATOMIC_LOAD_SMAX, REQ_ATOMIC_LOAD_SMIN, REQ_ATOMIC_LOAD_UMAX,
      REQ_ATOMIC_LOAD_UMIN, REQ_ATOMIC_SWAP, REQ_ATOMIC_COMPARE:
        return 1'b1;
      default: return 1'b0;
    endcase
  endfunction

  function bit chiIsCopyBack(input chiReqOpcodeE opcode);
    return (opcode == REQ_WRITE_BACK_FULL) || (opcode == REQ_WRITE_CLEAN_FULL);
  endfunction

  function void chiNoteComp(
    input chiAddrT addr,
    input chiReqOpcodeE opcode,
    input logic [RESP_W-1:0] resp,
    input logic [511:0] data
  );
    chiCacheStateE nextState;
    nextState = CACHE_I;
    if (opcode == REQ_EVICT || opcode == REQ_WRITE_BACK_FULL
        || opcode == REQ_WRITE_CLEAN_FULL || opcode == REQ_MAKE_UNIQUE)
      nextState = (opcode == REQ_MAKE_UNIQUE) ? CACHE_UC : CACHE_I;
    else if (resp == RESP_SC || resp == RESP_SC_PD)
      nextState = CACHE_SC;
    else if (resp == RESP_UC_UD)
      nextState = CACHE_UC;
    else if (resp == RESP_UC_PD)
      nextState = CACHE_UD;
    else if (resp == RESP_SD || resp == RESP_SD_PD)
      nextState = CACHE_SD;
    else if (opcode == REQ_CLEAN_UNIQUE)
      nextState = CACHE_UC;
    else
      nextState = CACHE_I;
    if (opcode inside {REQ_READ_ONCE, REQ_READ_NO_SNP, REQ_DVM_OP,
        REQ_PREFETCH_TGT, REQ_WRITE_UNIQUE_FULL, REQ_WRITE_UNIQUE_PTL,
        REQ_WRITE_NO_SNP_FULL, REQ_WRITE_NO_SNP_PTL,
        REQ_WRITE_UNIQUE_ZERO, REQ_WRITE_NO_SNP_ZERO})
      return;
    chiStoreLine(addr, nextState, data);
  endfunction

  function void chiPlanSnoop(
    input chiAddrT addr,
    input chiSnpOpcodeE opcode,
    input bit retToSrc,
    output chiCacheStateE finalState,
    output logic [RESP_W-1:0] resp,
    output bit withData,
    output logic [511:0] data
  );
    chiCacheStateE state;
    chiAddrT line;
    state = chiLookup(addr);
    line = chiLineAddr(addr);
    data = dataByLine.exists(line) ? dataByLine[line] : '0;
    withData = 1'b0;
    finalState = state;
    resp = RESP_I;
    case (opcode)
      SNP_UNIQUE, SNP_UNIQUE_FWD, SNP_MAKE_INVALID,
      SNP_CLEAN_INVALID, SNP_MAKE_INVALID_STASH: begin
        finalState = CACHE_I;
        if (chiIsDirty(state)) begin
          resp = RESP_I_PD;
          withData = 1'b1;
        end else if (retToSrc && chiHoldsData(state)) begin
          resp = RESP_I;
          withData = 1'b1;
        end else
          resp = RESP_I;
      end
      SNP_CLEAN, SNP_CLEAN_SHARED, SNP_CLEAN_FWD: begin
        if (state == CACHE_UD || state == CACHE_SD) begin
          finalState = CACHE_SC;
          resp = RESP_SC_PD;
          withData = 1'b1;
        end else if (chiHoldsData(state)) begin
          finalState = CACHE_SC;
          resp = RESP_SC;
          withData = retToSrc;
        end else
          resp = RESP_I;
      end
      SNP_ONCE, SNP_SHARED, SNP_QUERY, SNP_ONCE_FWD,
      SNP_SHARED_FWD, SNP_NOT_SHARED_DIRTY, SNP_NOT_SHARED_DIRTY_FWD,
      SNP_PREFER_UNIQUE, SNP_PREFER_UNIQUE_FWD: begin
        if (!chiHoldsData(state))
          resp = RESP_I;
        else if (state == CACHE_UD) begin
          resp = RESP_UC_PD;
          withData = 1'b1;
        end else if (state == CACHE_SD) begin
          resp = RESP_SD;
          withData = retToSrc;
        end else if (state == CACHE_UC) begin
          resp = RESP_UC_UD;
          withData = retToSrc;
        end else begin
          resp = RESP_SC;
          withData = retToSrc;
        end
      end
      default: begin
        resp = RESP_I;
        finalState = CACHE_I;
      end
    endcase
    chiStoreLine(addr, finalState, data);
  endfunction
endclass
