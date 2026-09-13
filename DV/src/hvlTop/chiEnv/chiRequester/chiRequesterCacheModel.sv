// Cache state for one fully coherent Requester.
//
// This is the state an RN-F is obliged to keep, not a performance model. Its
// job is to make the agent behave like a real caching master: pick an opcode
// that suits the state it already holds, answer a snoop with the transition
// the spec requires, and give up a line when it runs out of room.
//
// Only an RN-F has one. An I/O coherent Requester holds no cacheable state and
// is never snooped [SPEC:IHI0050H B1.6.1], so its agent leaves this null.
//
// The organisation is fully associative with a bounded line count, held in
// associative arrays keyed by line address. A set-associative model would add
// index and way bookkeeping without changing any protocol decision, since CHI
// never sees the geometry; what it does see is a capacity eviction, and a
// bounded fully associative cache produces those. Replacement is
// least-recently-used over the lines that have no transaction in flight,
// because evicting a line that is mid-transaction would create a second
// outstanding request to the same address, which the protocol forbids
// [SPEC:IHI0050H B2.6.1].
class chiRequesterCacheModel extends uvm_object;

  // Lines this cache can hold. Small on purpose: the point is to provoke
  // evictions and the writebacks that follow them within a short test.
  int unsigned capacityLines = 32;

  protected chi_cache_state_e lineState     [chiLineAddrT];
  protected chiLineBytesT     lineData      [chiLineAddrT];
  protected bit               lineOutstanding [chiLineAddrT];
  protected int unsigned      lineUseStamp  [chiLineAddrT];
  protected int unsigned      useCounter;

  `uvm_object_utils(chiRequesterCacheModel)

  function new(string name = "chiRequesterCacheModel");
    super.new(name);
    useCounter = 0;
  endfunction

  // -------------------------------------------------------------------------
  // Lookup
  // -------------------------------------------------------------------------
  // A line that was never allocated reads as Invalid, which is what makes the
  // sparse array equivalent to a cache that starts empty.
  function chi_cache_state_e lookup(chiAddrT addr);
    chiLineAddrT line;
    line = lineAddrOf(addr);
    if (!lineState.exists(line)) return CACHE_I;
    return lineState[line];
  endfunction

  function bit isValid(chiAddrT addr);
    return (lookup(addr) != CACHE_I);
  endfunction

  // Unique means this is the only copy, so it can be written without telling
  // anyone [SPEC:IHI0050H B2.2].
  function bit isUnique(chiAddrT addr);
    chi_cache_state_e state;
    state = lookup(addr);
    return (state == CACHE_UC) || (state == CACHE_UD) || (state == CACHE_UDP);
  endfunction

  function bit isDirty(chiAddrT addr);
    chi_cache_state_e state;
    state = lookup(addr);
    return (state == CACHE_UD) || (state == CACHE_SD) || (state == CACHE_UDP);
  endfunction

  function bit isOutstanding(chiAddrT addr);
    chiLineAddrT line;
    line = lineAddrOf(addr);
    if (!lineOutstanding.exists(line)) return 1'b0;
    return lineOutstanding[line];
  endfunction

  function int unsigned occupancy();
    return lineState.num();
  endfunction

  // -------------------------------------------------------------------------
  // Transaction tracking
  // -------------------------------------------------------------------------
  // A Requester may not have two transactions outstanding to the same cache
  // line at once [SPEC:IHI0050H B2.6.1], so the driver marks a line before it
  // issues and clears it on completion.
  function void markOutstanding(chiAddrT addr);
    lineOutstanding[lineAddrOf(addr)] = 1'b1;
  endfunction

  function void clearOutstanding(chiAddrT addr);
    lineOutstanding[lineAddrOf(addr)] = 1'b0;
  endfunction

  function void touch(chiAddrT addr);
    useCounter++;
    lineUseStamp[lineAddrOf(addr)] = useCounter;
  endfunction

  // -------------------------------------------------------------------------
  // Data
  // -------------------------------------------------------------------------
  function void writeLine(chiAddrT addr, chiLineBytesT bytes);
    lineData[lineAddrOf(addr)] = bytes;
  endfunction

  function chiLineBytesT readLine(chiAddrT addr);
    chiLineBytesT bytes;
    chiLineAddrT  line;
    line = lineAddrOf(addr);
    if (lineData.exists(line)) return lineData[line];
    for (int unsigned i = 0; i < CHI_LINE_BYTES; i++) bytes[i] = '0;
    return bytes;
  endfunction

  // -------------------------------------------------------------------------
  // Allocation and replacement
  // -------------------------------------------------------------------------
  function bit isFull();
    return (lineState.num() >= capacityLines);
  endfunction

  // Least recently used line that has nothing in flight. Returns 0 when every
  // resident line is busy, which tells the driver to wait rather than evict.
  function bit selectVictim(output chiAddrT victimAddr);
    chiLineAddrT bestLine;
    int unsigned bestStamp;
    bit          found;
    found     = 1'b0;
    bestStamp = 0;
    foreach (lineState[line]) begin
      if (lineOutstanding.exists(line) && lineOutstanding[line]) continue;
      if (lineState[line] == CACHE_I) continue;
      if (!found || (lineUseStamp[line] < bestStamp)) begin
        found     = 1'b1;
        bestLine  = line;
        bestStamp = lineUseStamp.exists(line) ? lineUseStamp[line] : 0;
      end
    end
    if (found) victimAddr = {bestLine, {CHI_LINE_OFF_W{1'b0}}};
    return found;
  endfunction

  // Residency and the in-flight mark are tracked separately on purpose. A line
  // is allocated and invalidated in the middle of the very transaction that
  // holds the mark, and it is invalidated by snoops arriving while an unrelated
  // transaction is in flight, so neither may disturb the mark: only the driver
  // thread that took it releases it.
  function void allocate(chiAddrT addr, chi_cache_state_e state);
    chiLineAddrT line;
    line            = lineAddrOf(addr);
    lineState[line] = state;
    touch(addr);
  endfunction

  function void invalidate(chiAddrT addr);
    chiLineAddrT line;
    line = lineAddrOf(addr);
    if (lineState.exists(line))    lineState.delete(line);
    if (lineData.exists(line))     lineData.delete(line);
    if (lineUseStamp.exists(line)) lineUseStamp.delete(line);
  endfunction

  // -------------------------------------------------------------------------
  // Completion
  // -------------------------------------------------------------------------
  // The state a line ends up in after a read or write completes is carried in
  // the response rather than decided locally: Resp[1:0] names the state and
  // Resp[2] says whether the dirty responsibility came with it
  // [SPEC:IHI0050H B13.10.34, B4.4].
  function void updateOnCompletion(chiAddrT addr, chi_resp_e resp);
    chi_cache_state_e state;
    case (resp[1:0])
      2'b00:   state = CACHE_I;
      2'b01:   state = respPassDirty(resp) ? CACHE_SD : CACHE_SC;
      2'b10:   state = respPassDirty(resp) ? CACHE_UD : CACHE_UC;
      default: state = CACHE_SD;
    endcase
    if (state == CACHE_I) invalidate(addr);
    else                  allocate(addr, state);
  endfunction

  // A local write makes the line dirty. Unique-clean becomes unique-dirty;
  // shared states cannot be written without first gaining uniqueness, which
  // the driver arranges before calling this.
  function void markDirtyAfterStore(chiAddrT addr);
    chi_cache_state_e state;
    state = lookup(addr);
    if ((state == CACHE_UC) || (state == CACHE_UD) || (state == CACHE_UDP))
      allocate(addr, CACHE_UD);
  endfunction

  // -------------------------------------------------------------------------
  // Snoops
  // -------------------------------------------------------------------------
  // The transition a snoop forces, and what has to be returned with the
  // response [SPEC:IHI0050H B4.9, Table B4.9-B4.14].
  //
  // Two rules drive the whole table. A snoop that invalidates or downgrades a
  // dirty line must hand the dirty data back, because the Requester is giving
  // up the responsibility for it. A snoop with RetToSrc set asks for the data
  // even when the line is clean, so the Home can forward it
  // [SPEC:IHI0050H B2.13.3].
  function chiSnoopActionS snoopAction(chiAddrT addr, chi_snp_opcode_e opcode,
                                       bit retToSrc);
    chiSnoopActionS action;
    chi_cache_state_e state;

    state            = lookup(addr);
    action.nextState = state;
    action.sendData  = 1'b0;
    action.passDirty = 1'b0;
    action.respState = RESP_I;

    case (opcode)
      // Read the line without changing what this Requester holds.
      SNP_ONCE: begin
        action.nextState = state;
        action.sendData  = retToSrc && (state != CACHE_I);
      end

      // The requester wants a shared copy, so this one may keep a copy but
      // must not keep it exclusive.
      SNP_SHARED, SNP_NOT_SHARED_DIRTY: begin
        case (state)
          CACHE_I:   action.nextState = CACHE_I;
          CACHE_SC:  action.nextState = CACHE_SC;
          CACHE_UC:  action.nextState = CACHE_SC;
          // A dirty line stays dirty under SnpShared but must move to shared
          // dirty; under SnpNotSharedDirty it may not stay dirty at all, so
          // the dirty data goes back with the response.
          CACHE_UD, CACHE_UDP, CACHE_SD: begin
            if (opcode == SNP_SHARED) begin
              action.nextState = CACHE_SD;
              action.sendData  = retToSrc;
            end else begin
              action.nextState = CACHE_SC;
              action.sendData  = 1'b1;
              action.passDirty = 1'b1;
            end
          end
          default: action.nextState = CACHE_I;
        endcase
      end

      // The line must end up clean here, so any dirty data goes back.
      SNP_CLEAN, SNP_CLEAN_SHARED: begin
        case (state)
          CACHE_I:  action.nextState = CACHE_I;
          CACHE_SC: action.nextState = CACHE_SC;
          CACHE_UC: action.nextState = CACHE_SC;
          CACHE_UD, CACHE_UDP, CACHE_SD: begin
            action.nextState = CACHE_SC;
            action.sendData  = 1'b1;
            action.passDirty = 1'b1;
          end
          default: action.nextState = CACHE_I;
        endcase
      end

      // The requester wants the only copy, so this one gives it up entirely.
      SNP_UNIQUE, SNP_CLEAN_INVALID: begin
        action.nextState = CACHE_I;
        if (isDirty(addr)) begin
          action.sendData  = 1'b1;
          action.passDirty = 1'b1;
        end else begin
          action.sendData = retToSrc && (state != CACHE_I);
        end
      end

      // Invalidate without returning data. The requester is going to overwrite
      // the whole line, so the dirty copy here is simply discarded
      // [SPEC:IHI0050H B4.9.3].
      SNP_MAKE_INVALID: begin
        action.nextState = CACHE_I;
        action.sendData  = 1'b0;
      end

      default: begin
        action.nextState = state;
        action.sendData  = retToSrc && (state != CACHE_I);
      end
    endcase

    // The response reports the state the line is left in, with PassDirty in
    // bit 2 when the dirty responsibility is being handed over.
    case (action.nextState)
      CACHE_I:            action.respState = RESP_I;
      CACHE_SC:           action.respState = RESP_SC;
      CACHE_UC:           action.respState = RESP_UC_UD;
      CACHE_UD, CACHE_UDP: action.respState = RESP_UC_UD;
      CACHE_SD:           action.respState = RESP_SD;
      default:            action.respState = RESP_I;
    endcase
    if (action.passDirty)
      action.respState = chi_resp_e'(action.respState | 3'b100);

    return action;
  endfunction

  // Apply what snoopAction decided. Kept separate so the driver can build the
  // response from the same decision it then commits, rather than computing the
  // transition twice.
  function void applySnoop(chiAddrT addr, chiSnoopActionS action);
    if (action.nextState == CACHE_I) invalidate(addr);
    else                             allocate(addr, action.nextState);
  endfunction

  function string convert2string();
    return $sformatf("cache: %0d of %0d lines resident",
                     lineState.num(), capacityLines);
  endfunction
endclass
