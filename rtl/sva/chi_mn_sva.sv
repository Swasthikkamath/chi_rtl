// MN (DVM) assertions (IHI 0050H B8.2).
//
//   *_STABLE_UNDER_BACKPRESSURE  a presented flit holds until taken.
//   MN_INPUTS_ALWAYS_READY  snoop responses and DVM payloads are always
//       accepted.
//   MN_SYNC_AFTER_OLDER_OPERATIONS  a Sync sends its snoops only once every
//       older DVMOp has collected all its snoop responses (B8.2.2,
//       B8.2.1.1).
//   MN_ONE_SNOOP_OF_EACH_KIND_PER_TARGET  a Request Node is never sent a
//       second SnpDVMOp(Sync) or a second SnpDVMOp(Non-sync) while one of
//       that kind is outstanding to it (B8.2.3.2).
//   MN_NONSYNC_ENTRY_KEPT  the tracker is never full of Syncs, so a
//       Non-sync DVMOp can always make progress (B8.2.3.1).
//
// Covers: concurrent DVMOps, a Sync held behind older DVMOps, a GPT
// invalidation, RetryAck to a Requester.
module chi_mn_sva #(
  parameter int unsigned DEPTH = 1,
  parameter int unsigned NUM_DVM_NODES = 1,
  parameter int unsigned TGT_W = 1
) (
  input logic clk,
  input logic resetn,
  input logic reqInValid,
  input logic reqInReady,
  input chi_pkg::chi_noc_flit_t reqInFlit,
  input logic rspInReady,
  input logic datInReady,
  input logic snpOutValid,
  input logic snpOutReady,
  input chi_pkg::chi_noc_flit_t snpOutFlit,
  input logic rspOutValid,
  input logic rspOutReady,
  input chi_pkg::chi_noc_flit_t rspOutFlit,
  input logic [DEPTH-1:0] active,
  input logic [DEPTH-1:0] activeSync,
  input logic [DEPTH-1:0] eOlderBusy,
  input logic snpFire,
  input logic snpPartTwo,
  input logic snpIsSync,
  input logic [chi_pkg::clog2Min1(DEPTH)-1:0] snpEntry,
  input logic [TGT_W-1:0] snpTarget,
  input logic [NUM_DVM_NODES-1:0] nonSyncOut,
  input logic [NUM_DVM_NODES-1:0] syncOut,
  input logic gptInvalidateAll,
  input logic gptInvalidateByPa,
  input logic retryHandshake
);
  REQ_INPUT_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    reqInValid && !reqInReady |=> reqInValid && $stable(reqInFlit));

  SNP_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    snpOutValid && !snpOutReady |=> snpOutValid && $stable(snpOutFlit));

  RSP_STABLE_UNDER_BACKPRESSURE: assert property (
    @(posedge clk) disable iff (!resetn)
    rspOutValid && !rspOutReady |=> rspOutValid && $stable(rspOutFlit));

  MN_INPUTS_ALWAYS_READY: assert property (
    @(posedge clk) disable iff (!resetn)
    rspInReady && datInReady);

  MN_SYNC_AFTER_OLDER_OPERATIONS: assert property (
    @(posedge clk) disable iff (!resetn)
    snpFire && !snpPartTwo && snpIsSync |-> !eOlderBusy[snpEntry]);

  MN_ONE_SNOOP_OF_EACH_KIND_PER_TARGET: assert property (
    @(posedge clk) disable iff (!resetn)
    snpFire && !snpPartTwo
      |-> (snpIsSync ? !syncOut[snpTarget] : !nonSyncOut[snpTarget]));

  MN_NONSYNC_ENTRY_KEPT: assert property (
    @(posedge clk) disable iff (!resetn)
    !((active == '1) && (activeSync == active)));

  MN_CONCURRENT_DVM: cover property (
    @(posedge clk) disable iff (!resetn)
    !$onehot0(active));

  MN_SYNC_WAITS: cover property (
    @(posedge clk) disable iff (!resetn)
    (activeSync & eOlderBusy) != '0);

  MN_GPT_INVALIDATE: cover property (
    @(posedge clk) disable iff (!resetn)
    gptInvalidateAll || gptInvalidateByPa);

  MN_RETRY_ACK_SENT: cover property (
    @(posedge clk) disable iff (!resetn)
    retryHandshake);
endmodule

bind chi_mn_dvm chi_mn_sva #(
  .DEPTH(DEPTH),
  .NUM_DVM_NODES(NUM_DVM_NODES),
  .TGT_W(TGT_W)
) chi_mn_protocol_assertions (
  .clk(clk),
  .resetn(resetn),
  .reqInValid(reqInValid),
  .reqInReady(reqInReady),
  .reqInFlit(reqInFlit),
  .rspInReady(rspInReady),
  .datInReady(datInReady),
  .snpOutValid(snpOutValid),
  .snpOutReady(snpOutReady),
  .snpOutFlit(snpOutFlit),
  .rspOutValid(rspOutValid),
  .rspOutReady(rspOutReady),
  .rspOutFlit(rspOutFlit),
  .active(active),
  .activeSync(activeSync),
  .eOlderBusy(eOlderBusy),
  .snpFire(snpFire),
  .snpPartTwo(snpPartTwo),
  .snpIsSync(snpIsSync),
  .snpEntry(snpEntry),
  .snpTarget(snpTarget),
  .nonSyncOut(nonSyncOut),
  .syncOut(syncOut),
  .gptInvalidateAll(gptInvalidateAll),
  .gptInvalidateByPa(gptInvalidateByPa),
  .retryHandshake(retryHandshake)
);
