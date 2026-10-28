// Direct transfer assertions (IHI 0050H B2.3.1.1, B2.3.2.1, B2.5.1, B6.3.1).
//
//   DIRECT_DATA_BYPASSES_HOME  no data of a DCT, DMT or DWT transaction
//       passes the Home's DAT ports: the Home never sends CompData for a
//       forwarded or DMT read, never receives memory data for a DMT read,
//       and never receives or sends the write data of a DWT write.
//   DMT_AFTER_SNOOPS  a DMT read is issued only once the entry's snoops have
//       completed.
//   RESP_SEP_DATA_FOR_DMT_SEP  RespSepData answers only a ReadNoSnpSep DMT
//       read, after the ReadReceipt that shows the SN-F accepted it, in the
//       UC state of the SN-F's DataSepResp (B2.3.1.1 alt 4, B4.5.1.1,
//       B4.7.1).
//   DWT_NO_DATA_REQUEST_FROM_HOME  the Home never sends DBIDResp or
//       CompDBIDResp for a DWT write; the SN-F asks for the data.
//   EXCLUSIVE_NOT_DIRECT  an Exclusive access uses neither DMT nor DCT, and
//       an Exclusive Store does not use DWT (B6.3.1).
//   DWT_NOT_ON_SLC_LINE  DWT is never used for a line the SLC holds or is
//       allocating, so no SLC copy can be stale after it.
//
// Covers: each forwarding snoop, a forwarded read, a forwarding snoop the
// owner declined (the fallback), DMT by ReadNoSnp and by ReadNoSnpSep, a DWT
// write and the SN-F's Comp for it, CompDBIDResp and separate DBIDResp and
// Comp for a write through the Home, WriteDataCancel at the Home.
module chi_direct_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned POS_DEPTH = 1,
  parameter int unsigned POS_W = 1,
  parameter int unsigned OWNER_W = 1,
  parameter int unsigned TRK_W = 1
) (
  input logic clk,
  input logic resetn,
  input logic [POS_DEPTH-1:0] eDmtUsed,
  input logic [POS_DEPTH-1:0] eDmtSep,
  input logic [POS_DEPTH-1:0] eDnReadDone,
  input logic [POS_DEPTH-1:0] eDwtUsed,
  input logic [POS_DEPTH-1:0] eDnWriting,
  input logic [POS_DEPTH-1:0] eDctPlanned,
  input logic [POS_DEPTH-1:0] eDctFwded,
  input logic [POS_DEPTH-1:0] eDmtOk,
  input logic [POS_DEPTH-1:0] eSnpDone,
  input logic [POS_DEPTH-1:0] eExclLoad,
  input logic [POS_DEPTH-1:0] eExclStore,
  input logic [POS_DEPTH-1:0] eSlcLine,
  input logic [POS_DEPTH-1:0] dnStartValid,
  input chi_hnf_pkg::chi_hnf_dn_e [POS_DEPTH-1:0] dnStartKind,
  input logic datEntrySend,
  input logic datEntryToPull,
  input logic [POS_W-1:0] datEntry,
  input logic wrDatValid,
  input logic [POS_W-1:0] wrDatEntry,
  input chi_pkg::chi_dat_opcode_e wrDatOpcode,
  input logic memDatValid,
  input logic [OWNER_W-1:0] memDatOwner,
  input logic datTrackerSend,
  input logic [TRK_W-1:0] dnDatOwner,
  input logic rspEntrySend,
  input logic [POS_W-1:0] rspEntry,
  input chi_pkg::chi_noc_flit_t rspPushFlit,
  input logic snRspValid,
  input chi_pkg::chi_rsp_flit_t snRsp,
  input logic snpOutValid,
  input logic snpOutReady,
  input chi_pkg::chi_noc_flit_t snpOutFlit
);
  import chi_pkg::*;
  import chi_hnf_pkg::*;

  chi_rsp_flit_t pushed;
  chi_snp_flit_t snoop;
  logic snRspForEntry;
  logic [POS_W-1:0] snRspEntry;

  always_comb begin
    pushed = unpackRspFlit(CFG, rspPushFlit.payload[CHI_MAX_RSP_FLIT_W-1:0]);
    snoop = unpackSnpFlit(CFG, snpOutFlit.payload[CHI_MAX_SNP_FLIT_W-1:0]);
    snRspForEntry = snRspValid && (int'(snRsp.txnId) < POS_DEPTH);
    snRspEntry = POS_W'(snRsp.txnId);
  end

  DIRECT_DATA_BYPASSES_HOME: assert property (
    @(posedge clk) disable iff (!resetn)
    (datEntrySend && !datEntryToPull
       |-> !(eDmtUsed[datEntry] || eDctFwded[datEntry]))
    and (wrDatValid |-> !eDwtUsed[wrDatEntry])
    and (memDatValid && (int'(memDatOwner) < POS_DEPTH)
           |-> !eDmtUsed[POS_W'(memDatOwner)])
    and (datTrackerSend && (int'(dnDatOwner) < POS_DEPTH)
           |-> !eDwtUsed[POS_W'(dnDatOwner)]));

  RESP_SEP_DATA_FOR_DMT_SEP: assert property (
    @(posedge clk) disable iff (!resetn)
    rspEntrySend && (pushed.opcode == RSP_RESP_SEP_DATA)
      |-> eDmtSep[rspEntry] && eDnReadDone[rspEntry]
          && (pushed.resp == RESP_UC_UD));

  DWT_NO_DATA_REQUEST_FROM_HOME: assert property (
    @(posedge clk) disable iff (!resetn)
    rspEntrySend
    && ((pushed.opcode == RSP_DBID_RESP) || (pushed.opcode == RSP_COMP_DBID_RESP))
      |-> !eDwtUsed[rspEntry]);

  for (genvar i = 0; i < POS_DEPTH; i++) begin : per_entry
    DMT_AFTER_SNOOPS: assert property (
      @(posedge clk) disable iff (!resetn)
      dnStartValid[i] && (dnStartKind[i] == HNF_DN_READ) && eDmtOk[i]
        |-> eSnpDone[i]);

    EXCLUSIVE_NOT_DIRECT: assert property (
      @(posedge clk) disable iff (!resetn)
      ((eDmtUsed[i] || eDctPlanned[i]) |-> !(eExclLoad[i] || eExclStore[i]))
      and (eDwtUsed[i] |-> !eExclStore[i]));

    DWT_NOT_ON_SLC_LINE: assert property (
      @(posedge clk) disable iff (!resetn)
      eDwtUsed[i] |-> !eSlcLine[i]);
  end

  // Every forwarding snoop the protocol defines (IHI 0050H Table B4.26).
  localparam int unsigned NUM_FWD = 6;
  localparam chi_snp_opcode_e FWD_SNOOPS [NUM_FWD] = '{
    SNP_SHARED_FWD, SNP_CLEAN_FWD, SNP_ONCE_FWD, SNP_NOT_SHARED_DIRTY_FWD,
    SNP_PREFER_UNIQUE_FWD, SNP_UNIQUE_FWD
  };
  for (genvar f = 0; f < NUM_FWD; f++) begin : per_forwarding_snoop
    FORWARDING_SNOOP_SENT: cover property (
      @(posedge clk) disable iff (!resetn)
      snpOutValid && snpOutReady && (snoop.opcode == FWD_SNOOPS[f]));
  end

  DCT_FORWARDED: cover property (
    @(posedge clk) disable iff (!resetn)
    eDctFwded != '0);

  DCT_FALLBACK: cover property (
    @(posedge clk) disable iff (!resetn)
    (eDctPlanned & eSnpDone & ~eDctFwded) != '0);

  DMT_COMBINED: cover property (
    @(posedge clk) disable iff (!resetn)
    (eDmtUsed & ~eDmtSep) != '0);

  DMT_SEPARATE: cover property (
    @(posedge clk) disable iff (!resetn)
    rspEntrySend && (pushed.opcode == RSP_RESP_SEP_DATA));

  DWT_USED: cover property (
    @(posedge clk) disable iff (!resetn)
    eDwtUsed != '0);

  DWT_COMP_FROM_SUBORDINATE: cover property (
    @(posedge clk) disable iff (!resetn)
    snRspForEntry && (snRsp.opcode == RSP_COMP) && eDwtUsed[snRspEntry]);

  WRITE_COMP_DBID_RESP: cover property (
    @(posedge clk) disable iff (!resetn)
    snRspForEntry && (snRsp.opcode == RSP_COMP_DBID_RESP)
    && eDnWriting[snRspEntry]);

  WRITE_SEPARATE_DBID_RESP: cover property (
    @(posedge clk) disable iff (!resetn)
    snRspForEntry && (snRsp.opcode == RSP_DBID_RESP) && eDnWriting[snRspEntry]);

  WRITE_SEPARATE_COMP: cover property (
    @(posedge clk) disable iff (!resetn)
    snRspForEntry && (snRsp.opcode == RSP_COMP) && eDnWriting[snRspEntry]
    && !eDwtUsed[snRspEntry]);

  WRITE_DATA_CANCEL_AT_HOME: cover property (
    @(posedge clk) disable iff (!resetn)
    wrDatValid && (wrDatOpcode == DAT_WRITE_DATA_CANCEL));
endmodule

bind chi_hnf_top chi_direct_sva #(
  .CFG(CFG),
  .POS_DEPTH(POS_DEPTH),
  .POS_W(POS_W),
  .OWNER_W(OWNER_W),
  .TRK_W(TRK_W)
) chi_hnf_direct_assertions (
  .clk(clk),
  .resetn(resetn),
  .eDmtUsed(eDmtUsed),
  .eDmtSep(eDmtSep),
  .eDnReadDone(eDnReadDone),
  .eDwtUsed(eDwtUsed),
  .eDnWriting(eDnWriting),
  .eDctPlanned(eDctPlanned),
  .eDctFwded(eDctFwded),
  .eDmtOk(eDmtOk),
  .eSnpDone(eSnpDone),
  .eExclLoad(eExclLoad),
  .eExclStore(eExclStore),
  .eSlcLine(eSlcLine),
  .dnStartValid(dnStartValid[POS_DEPTH-1:0]),
  .dnStartKind(dnStartKind[POS_DEPTH-1:0]),
  .datEntrySend(datEntrySend),
  .datEntryToPull(datEntryToPull),
  .datEntry(datEntry),
  .wrDatValid(wrDatValid),
  .wrDatEntry(wrDatEntry),
  .wrDatOpcode(incomingDat.opcode),
  .memDatValid(memDatValid),
  .memDatOwner(memDatOwner),
  .datTrackerSend(datTrackerSend),
  .dnDatOwner(dnDatOwner),
  .rspEntrySend(rspEntrySend),
  .rspEntry(rspEntry),
  .rspPushFlit(rspPushFlit),
  .snRspValid(snRspValid),
  .snRsp(incomingRsp),
  .snpOutValid(snpOutValid),
  .snpOutReady(snpOutReady),
  .snpOutFlit(snpOutFlit)
);
