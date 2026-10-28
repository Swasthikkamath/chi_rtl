// Transaction completion for a Home Node (HN-F or HN-I).
//
// Bounded completion. One cover per entry: the entry is allocated and is free
// again within BOUND cycles, a witness that every entry can complete.
//
// Liveness (`define CHI_SVA_LIVENESS, for a formal tool). Assumed: every
// output stage is ready infinitely often, and everything an entry waits for
// from outside the Home eventually arrives — a snoop response, the
// Subordinate's answer or P-Credit, the Requester's data or CompAck. The
// assumptions are written on the entry's own wait states, so they state
// exactly what the argument in Section 9.7 of the design specification takes
// from the environment. Asserted: every allocated entry eventually frees.
// Strong properties cannot pass at the end of a finite simulation, so they are
// left out of simulation builds.
module chi_home_liveness_sva #(
  parameter int unsigned DEPTH = 1,
  parameter int unsigned BOUND = 256
) (
  input logic clk,
  input logic resetn,
  input logic [DEPTH-1:0] active,
  input logic [DEPTH-1:0] waitSnoop,
  input logic [DEPTH-1:0] waitDownstream,
  input logic [DEPTH-1:0] waitRequester,
  input logic reqOutReady,
  input logic rspOutReady,
  input logic snpOutReady,
  input logic datOutReady
);
  for (genvar i = 0; i < DEPTH; i++) begin : per_entry
    ENTRY_COMPLETES_WITHIN_BOUND: cover property (
      @(posedge clk) disable iff (!resetn)
      $rose(active[i]) ##[1:BOUND] !active[i]);

`ifdef CHI_SVA_LIVENESS
    SNOOP_RESPONSE_ARRIVES: assume property (
      @(posedge clk) disable iff (!resetn)
      waitSnoop[i] |-> s_eventually !waitSnoop[i]);

    SUBORDINATE_ANSWERS: assume property (
      @(posedge clk) disable iff (!resetn)
      waitDownstream[i] |-> s_eventually !waitDownstream[i]);

    REQUESTER_ANSWERS: assume property (
      @(posedge clk) disable iff (!resetn)
      waitRequester[i] |-> s_eventually !waitRequester[i]);

    ENTRY_EVENTUALLY_FREES: assert property (
      @(posedge clk) disable iff (!resetn)
      active[i] |-> s_eventually !active[i]);
`endif
  end

`ifdef CHI_SVA_LIVENESS
  REQ_OUTPUT_FAIR: assume property (
    @(posedge clk) disable iff (!resetn) s_eventually reqOutReady);
  RSP_OUTPUT_FAIR: assume property (
    @(posedge clk) disable iff (!resetn) s_eventually rspOutReady);
  SNP_OUTPUT_FAIR: assume property (
    @(posedge clk) disable iff (!resetn) s_eventually snpOutReady);
  DAT_OUTPUT_FAIR: assume property (
    @(posedge clk) disable iff (!resetn) s_eventually datOutReady);
`endif
endmodule

bind chi_hnf_top chi_home_liveness_sva #(
  .DEPTH(POS_DEPTH)
) chi_hnf_liveness_assertions (
  .clk(clk),
  .resetn(resetn),
  .active(posActive),
  .waitSnoop(liveWaitSnoop),
  .waitDownstream(liveWaitDownstream),
  .waitRequester(liveWaitRequester),
  .reqOutReady(reqOutReady),
  .rspOutReady(rspOutReady),
  .snpOutReady(snpOutReady),
  .datOutReady(datOutReady)
);

bind chi_hni_top chi_home_liveness_sva #(
  .DEPTH(DEPTH)
) chi_hni_liveness_assertions (
  .clk(clk),
  .resetn(resetn),
  .active(posActive),
  .waitSnoop('0),
  .waitDownstream(liveWaitDownstream),
  .waitRequester(liveWaitRequester),
  .reqOutReady(reqOutReady),
  .rspOutReady(rspOutReady),
  .snpOutReady(1'b1),
  .datOutReady(datOutReady)
);
