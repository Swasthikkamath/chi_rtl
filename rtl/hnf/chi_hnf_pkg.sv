// Types and decode functions shared by the HN-F blocks.
//
// The HN-F keeps one transaction entry per POS slot and decides, once at
// allocation, what kind of transaction a request is. Every later decision —
// which snoops to send, whether memory has to be read or written, which
// responses the Requester is owed and in what state — is a function of that
// kind, the opcode, and what the snoops return. Those functions live here so
// that the engine in chi_hnf_top, the assertions and later stages all use one
// definition.
package chi_hnf_pkg;
  import chi_cfg_pkg::*;
  import chi_pkg::*;

  localparam int unsigned CHI_LINE_BYTES = 64;

  // Life of a POS entry.
  typedef enum logic [1:0] {
    PH_FREE   = 2'd0,  // unused
    PH_WAIT   = 2'd1,  // allocated, not started: an older entry for the same
                       // location or an older ordered request from the same
                       // source is active, or the lookup port is busy
    PH_RUN    = 2'd2,  // started; obligations in progress
    PH_RETIRE = 2'd3   // obligations met; directory update outstanding
  } chi_hnf_phase_e;

  // What the Home does for a request, decided once at allocation.
  typedef enum logic [3:0] {
    HNF_KIND_READ       = 4'd0,  // allocating reads and MakeReadUnique
    HNF_KIND_READ_ONCE  = 4'd1,  // ReadOnce, ReadOnceCleanInvalid, ReadOnceMakeInvalid
    HNF_KIND_READ_NOSNP = 4'd2,  // ReadNoSnp
    HNF_KIND_DATALESS   = 4'd3,  // CleanUnique, MakeUnique, Evict
    HNF_KIND_CMO        = 4'd4,  // standalone cache maintenance
    HNF_KIND_STASH_ONCE = 4'd5,  // StashOnce*, StashOnceSep*
    HNF_KIND_WRITE      = 4'd6,  // Immediate writes, incl. stash and Combined
    HNF_KIND_WRITE_ZERO = 4'd7,  // WriteNoSnpZero, WriteUniqueZero
    HNF_KIND_WRITE_DEF  = 4'd8,  // WriteNoSnpDef, which an HN-F does not support
    HNF_KIND_COPYBACK   = 4'd9,  // CopyBack writes, incl. Combined
    HNF_KIND_ATOMIC     = 4'd10, // Atomic*
    HNF_KIND_ILLEGAL    = 4'd11  // not a request an HN-F accepts
  } chi_hnf_kind_e;

  // The cache maintenance a request carries, standalone or combined with a
  // write (IHI 0050H B4.2.2.1, B2.3.2.4-B2.3.2.6).
  typedef enum logic [2:0] {
    HNF_CMO_NONE          = 3'd0,
    HNF_CMO_CLEAN_SHARED  = 3'd1,  // CleanShared and the *CleanSh writes
    HNF_CMO_CLEAN_INVALID = 3'd2,  // CleanInvalid and the *CleanInv writes
    HNF_CMO_MAKE_INVALID  = 3'd3,  // MakeInvalid
    HNF_CMO_PERSIST       = 3'd4,  // CleanSharedPersist
    HNF_CMO_PERSIST_SEP   = 3'd5,  // CleanSharedPersistSep and *CleanShPerSep
    HNF_CMO_POPA          = 3'd6,  // CleanInvalidPoPA and *CleanInvPoPA
    HNF_CMO_STORAGE       = 3'd7   // CleanInvalidStorage and *CleanInvStrg
  } chi_hnf_cmo_e;

  // Errors found before the transaction starts. Each completes the
  // transaction with its normal message structure and NDERR, with no snoop,
  // memory or directory side effect (IHI 0050H B9.1.1, B9.1.3).
  typedef enum logic [2:0] {
    HNF_ERR_NONE        = 3'd0,
    HNF_ERR_ADDRESS     = 3'd1,  // no region maps the address
    HNF_ERR_PAS         = 3'd2,  // the region does not allow the request's PAS
    HNF_ERR_GPC         = 3'd3,  // granule protection check failed
    HNF_ERR_UNSUPPORTED = 3'd4   // the HN-F does not support the opcode
  } chi_hnf_err_e;

  // Downstream operation an owner asks the SN tracker for.
  typedef enum logic [1:0] {
    HNF_DN_READ   = 2'd0,  // ReadNoSnp into the owner's line buffer
    HNF_DN_WRITE  = 2'd1,  // a write from the buffer
    HNF_DN_CMO    = 2'd2,  // forwarded cache maintenance
    HNF_DN_ATOMIC = 2'd3   // a forwarded atomic: operand out, value back
  } chi_hnf_dn_e;

  function automatic logic isAtomicOpcode(input chi_req_opcode_e op);
    return ((op >= REQ_ATOMIC_STORE_ADD) && (op <= REQ_ATOMIC_LOAD_UMIN))
           || (op == REQ_ATOMIC_SWAP) || (op == REQ_ATOMIC_COMPARE);
  endfunction

  function automatic logic isAtomicStore(input chi_req_opcode_e op);
    return (op >= REQ_ATOMIC_STORE_ADD) && (op <= REQ_ATOMIC_STORE_UMIN);
  endfunction

  // IHI 0050H B1.4, Table B13.12.
  function automatic chi_hnf_kind_e hnfKind(input chi_req_opcode_e op);
    if (isAtomicOpcode(op)) return HNF_KIND_ATOMIC;
    case (op)
      REQ_READ_SHARED, REQ_READ_CLEAN, REQ_READ_NOT_SHARED_DIRTY,
      REQ_READ_UNIQUE, REQ_READ_PREFER_UNIQUE, REQ_MAKE_READ_UNIQUE:
        return HNF_KIND_READ;
      REQ_READ_ONCE, REQ_READ_ONCE_CLEAN_INVALID, REQ_READ_ONCE_MAKE_INVALID:
        return HNF_KIND_READ_ONCE;
      REQ_READ_NO_SNP:
        return HNF_KIND_READ_NOSNP;
      REQ_CLEAN_UNIQUE, REQ_MAKE_UNIQUE, REQ_EVICT:
        return HNF_KIND_DATALESS;
      REQ_CLEAN_SHARED, REQ_CLEAN_SHARED_PERSIST, REQ_CLEAN_SHARED_PERSIST_SEP,
      REQ_CLEAN_INVALID, REQ_CLEAN_INVALID_POPA, REQ_CLEAN_INVALID_STORAGE,
      REQ_MAKE_INVALID:
        return HNF_KIND_CMO;
      REQ_STASH_ONCE_SHARED, REQ_STASH_ONCE_UNIQUE,
      REQ_STASH_ONCE_SEP_SHARED, REQ_STASH_ONCE_SEP_UNIQUE:
        return HNF_KIND_STASH_ONCE;
      REQ_WRITE_NO_SNP_PTL, REQ_WRITE_NO_SNP_FULL,
      REQ_WRITE_UNIQUE_PTL, REQ_WRITE_UNIQUE_FULL,
      REQ_WRITE_UNIQUE_FULL_STASH, REQ_WRITE_UNIQUE_PTL_STASH,
      REQ_WRITE_NO_SNP_FULL_CLEAN_SH, REQ_WRITE_NO_SNP_FULL_CLEAN_INV,
      REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP,
      REQ_WRITE_UNIQUE_FULL_CLEAN_SH, REQ_WRITE_UNIQUE_FULL_CLEAN_SH_PER_SEP,
      REQ_WRITE_UNIQUE_FULL_CLEAN_INV_STRG,
      REQ_WRITE_NO_SNP_PTL_CLEAN_SH, REQ_WRITE_NO_SNP_PTL_CLEAN_INV,
      REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP,
      REQ_WRITE_UNIQUE_PTL_CLEAN_SH, REQ_WRITE_UNIQUE_PTL_CLEAN_SH_PER_SEP,
      REQ_WRITE_NO_SNP_PTL_CLEAN_INV_POPA, REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA,
      REQ_WRITE_NO_SNP_FULL_CLEAN_INV_STRG:
        return HNF_KIND_WRITE;
      REQ_WRITE_NO_SNP_ZERO, REQ_WRITE_UNIQUE_ZERO:
        return HNF_KIND_WRITE_ZERO;
      REQ_WRITE_NO_SNP_DEF:
        return HNF_KIND_WRITE_DEF;
      REQ_WRITE_BACK_FULL, REQ_WRITE_BACK_PTL, REQ_WRITE_CLEAN_FULL,
      REQ_WRITE_EVICT_FULL, REQ_WRITE_EVICT_OR_EVICT,
      REQ_WRITE_BACK_FULL_CLEAN_SH, REQ_WRITE_BACK_FULL_CLEAN_INV,
      REQ_WRITE_BACK_FULL_CLEAN_SH_PER_SEP, REQ_WRITE_BACK_FULL_CLEAN_INV_POPA,
      REQ_WRITE_BACK_FULL_CLEAN_INV_STRG,
      REQ_WRITE_CLEAN_FULL_CLEAN_SH, REQ_WRITE_CLEAN_FULL_CLEAN_SH_PER_SEP:
        return HNF_KIND_COPYBACK;
      default:
        return HNF_KIND_ILLEGAL;
    endcase
  endfunction

  function automatic chi_hnf_cmo_e hnfCmo(input chi_req_opcode_e op);
    case (op)
      REQ_CLEAN_SHARED,
      REQ_WRITE_NO_SNP_FULL_CLEAN_SH, REQ_WRITE_NO_SNP_PTL_CLEAN_SH,
      REQ_WRITE_UNIQUE_FULL_CLEAN_SH, REQ_WRITE_UNIQUE_PTL_CLEAN_SH,
      REQ_WRITE_BACK_FULL_CLEAN_SH, REQ_WRITE_CLEAN_FULL_CLEAN_SH:
        return HNF_CMO_CLEAN_SHARED;
      REQ_CLEAN_INVALID,
      REQ_WRITE_NO_SNP_FULL_CLEAN_INV, REQ_WRITE_NO_SNP_PTL_CLEAN_INV,
      REQ_WRITE_BACK_FULL_CLEAN_INV:
        return HNF_CMO_CLEAN_INVALID;
      REQ_MAKE_INVALID:
        return HNF_CMO_MAKE_INVALID;
      REQ_CLEAN_SHARED_PERSIST:
        return HNF_CMO_PERSIST;
      REQ_CLEAN_SHARED_PERSIST_SEP,
      REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP, REQ_WRITE_NO_SNP_PTL_CLEAN_SH_PER_SEP,
      REQ_WRITE_UNIQUE_FULL_CLEAN_SH_PER_SEP, REQ_WRITE_UNIQUE_PTL_CLEAN_SH_PER_SEP,
      REQ_WRITE_BACK_FULL_CLEAN_SH_PER_SEP, REQ_WRITE_CLEAN_FULL_CLEAN_SH_PER_SEP:
        return HNF_CMO_PERSIST_SEP;
      REQ_CLEAN_INVALID_POPA,
      REQ_WRITE_NO_SNP_PTL_CLEAN_INV_POPA, REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA,
      REQ_WRITE_BACK_FULL_CLEAN_INV_POPA:
        return HNF_CMO_POPA;
      REQ_CLEAN_INVALID_STORAGE,
      REQ_WRITE_UNIQUE_FULL_CLEAN_INV_STRG, REQ_WRITE_NO_SNP_FULL_CLEAN_INV_STRG,
      REQ_WRITE_BACK_FULL_CLEAN_INV_STRG:
        return HNF_CMO_STORAGE;
      default:
        return HNF_CMO_NONE;
    endcase
  endfunction

  // A CMO that removes every cached copy.
  function automatic logic cmoInvalidates(input chi_hnf_cmo_e cmo);
    return (cmo == HNF_CMO_CLEAN_INVALID) || (cmo == HNF_CMO_MAKE_INVALID)
           || (cmo == HNF_CMO_POPA) || (cmo == HNF_CMO_STORAGE);
  endfunction

  // A CMO whose point of completion is downstream of the Home: the Point of
  // Persistence and the Point of Physical Storage are in or behind the SN-F,
  // so the Home forwards these (IHI 0050H B4.2.2.2, B2.3.5 alt 3c).
  // CMOs whose point lies at or behind the Subordinate: the PoP, the PoPA and
  // the PoPS. A Home forwards them once its own copies are clean
  // (IHI 0050H B2.3.9.5, B4.2.2.1); the PoC is at the Home.
  function automatic logic cmoForwarded(input chi_hnf_cmo_e cmo);
    return (cmo == HNF_CMO_PERSIST) || (cmo == HNF_CMO_PERSIST_SEP)
           || (cmo == HNF_CMO_POPA) || (cmo == HNF_CMO_STORAGE);
  endfunction

  function automatic chi_req_opcode_e cmoDownstreamOpcode(input chi_hnf_cmo_e cmo);
    case (cmo)
      HNF_CMO_PERSIST:     return REQ_CLEAN_SHARED_PERSIST;
      HNF_CMO_PERSIST_SEP: return REQ_CLEAN_SHARED_PERSIST_SEP;
      HNF_CMO_POPA:        return REQ_CLEAN_INVALID_POPA;
      default:             return REQ_CLEAN_INVALID_STORAGE;
    endcase
  endfunction

  // The writes that come from a Requester holding no copy, so every other
  // copy must be invalidated (IHI 0050H B4.2.3, Table B4.26).
  function automatic logic isWriteUnique(input chi_req_opcode_e op);
    return op inside {REQ_WRITE_UNIQUE_PTL, REQ_WRITE_UNIQUE_FULL,
                      REQ_WRITE_UNIQUE_FULL_STASH, REQ_WRITE_UNIQUE_PTL_STASH,
                      REQ_WRITE_UNIQUE_FULL_CLEAN_SH,
                      REQ_WRITE_UNIQUE_FULL_CLEAN_SH_PER_SEP,
                      REQ_WRITE_UNIQUE_FULL_CLEAN_INV_STRG,
                      REQ_WRITE_UNIQUE_PTL_CLEAN_SH,
                      REQ_WRITE_UNIQUE_PTL_CLEAN_SH_PER_SEP,
                      REQ_WRITE_UNIQUE_ZERO};
  endfunction

  function automatic logic isFullLineWrite(input chi_req_opcode_e op);
    return op inside {REQ_WRITE_NO_SNP_FULL, REQ_WRITE_UNIQUE_FULL,
                      REQ_WRITE_UNIQUE_FULL_STASH,
                      REQ_WRITE_NO_SNP_FULL_CLEAN_SH,
                      REQ_WRITE_NO_SNP_FULL_CLEAN_INV,
                      REQ_WRITE_NO_SNP_FULL_CLEAN_SH_PER_SEP,
                      REQ_WRITE_UNIQUE_FULL_CLEAN_SH,
                      REQ_WRITE_UNIQUE_FULL_CLEAN_SH_PER_SEP,
                      REQ_WRITE_UNIQUE_FULL_CLEAN_INV_STRG,
                      REQ_WRITE_NO_SNP_FULL_CLEAN_INV_POPA,
                      REQ_WRITE_NO_SNP_FULL_CLEAN_INV_STRG,
                      REQ_WRITE_NO_SNP_ZERO, REQ_WRITE_UNIQUE_ZERO,
                      REQ_WRITE_BACK_FULL, REQ_WRITE_CLEAN_FULL,
                      REQ_WRITE_EVICT_FULL, REQ_WRITE_EVICT_OR_EVICT,
                      REQ_WRITE_BACK_FULL_CLEAN_SH, REQ_WRITE_BACK_FULL_CLEAN_INV,
                      REQ_WRITE_BACK_FULL_CLEAN_SH_PER_SEP,
                      REQ_WRITE_BACK_FULL_CLEAN_INV_POPA,
                      REQ_WRITE_BACK_FULL_CLEAN_INV_STRG,
                      REQ_WRITE_CLEAN_FULL_CLEAN_SH,
                      REQ_WRITE_CLEAN_FULL_CLEAN_SH_PER_SEP};
  endfunction

  function automatic logic isStashWrite(input chi_req_opcode_e op);
    return (op == REQ_WRITE_UNIQUE_FULL_STASH)
           || (op == REQ_WRITE_UNIQUE_PTL_STASH);
  endfunction

  // A CopyBack that leaves the Requester without a copy, as opposed to
  // WriteCleanFull, after which it keeps a clean one (IHI 0050H B4.2.3).
  function automatic logic copyBackDeallocates(input chi_req_opcode_e op);
    return !(op inside {REQ_WRITE_CLEAN_FULL, REQ_WRITE_CLEAN_FULL_CLEAN_SH,
                        REQ_WRITE_CLEAN_FULL_CLEAN_SH_PER_SEP});
  endfunction

  // The snoop each request sends to the RN-Fs that are not a stash target
  // (IHI 0050H Table B4.26, B4.4.2). SnpMakeInvalid is only legal when no
  // Snoopee can hold Dirty tags, which is guaranteed when MTE is not
  // supported anywhere; otherwise the invalidating snoop is SnpCleanInvalid.
  function automatic chi_snp_opcode_e snoopForRequest(
    input chi_req_opcode_e op,
    input logic mteEn
  );
    if (isAtomicOpcode(op)) return SNP_UNIQUE;
    case (op)
      REQ_READ_SHARED:           return SNP_SHARED;
      REQ_READ_CLEAN:            return SNP_CLEAN;
      REQ_READ_NOT_SHARED_DIRTY: return SNP_NOT_SHARED_DIRTY;
      REQ_READ_PREFER_UNIQUE:    return SNP_PREFER_UNIQUE;
      REQ_READ_UNIQUE:           return SNP_UNIQUE;
      REQ_MAKE_READ_UNIQUE:      return SNP_CLEAN_INVALID;
      REQ_READ_ONCE, REQ_READ_ONCE_CLEAN_INVALID, REQ_READ_ONCE_MAKE_INVALID:
        return SNP_ONCE;
      REQ_CLEAN_UNIQUE:          return SNP_CLEAN_INVALID;
      REQ_CLEAN_SHARED, REQ_CLEAN_SHARED_PERSIST, REQ_CLEAN_SHARED_PERSIST_SEP:
        return SNP_CLEAN_SHARED;
      REQ_CLEAN_INVALID, REQ_CLEAN_INVALID_POPA, REQ_CLEAN_INVALID_STORAGE:
        return SNP_CLEAN_INVALID;
      REQ_MAKE_UNIQUE, REQ_MAKE_INVALID, REQ_WRITE_UNIQUE_ZERO:
        return mteEn ? SNP_CLEAN_INVALID : SNP_MAKE_INVALID;
      default: begin
        // Writes: a full-line write replaces the line outright; a partial
        // write needs any dirty copy back so the line can be merged.
        if (isFullLineWrite(op))
          return mteEn ? SNP_CLEAN_INVALID : SNP_MAKE_INVALID;
        return SNP_CLEAN_INVALID;
      end
    endcase
  endfunction

  // Snoop opcodes after which the Snoopee keeps no copy.
  function automatic logic snoopInvalidates(input chi_snp_opcode_e op);
    return op inside {SNP_UNIQUE, SNP_CLEAN_INVALID, SNP_MAKE_INVALID,
                      SNP_UNIQUE_STASH, SNP_MAKE_INVALID_STASH,
                      SNP_UNIQUE_FWD};
  endfunction

  // Whether a read may take the line in a Dirty state, given whether any
  // other RN-F keeps a copy after the snoops (IHI 0050H Table B4.27, B4.7.1).
  function automatic logic readTakesDirty(
    input chi_req_opcode_e op,
    input logic othersKeep
  );
    case (op)
      REQ_READ_UNIQUE, REQ_MAKE_READ_UNIQUE, REQ_READ_SHARED,
      REQ_READ_PREFER_UNIQUE:
        return 1'b1;
      REQ_READ_NOT_SHARED_DIRTY:
        return !othersKeep;
      default:
        return 1'b0;
    endcase
  endfunction

  // The Resp of the CompData a read returns (IHI 0050H Table B4.27). dirty
  // means the data carries the responsibility for a Dirty line that the
  // Requester is taking; a read that cannot take it has had the line written
  // back and passes clean data.
  function automatic chi_resp_e readCompResp(
    input chi_req_opcode_e op,
    input logic othersKeep,
    input logic dirty
  );
    case (op)
      REQ_READ_UNIQUE, REQ_MAKE_READ_UNIQUE:
        return dirty ? RESP_UD_PD : RESP_UC_UD;
      REQ_READ_SHARED, REQ_READ_PREFER_UNIQUE:
        if (othersKeep) return dirty ? RESP_SD_PD : RESP_SC;
        else            return dirty ? RESP_UD_PD : RESP_UC_UD;
      REQ_READ_NOT_SHARED_DIRTY:
        if (othersKeep) return RESP_SC;
        else            return dirty ? RESP_UD_PD : RESP_UC_UD;
      REQ_READ_CLEAN:
        return othersKeep ? RESP_SC : RESP_UC_UD;
      default:
        return RESP_I;
    endcase
  endfunction

  // Snoop response Resp[1:0] is the Snoopee's final state: I, SC, UC/UD, SD
  // (IHI 0050H B13.10.46).
  function automatic logic snoopeeKeeps(input chi_resp_e resp);
    return resp[1:0] != 2'b00;
  endfunction

  function automatic logic snoopeeOwns(input chi_resp_e resp);
    return (resp[1:0] == 2'b10) || (resp[1:0] == 2'b11);
  endfunction

  function automatic logic isSnoopResponse(input chi_rsp_opcode_e op);
    return (op == RSP_SNP_RESP) || (op == RSP_SNP_RESP_FWDED);
  endfunction

  function automatic logic isSnoopData(input chi_dat_opcode_e op);
    return (op == DAT_SNP_RESP_DATA) || (op == DAT_SNP_RESP_DATA_PTL)
           || (op == DAT_SNP_RESP_DATA_FWDED);
  endfunction

  function automatic logic isRequesterData(input chi_dat_opcode_e op);
    return (op == DAT_COPY_BACK_WR_DATA) || (op == DAT_NON_COPY_BACK_WR_DATA)
           || (op == DAT_NCB_WR_DATA_COMP_ACK) || (op == DAT_WRITE_DATA_CANCEL);
  endfunction

  // Number of DataID granules (16 bytes each) one DAT packet covers.
  function automatic int unsigned granulesPerBeat(input chi_cfg_t cfg);
    return datIdStep(cfg);
  endfunction

  // Granule mask a packet with this DataID fills.
  function automatic logic [3:0] beatGranules(
    input chi_cfg_t cfg,
    input logic [1:0] dataId
  );
    logic [3:0] mask;
    int unsigned step;
    step = datIdStep(cfg);
    mask = '0;
    for (int unsigned g = 0; g < 4; g++)
      if ((g >= int'(dataId)) && (g < (int'(dataId) + step)))
        mask[g] = 1'b1;
    return mask;
  endfunction

  // Granules a transfer of 1 << size bytes at addr occupies.
  function automatic logic [3:0] transferGranules(
    input logic [CHI_MAX_ADDR_W-1:0] addr,
    input logic [2:0] size
  );
    logic [3:0] mask;
    int unsigned first;
    int unsigned last;
    int unsigned bytes;
    bytes = 32'd1 << size;
    first = (32'(addr[5:0]) & ~(bytes - 1)) / 16;
    last = ((32'(addr[5:0]) & ~(bytes - 1)) + bytes - 1) / 16;
    mask = '0;
    for (int unsigned g = 0; g < 4; g++)
      if ((g >= first) && (g <= last))
        mask[g] = 1'b1;
    return mask;
  endfunction

  // Granule mask a data message needs before it is complete, rounded out to
  // whole packets of the configured data bus.
  function automatic logic [3:0] messageGranules(
    input chi_cfg_t cfg,
    input logic [CHI_MAX_ADDR_W-1:0] addr,
    input logic [2:0] size
  );
    logic [3:0] mask;
    logic [3:0] needed;
    int unsigned step;
    int unsigned base;
    step = datIdStep(cfg);
    needed = transferGranules(addr, size);
    mask = '0;
    for (int unsigned g = 0; g < 4; g++)
      if (needed[g]) begin
        base = (g / step) * step;
        for (int unsigned k = 0; k < step; k++)
          mask[base + k] = 1'b1;
      end
    return mask;
  endfunction

  // DataCheck is odd parity over each byte of the data field
  // (IHI 0050H B9.2.2).
  function automatic logic [63:0] dataCheckOf(input logic [511:0] data);
    logic [63:0] check;
    for (int unsigned b = 0; b < 64; b++)
      check[b] = ~(^data[b*8 +: 8]);
    return check;
  endfunction
endpackage
