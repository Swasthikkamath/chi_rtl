// HN-F snoop assertions.
//
//   SNOOP_OUTSTANDING_BOUNDED  never more than maxOutstandingSnoops snoops in
//       flight across the Home.
//   SNOOP_COUNT_MATCHES_PENDING  the in-flight count equals the snoops the
//       owners are still waiting for, so the bound is exact.
//   ONE_SNOOP_PER_SNOOPEE_PER_LOCATION  a snoop goes to an RN-F only when no
//       snoop to the same location is outstanding at it (IHI 0050H B4.11.2).
//   SNOOP_RESPONSE_EXPECTED, SNOOP_DATA_EXPECTED  every snoop response names
//       an owner waiting for that Snoopee; an RN-F answers only what it was
//       asked, and only once (IHI 0050H B4.5.3).
//
// Covers: one transaction with several snoops in flight, several
// transactions snooping at once, the bound reached with snoops waiting, two
// Snoopees returning data to one transaction, Dirty and partial snoop data,
// and a forwarded snoop response (reachable once direct cache transfer is in
// use).
module chi_snoop_sva #(
  parameter int unsigned NUM_OWNERS = 1,
  parameter int unsigned NUM_RNF = 1,
  parameter int unsigned KEY_W = 1,
  parameter int unsigned OWNER_W = 1,
  parameter int unsigned RNF_W = 1,
  parameter int unsigned COUNT_W = 1,
  parameter int unsigned MAX_OUTSTANDING = 1
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_OWNERS-1:0][NUM_RNF-1:0] ownerToSend,
  input logic [NUM_OWNERS-1:0][NUM_RNF-1:0] ownerPending,
  input logic [NUM_OWNERS-1:0][KEY_W-1:0] ownerKey,
  input logic [NUM_OWNERS-1:0] ownerLive,
  input logic [NUM_OWNERS-1:0][NUM_RNF-1:0] ownerDataFrom,
  input logic snpIssueFire,
  input logic [OWNER_W-1:0] snpIssueOwner,
  input logic [RNF_W-1:0] snpIssueTarget,
  input logic [COUNT_W-1:0] snpOutstanding,
  input logic snpRspValid,
  input logic [OWNER_W-1:0] snpRspOwner,
  input logic [RNF_W-1:0] snpRspTarget,
  input logic snpDatValid,
  input logic [OWNER_W-1:0] snpDatOwner,
  input logic [RNF_W-1:0] snpDatTarget,
  input chi_pkg::chi_rsp_flit_t incomingRsp,
  input chi_pkg::chi_dat_flit_t incomingDat
);
  import chi_pkg::*;

  int unsigned pendingCount;
  int unsigned snoopingOwners;
  logic multiTargetOwner;
  logic multiDataOwner;
  logic issueConflict;

  always_comb begin
    pendingCount = 0;
    snoopingOwners = 0;
    multiTargetOwner = 1'b0;
    multiDataOwner = 1'b0;
    for (int unsigned owner = 0; owner < NUM_OWNERS; owner++) begin
      int unsigned targets;
      int unsigned sources;
      targets = 0;
      sources = 0;
      for (int unsigned rnf = 0; rnf < NUM_RNF; rnf++) begin
        if (ownerPending[owner][rnf])
          targets++;
        if (ownerDataFrom[owner][rnf])
          sources++;
      end
      pendingCount += targets;
      if (targets != 0)
        snoopingOwners++;
      if (targets >= 2)
        multiTargetOwner = 1'b1;
      if (sources >= 2)
        multiDataOwner = 1'b1;
    end

    // The issuing owner counts too: it must not snoop one RN-F twice.
    issueConflict = 1'b0;
    for (int unsigned owner = 0; owner < NUM_OWNERS; owner++)
      if (ownerLive[owner] && ownerPending[owner][snpIssueTarget]
          && (ownerKey[owner] == ownerKey[snpIssueOwner]))
        issueConflict = 1'b1;
  end

  SNOOP_OUTSTANDING_BOUNDED: assert property (
    @(posedge clk) disable iff (!resetn)
    int'(snpOutstanding) <= MAX_OUTSTANDING);

  SNOOP_COUNT_MATCHES_PENDING: assert property (
    @(posedge clk) disable iff (!resetn)
    int'(snpOutstanding) == pendingCount);

  ONE_SNOOP_PER_SNOOPEE_PER_LOCATION: assert property (
    @(posedge clk) disable iff (!resetn)
    snpIssueFire |-> !issueConflict);

  SNOOP_RESPONSE_EXPECTED: assert property (
    @(posedge clk) disable iff (!resetn)
    snpRspValid |-> ownerPending[snpRspOwner][snpRspTarget]);

  SNOOP_DATA_EXPECTED: assert property (
    @(posedge clk) disable iff (!resetn)
    snpDatValid |-> ownerPending[snpDatOwner][snpDatTarget]);

  PARALLEL_SNOOPS_ONE_TRANSACTION: cover property (
    @(posedge clk) disable iff (!resetn)
    multiTargetOwner);

  SEVERAL_TRANSACTIONS_SNOOPING: cover property (
    @(posedge clk) disable iff (!resetn)
    snoopingOwners >= 2);

  SNOOP_LIMIT_REACHED: cover property (
    @(posedge clk) disable iff (!resetn)
    (int'(snpOutstanding) == MAX_OUTSTANDING) && (ownerToSend != '0));

  DATA_FROM_TWO_SNOOPEES: cover property (
    @(posedge clk) disable iff (!resetn)
    multiDataOwner);

  DIRTY_SNOOP_DATA: cover property (
    @(posedge clk) disable iff (!resetn)
    snpDatValid && respPassDirty(incomingDat.resp));

  PARTIAL_SNOOP_DATA: cover property (
    @(posedge clk) disable iff (!resetn)
    snpDatValid && (incomingDat.opcode == DAT_SNP_RESP_DATA_PTL));

  FORWARDED_SNOOP_RESPONSE: cover property (
    @(posedge clk) disable iff (!resetn)
    (snpRspValid && (incomingRsp.opcode == RSP_SNP_RESP_FWDED))
    || (snpDatValid && (incomingDat.opcode == DAT_SNP_RESP_DATA_FWDED)));
endmodule

bind chi_hnf_top chi_snoop_sva #(
  .NUM_OWNERS(NUM_OWNERS),
  .NUM_RNF(NUM_RNF),
  .KEY_W(KEY_W),
  .OWNER_W(OWNER_W),
  .RNF_W(RNF_W),
  .COUNT_W(SNP_COUNT_W),
  .MAX_OUTSTANDING(CFG.maxOutstandingSnoops)
) chi_hnf_snoop_assertions (
  .clk(clk),
  .resetn(resetn),
  .ownerToSend(ownerToSend),
  .ownerPending(ownerPending),
  .ownerKey(ownerKey),
  .ownerLive(ownerLive),
  .ownerDataFrom(ownerDataFrom),
  .snpIssueFire(snpIssueFire),
  .snpIssueOwner(snpIssueOwner),
  .snpIssueTarget(snpIssueTarget),
  .snpOutstanding(snpOutstanding),
  .snpRspValid(snpRspValid),
  .snpRspOwner(snpRspOwner),
  .snpRspTarget(snpRspTarget),
  .snpDatValid(snpDatValid),
  .snpDatOwner(snpDatOwner),
  .snpDatTarget(snpDatTarget),
  .incomingRsp(incomingRsp),
  .incomingDat(incomingDat)
);
