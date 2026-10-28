// Response-state, data and error assertions of the Homes (IHI 0050H B2.9.3,
// B4.7.1, B9.2), and the SLC side of a directory eviction.
//
// HN-F (chi_hnf_correctness_sva):
//   READ_DATA_STATE_LEGAL  CompData to a Requester carries a state its read
//       may be given (Table B4.38, Tables B4.41 and B4.42): ReadClean SC or
//       UC; ReadNotSharedDirty and ReadPreferUnique SC, UC or UD_PD;
//       ReadShared SC, UC, SD_PD or UD_PD; ReadUnique UC or UD_PD;
//       MakeReadUnique SC, UC or UD_PD; ReadNoSnp, ReadOnce and
//       ReadOnceCleanInvalid I or UC; ReadOnceMakeInvalid I, UC or UD_PD.
//   MAKE_READ_UNIQUE_COMP_STATE_LEGAL  a Comp to MakeReadUnique is SC, UC
//       or UD_PD (Tables B4.41, B4.42).
//   WRITE_DATA_ZERO_WHERE_DISABLED  a byte of write data the Home sends with
//       BE 0 is 0 (B2.9.3).
//   REQUESTER_BE_IN_WINDOW  Requester write data enables no byte outside the
//       window its Addr and Size give (B2.9.3.1). The Home tolerates a
//       violation by not taking those bytes; this reports it.
//   WRITE_DATA_CANCEL_PERMITTED  WriteDataCancel answers only a write that
//       may be cancelled: not WriteNoSnpFull, WriteUniqueFull(Stash) or a
//       CopyBack (Table B4.44). The Home writes nothing either way; this
//       reports a Requester that cancels such a write.
//   POISON_KEPT_UNDER_PARTIAL_WRITE  a poisoned 64-bit word stays poisoned
//       when the Requester writes only part of it (B9.2.1).
//   DATACHECK_ERROR_KEPT  a DataCheck error on a byte the Home keeps leaves
//       its word poisoned, or, without Poison, the line marked for DERR
//       (B9.2.3).
//   DIRECTORY_EVICTION_RECONCILES_SLC  with an SLC, a directory eviction
//       that collected Dirty data writes memory only once it has found that
//       the SLC does not hold the line, and frees only once the SLC has taken
//       the merged line when it does.
//
// Covers: ReadShared granted SD_PD, ReadPreferUnique granted UD_PD,
// MakeReadUnique answered Comp_UD_PD, a partial write over a poisoned word,
// a DataCheck error kept, a directory eviction whose Dirty data the SLC
// takes.
//
// HN-I (chi_hni_correctness_sva):
//   WRITE_DATA_ZERO_WHERE_DISABLED  as above, for the HN-I's write data.
// Covers: a DataCheck error kept.
module chi_hnf_correctness_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned POS_W = 1,
  parameter int unsigned OWNER_W = 1,
  parameter int unsigned NUM_OWNERS = 1,
  parameter int unsigned NUM_VB = 1
) (
  input logic clk,
  input logic resetn,
  input logic datEntrySend,
  input logic datEntryToPull,
  input chi_pkg::chi_req_opcode_e datEntryOpcode,
  input chi_pkg::chi_noc_flit_t datPushFlit,
  input logic rspEntrySend,
  input chi_pkg::chi_req_opcode_e rspEntryOpcode,
  input chi_pkg::chi_noc_flit_t rspPushFlit,
  input logic datTrackerSend,
  input chi_pkg::chi_noc_flit_t dnDatFlit,
  input logic wrDatMerge,
  input logic wrDatValid,
  input chi_pkg::chi_dat_opcode_e datInOpcode,
  input chi_pkg::chi_req_opcode_e wrDatEntryOpcode,
  input logic [POS_W-1:0] wrDatEntry,
  input logic [1:0] datInDataId,
  input logic [63:0] datInBe,
  input logic [63:0] wrDatBeatBe,
  input logic datInTaken,
  input logic [OWNER_W-1:0] datInOwner,
  input logic [7:0] dcWords,
  input logic [NUM_OWNERS-1:0][7:0] bufPoisonPacked,
  input logic [NUM_OWNERS-1:0] bufDataErr,
  input logic [NUM_VB-1:0] vValid,
  input logic [NUM_VB-1:0] vFromSf,
  input logic [NUM_VB-1:0] vSlcChecked,
  input logic [NUM_VB-1:0] vSlcHeld,
  input logic [NUM_VB-1:0] vSlcWritten,
  input logic [NUM_VB-1:0] vDnStart,
  input logic slcUpdateValid,
  input logic slcUpdateReady,
  input logic slcUpdateForVictim
);
  import chi_pkg::*;

  localparam int unsigned DAT_BYTES = CFG.dataW / 8;
  localparam int unsigned POISON_PER_BEAT = CFG.dataW / 64;

  function automatic logic readStateLegal(
    input chi_req_opcode_e op,
    input chi_resp_e resp
  );
    case (op)
      REQ_READ_CLEAN:
        return resp inside {RESP_SC, RESP_UC_UD};
      REQ_READ_NOT_SHARED_DIRTY, REQ_READ_PREFER_UNIQUE:
        return resp inside {RESP_SC, RESP_UC_UD, RESP_UD_PD};
      REQ_READ_SHARED:
        return resp inside {RESP_SC, RESP_UC_UD, RESP_SD_PD, RESP_UD_PD};
      REQ_READ_UNIQUE:
        return resp inside {RESP_UC_UD, RESP_UD_PD};
      REQ_MAKE_READ_UNIQUE:
        return resp inside {RESP_SC, RESP_UC_UD, RESP_UD_PD};
      REQ_READ_NO_SNP, REQ_READ_ONCE, REQ_READ_ONCE_CLEAN_INVALID:
        return resp inside {RESP_I, RESP_UC_UD};
      REQ_READ_ONCE_MAKE_INVALID:
        return resp inside {RESP_I, RESP_UC_UD, RESP_UD_PD};
      default:
        return 1'b1;
    endcase
  endfunction

  function automatic logic disabledBytesZero(input chi_dat_flit_t data);
    for (int unsigned b = 0; b < DAT_BYTES; b++)
      if (!data.be[b] && (data.data[b*8 +: 8] != 8'h00))
        return 1'b0;
    return 1'b1;
  endfunction

  chi_dat_flit_t toRequester;
  chi_rsp_flit_t response;
  chi_dat_flit_t toSubordinate;
  logic compDataSent;
  logic mruCompSent;

  always_comb begin
    toRequester = unpackDatFlit(CFG, datPushFlit.payload[CHI_MAX_DAT_FLIT_W-1:0]);
    response = unpackRspFlit(CFG, rspPushFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    toSubordinate = unpackDatFlit(CFG, dnDatFlit.payload[CHI_MAX_DAT_FLIT_W-1:0]);
    compDataSent = datEntrySend && !datEntryToPull
                   && (toRequester.opcode == DAT_COMP_DATA)
                   && (toRequester.respErr != RESP_ERR_NDERR);
    mruCompSent = rspEntrySend && (response.opcode == RSP_COMP)
                  && (rspEntryOpcode == REQ_MAKE_READ_UNIQUE)
                  && (response.respErr != RESP_ERR_NDERR);
  end

  READ_DATA_STATE_LEGAL: assert property (
    @(posedge clk) disable iff (!resetn)
    compDataSent |-> readStateLegal(datEntryOpcode, toRequester.resp));

  MAKE_READ_UNIQUE_COMP_STATE_LEGAL: assert property (
    @(posedge clk) disable iff (!resetn)
    mruCompSent |-> response.resp inside {RESP_SC, RESP_UC_UD, RESP_UD_PD});

  WRITE_DATA_ZERO_WHERE_DISABLED: assert property (
    @(posedge clk) disable iff (!resetn)
    datTrackerSend |-> disabledBytesZero(toSubordinate));

  REQUESTER_BE_IN_WINDOW: assert property (
    @(posedge clk) disable iff (!resetn)
    wrDatMerge |-> ((datInBe[DAT_BYTES-1:0] & ~wrDatBeatBe[DAT_BYTES-1:0]) == '0));

  WRITE_DATA_CANCEL_PERMITTED: assert property (
    @(posedge clk) disable iff (!resetn)
    wrDatValid && (datInOpcode == DAT_WRITE_DATA_CANCEL)
      |-> !(wrDatEntryOpcode inside {
              REQ_WRITE_NO_SNP_FULL, REQ_WRITE_UNIQUE_FULL,
              REQ_WRITE_UNIQUE_FULL_STASH, REQ_WRITE_BACK_FULL,
              REQ_WRITE_BACK_PTL, REQ_WRITE_CLEAN_FULL,
              REQ_WRITE_EVICT_FULL, REQ_WRITE_EVICT_OR_EVICT}));

  for (genvar w = 0; w < POISON_PER_BEAT; w++) begin : per_word
    POISON_KEPT_UNDER_PARTIAL_WRITE: assert property (
      @(posedge clk) disable iff (!resetn)
      wrDatMerge
      && bufPoisonPacked[wrDatEntry][int'(datInDataId)*2 + w]
      && (wrDatBeatBe[w*8 +: 8] != 8'h00) && (wrDatBeatBe[w*8 +: 8] != 8'hff)
        |=> bufPoisonPacked[$past(wrDatEntry)][int'($past(datInDataId))*2 + w]);

    DATACHECK_ERROR_KEPT: assert property (
      @(posedge clk) disable iff (!resetn)
      datInTaken && dcWords[w]
        |=> (CFG.poisonEn
             ? bufPoisonPacked[$past(datInOwner)][int'($past(datInDataId))*2 + w]
             : bufDataErr[$past(datInOwner)]));

    PARTIAL_WRITE_OVER_POISON: cover property (
      @(posedge clk) disable iff (!resetn)
      wrDatMerge
      && bufPoisonPacked[wrDatEntry][int'(datInDataId)*2 + w]
      && (wrDatBeatBe[w*8 +: 8] != 8'h00) && (wrDatBeatBe[w*8 +: 8] != 8'hff));
  end

  for (genvar v = 0; v < NUM_VB; v++) begin : per_victim
    DIRECTORY_EVICTION_RECONCILES_SLC: assert property (
      @(posedge clk) disable iff (!resetn)
      (vDnStart[v]
         |-> !(CFG.slcEn && vFromSf[v] && (!vSlcChecked[v] || vSlcHeld[v])))
      and (vValid[v] && vSlcHeld[v] && !vSlcWritten[v] |=> vValid[v]));
  end

  READ_SHARED_SD_PD: cover property (
    @(posedge clk) disable iff (!resetn)
    compDataSent && (datEntryOpcode == REQ_READ_SHARED)
    && (toRequester.resp == RESP_SD_PD));

  READ_PREFER_UNIQUE_UD_PD: cover property (
    @(posedge clk) disable iff (!resetn)
    compDataSent && (datEntryOpcode == REQ_READ_PREFER_UNIQUE)
    && (toRequester.resp == RESP_UD_PD));

  MAKE_READ_UNIQUE_COMP_UD_PD: cover property (
    @(posedge clk) disable iff (!resetn)
    mruCompSent && (response.resp == RESP_UD_PD));

  DATACHECK_ERROR_SEEN: cover property (
    @(posedge clk) disable iff (!resetn)
    datInTaken && (dcWords != '0));

  DIRECTORY_EVICTION_INTO_SLC: cover property (
    @(posedge clk) disable iff (!resetn)
    slcUpdateValid && slcUpdateReady && slcUpdateForVictim);
endmodule

module chi_hni_correctness_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT
) (
  input logic clk,
  input logic resetn,
  input logic datTrackerSend,
  input chi_pkg::chi_noc_flit_t dnDatFlit,
  input logic wrDatValid,
  input logic snDatForEntry,
  input logic [7:0] dcWords
);
  import chi_pkg::*;

  localparam int unsigned DAT_BYTES = CFG.dataW / 8;

  function automatic logic disabledBytesZero(input chi_dat_flit_t data);
    for (int unsigned b = 0; b < DAT_BYTES; b++)
      if (!data.be[b] && (data.data[b*8 +: 8] != 8'h00))
        return 1'b0;
    return 1'b1;
  endfunction

  chi_dat_flit_t toSubordinate;
  always_comb
    toSubordinate = unpackDatFlit(CFG, dnDatFlit.payload[CHI_MAX_DAT_FLIT_W-1:0]);

  WRITE_DATA_ZERO_WHERE_DISABLED: assert property (
    @(posedge clk) disable iff (!resetn)
    datTrackerSend |-> disabledBytesZero(toSubordinate));

  DATACHECK_ERROR_SEEN: cover property (
    @(posedge clk) disable iff (!resetn)
    (wrDatValid || snDatForEntry) && (dcWords != '0));
endmodule

bind chi_hnf_top chi_hnf_correctness_sva #(
  .CFG(CFG),
  .POS_W(POS_W),
  .OWNER_W(OWNER_W),
  .NUM_OWNERS(NUM_OWNERS),
  .NUM_VB(NUM_VB)
) chi_hnf_correctness_assertions (
  .clk(clk),
  .resetn(resetn),
  .datEntrySend(datEntrySend),
  .datEntryToPull(datEntryToPull),
  .datEntryOpcode(datEntryOpcode),
  .datPushFlit(datPushFlit),
  .rspEntrySend(rspEntrySend),
  .rspEntryOpcode(rspEntryOpcode),
  .rspPushFlit(rspPushFlit),
  .datTrackerSend(datTrackerSend),
  .dnDatFlit(dnDatFlit),
  .wrDatMerge(wrDatMerge),
  .wrDatValid(wrDatValid),
  .datInOpcode(incomingDat.opcode),
  .wrDatEntryOpcode(wrDatEntryOpcode),
  .wrDatEntry(wrDatEntry),
  .datInDataId(incomingDat.dataId),
  .datInBe(incomingDat.be),
  .wrDatBeatBe(wrDatBeatBe),
  .datInTaken(datInTaken),
  .datInOwner(datInOwner),
  .dcWords(dcWords),
  .bufPoisonPacked(bufPoisonPacked),
  .bufDataErr(bufDataErr),
  .vValid(vValid),
  .vFromSf(vFromSf),
  .vSlcChecked(vSlcChecked),
  .vSlcHeld(vSlcHeld),
  .vSlcWritten(vSlcWritten),
  .vDnStart(vDnStart),
  .slcUpdateValid(slcUpdateValid),
  .slcUpdateReady(slcUpdateReady),
  .slcUpdateForVictim(slcUpdateForVictim)
);

bind chi_hni_top chi_hni_correctness_sva #(
  .CFG(CFG)
) chi_hni_correctness_assertions (
  .clk(clk),
  .resetn(resetn),
  .datTrackerSend(datTrackerSend),
  .dnDatFlit(dnDatFlit),
  .wrDatValid(wrDatValid),
  .snDatForEntry(snDatForEntry),
  .dcWords(dcWords)
);
