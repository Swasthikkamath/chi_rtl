// Granule Protection Check assertions.
//
// chi_hnf_gpc_sva, bound to chi_hnf_top:
//   GPC_FAILED_SENDS_NOTHING_DOWNSTREAM  an entry that failed the check never
//       starts a downstream operation.
//   GPC_FAILED_SNOOPS_NOTHING  it never sends a snoop.
//   GPC_FAILED_TOUCHES_NO_SLC  it never reads or updates the SLC.
//   GPC_START_AFTER_CHECK  no entry starts before its check is answered.
//
// chi_hni_gpc_sva, bound to chi_hni_top:
//   HNI_ERROR_SENDS_NOTHING_DOWNSTREAM  an entry in error, a failed check
//       among them, never starts a downstream operation.
//   HNI_GPC_START_AFTER_CHECK  no entry starts before its check is answered.
//
// Covers: a failed check at each Home, an entry waiting for a walk.
module chi_hnf_gpc_sva #(
  parameter int unsigned POS_DEPTH = 1,
  parameter int unsigned POS_W = 1,
  parameter int unsigned OWNER_W = 1
) (
  input logic clk,
  input logic resetn,
  input logic [POS_DEPTH-1:0] eGpcFailed,
  input logic [POS_DEPTH-1:0] eGpcPending,
  input logic [POS_DEPTH-1:0] posStartMask,
  input logic [POS_DEPTH-1:0] dnStartValid,
  input logic snpIssueFire,
  input logic [OWNER_W-1:0] snpIssueOwner,
  input logic slcReadValid,
  input logic [POS_W-1:0] slcReadEntry,
  input logic slcUpdateValid,
  input logic slcUpdateFromRetire,
  input logic [POS_W-1:0] slcUpdateEntry
);
  GPC_FAILED_SENDS_NOTHING_DOWNSTREAM: assert property (
    @(posedge clk) disable iff (!resetn)
    (dnStartValid & eGpcFailed) == '0);

  GPC_FAILED_SNOOPS_NOTHING: assert property (
    @(posedge clk) disable iff (!resetn)
    snpIssueFire && (int'(snpIssueOwner) < POS_DEPTH)
      |-> !eGpcFailed[POS_W'(snpIssueOwner)]);

  GPC_FAILED_TOUCHES_NO_SLC: assert property (
    @(posedge clk) disable iff (!resetn)
    (slcReadValid |-> !eGpcFailed[slcReadEntry])
    and (slcUpdateValid && slcUpdateFromRetire |-> !eGpcFailed[slcUpdateEntry]));

  GPC_START_AFTER_CHECK: assert property (
    @(posedge clk) disable iff (!resetn)
    (posStartMask & eGpcPending) == '0);

  GPC_FAULT_AT_HNF: cover property (
    @(posedge clk) disable iff (!resetn)
    eGpcFailed != '0);

  GPC_WAITING_FOR_WALK: cover property (
    @(posedge clk) disable iff (!resetn)
    eGpcPending != '0);
endmodule

module chi_hni_gpc_sva #(
  parameter int unsigned DEPTH = 1
) (
  input logic clk,
  input logic resetn,
  input logic [DEPTH-1:0] eErr,
  input logic [DEPTH-1:0] eGpcPending,
  input logic [DEPTH-1:0] posStartMask,
  input logic [DEPTH-1:0] dnStartValid
);
  HNI_ERROR_SENDS_NOTHING_DOWNSTREAM: assert property (
    @(posedge clk) disable iff (!resetn)
    (dnStartValid & eErr) == '0);

  HNI_GPC_START_AFTER_CHECK: assert property (
    @(posedge clk) disable iff (!resetn)
    (posStartMask & eGpcPending) == '0);

  HNI_GPC_WAITING_FOR_WALK: cover property (
    @(posedge clk) disable iff (!resetn)
    eGpcPending != '0);
endmodule

bind chi_hnf_top chi_hnf_gpc_sva #(
  .POS_DEPTH(POS_DEPTH),
  .POS_W(POS_W),
  .OWNER_W(OWNER_W)
) chi_hnf_gpc_assertions (
  .clk(clk),
  .resetn(resetn),
  .eGpcFailed(eGpcFailed),
  .eGpcPending(eGpcPending),
  .posStartMask(posStartMask),
  .dnStartValid(dnStartValid[POS_DEPTH-1:0]),
  .snpIssueFire(snpIssueFire),
  .snpIssueOwner(snpIssueOwner),
  .slcReadValid(slcReadValid),
  .slcReadEntry(slcReadEntry),
  .slcUpdateValid(slcUpdateValid),
  .slcUpdateFromRetire(slcUpdateFromRetire),
  .slcUpdateEntry(slcUpdateEntry)
);

bind chi_hni_top chi_hni_gpc_sva #(
  .DEPTH(DEPTH)
) chi_hni_gpc_assertions (
  .clk(clk),
  .resetn(resetn),
  .eErr(eErr),
  .eGpcPending(eGpcPending),
  .posStartMask(posStartMask),
  .dnStartValid(dnStartValid)
);
