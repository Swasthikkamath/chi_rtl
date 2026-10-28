// System coherency, RAS, PMU and QoS assertions (IHI 0050H B15; the RAS,
// PMU and QoS rules are this design's, Section 9.16).
//
// chi_sysco_sva (chi_sysco):
//   SYSCO_REQ_FOUR_PHASE  assumption checked of the node: SYSCOREQ changes
//       only while SYSCOACK has the same value (B15.2).
//   SYSCO_ACK_FOUR_PHASE  SYSCOACK changes only while SYSCOREQ has the
//       opposite value (B15.2).
//   SYSCO_CONNECT_AT_ONCE  SYSCOACK rises the cycle after SYSCOREQ is seen
//       HIGH, without waiting for snoops (B15.2.2).
//   SYSCO_DISCONNECT_DRAINED  SYSCOACK falls only once every Home and MN
//       reports the node drained (B15.2.2).
// chi_hnf_sysco_sva (chi_hnf_top):
//   NO_SNOOP_OUTSIDE_COHERENCY  no snoop is issued to an RN-F whose
//       SYSCOREQ is LOW (B15.2.2).
//   RNF_IDLE_MEANS_DRAINED  an RN-F reported idle has no snoop outstanding
//       and no directory bit left.
//   CACHEABLE_REQUEST_INSIDE_COHERENCY  checked of the RN-F: a request that
//       lets it cache a coherent line comes only while its SYSCOREQ is HIGH
//       (B15.2.1).
// chi_mn_sysco_sva (chi_mn_dvm):
//   NO_DVM_SNOOP_OUTSIDE_COHERENCY  no SnpDVMOp part 1 goes to a node
//       outside the DVM domain.
// chi_sf_system_sva (chi_snoop_filter):
//   SF_HIDES_NODES_OUTSIDE_COHERENCY  a lookup and an eviction name no RN-F
//       that has left system coherency.
// chi_qos_sva (chi_qos_reg):
//   QOS_INJECTION_TAKES_A_TOKEN  a regulated port injects only with a token.
//   QOS_TOKENS_BOUNDED  a bucket holds no more than its burst, once the burst
//       has been stable for a cycle.
// chi_hnf_eo_sva (chi_hnf_top):
//   EO_STARTS_ON_ITS_TICKET  an Endpoint-ordered request starts only when its
//       ticket is the one served for its Requester and SN-F (Section 9.5).
// chi_hnf_gpt_slc_sva (chi_hnf_top):
//   GPT_FILL_ONLY_WHILE_LINE_FREE  a GPT line goes into the SLC only while no
//       transaction or eviction holds the line, in any PAS.
// chi_cfg_slave_sva (chi_cfg_slave):
//   REGION_COMMIT_LEGAL  a committed region is legal (chi_pkg::samRegionLegal).
// chi_quiescence_sva (chi_interconnect_top):
//   REGION_UPDATE_WHEN_QUIESCENT  an APB region commit lands only when the
//       fabric was empty and every Home and MN idle.
// chi_obs_sva (chi_obs_regs):
//   RAS_UNCORRECTED_RAISES_IRQ  an uncorrected error leaves its record's
//       interrupt HIGH.
//   RAS_IRQ_HOLDS_UNTIL_CLEARED  the interrupt stays HIGH until software
//       clears the record.
//
// Covers: a connect and a disconnect, a disconnect waiting to drain, a
// snoop dropped at disconnect, a directory and SLC tag error corrected and
// uncorrectable, a directory lookup of a set with a dead way, a regulated
// port held back, an interrupt raised and cleared, an Endpoint-ordered
// request waiting on another Home, a GPT read hitting in the SLC and a GPT
// line filled, a region commit refused.
module chi_sysco_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_COH = 1
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_COH-1:0] coReq,
  input logic [NUM_COH-1:0] coAck,
  input logic [NUM_COH-1:0] drained
);
  for (genvar n = 0; n < NUM_COH; n++) begin : per_node
    if (CFG.syscoEn) begin : handshake
      SYSCO_REQ_FOUR_PHASE: assert property (
        @(posedge clk) disable iff (!resetn)
        (coReq[n] != $past(coReq[n])) |-> ($past(coReq[n]) == $past(coAck[n])));

      SYSCO_ACK_FOUR_PHASE: assert property (
        @(posedge clk) disable iff (!resetn)
        (coAck[n] != $past(coAck[n])) |-> ($past(coReq[n]) != $past(coAck[n])));

      SYSCO_CONNECT_AT_ONCE: assert property (
        @(posedge clk) disable iff (!resetn)
        coReq[n] && !coAck[n] |=> coAck[n]);

      SYSCO_DISCONNECT_DRAINED: assert property (
        @(posedge clk) disable iff (!resetn)
        $fell(coAck[n]) |-> $past(drained[n]));

      SYSCO_CONNECT_DISCONNECT: cover property (
        @(posedge clk) disable iff (!resetn)
        $rose(coAck[n]) ##[1:$] $fell(coAck[n]));

      SYSCO_DISCONNECT_WAITS: cover property (
        @(posedge clk) disable iff (!resetn)
        !coReq[n] && coAck[n] && !drained[n]);
    end
  end
endmodule

module chi_hnf_sysco_sva #(
  parameter int unsigned NUM_RNF = 1,
  parameter int unsigned NUM_OWNERS = 1,
  parameter int unsigned RNF_W = 1,
  parameter int unsigned POS_DEPTH = 1
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_RNF-1:0] rnfSnoopable,
  input logic [NUM_RNF-1:0] rnfIdle,
  input logic [NUM_RNF-1:0] sfRnfCleared,
  input logic [NUM_OWNERS-1:0][NUM_RNF-1:0] ownerPending,
  input logic snpIssueFire,
  input logic [RNF_W-1:0] snpIssueTarget,
  input logic allocValid,
  input chi_pkg::chi_req_opcode_e allocOpcode,
  input logic allocIsRnf,
  input logic [RNF_W-1:0] allocRnf
);
  import chi_pkg::*;

  CACHEABLE_REQUEST_INSIDE_COHERENCY: assert property (
    @(posedge clk) disable iff (!resetn)
    allocValid && allocIsRnf
    && (allocOpcode inside {REQ_READ_CLEAN, REQ_READ_NOT_SHARED_DIRTY,
                            REQ_READ_SHARED, REQ_READ_UNIQUE,
                            REQ_READ_PREFER_UNIQUE, REQ_MAKE_READ_UNIQUE,
                            REQ_CLEAN_UNIQUE, REQ_MAKE_UNIQUE})
      |-> rnfSnoopable[allocRnf]);

  NO_SNOOP_OUTSIDE_COHERENCY: assert property (
    @(posedge clk) disable iff (!resetn)
    snpIssueFire |-> rnfSnoopable[snpIssueTarget]);

  for (genvar r = 0; r < NUM_RNF; r++) begin : per_rnf
    logic pending;
    always_comb begin
      pending = 1'b0;
      for (int unsigned o = 0; o < NUM_OWNERS; o++)
        pending = pending || ownerPending[o][r];
    end

    RNF_IDLE_MEANS_DRAINED: assert property (
      @(posedge clk) disable iff (!resetn)
      rnfIdle[r] |-> !pending && sfRnfCleared[r]);

    SNOOP_DROPPED_AT_DISCONNECT: cover property (
      @(posedge clk) disable iff (!resetn)
      $fell(rnfSnoopable[r]) && pending);
  end
endmodule

module chi_mn_sysco_sva #(
  parameter int unsigned NUM_DVM_NODES = 1,
  parameter int unsigned TGT_W = 1
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_DVM_NODES-1:0] nodeSnoopable,
  input logic snpFire,
  input logic snpPartTwo,
  input logic [TGT_W-1:0] snpTarget
);
  NO_DVM_SNOOP_OUTSIDE_COHERENCY: assert property (
    @(posedge clk) disable iff (!resetn)
    snpFire && !snpPartTwo |-> nodeSnoopable[snpTarget]);
endmodule

module chi_sf_system_sva #(
  parameter int unsigned NUM_RNF = 1
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_RNF-1:0] liveMask,
  input logic lookupHit,
  input logic lookupError,
  input logic [NUM_RNF-1:0] lookupSharers,
  input logic victimValid,
  input logic [NUM_RNF-1:0] victimSharers,
  input logic eccCorrected,
  input logic eccUncorrected
);
  SF_HIDES_NODES_OUTSIDE_COHERENCY: assert property (
    @(posedge clk) disable iff (!resetn)
    ((lookupSharers & ~liveMask) == '0)
    and (victimValid |-> ((victimSharers & ~liveMask) == '0)));

  SF_ECC_CORRECTED: cover property (
    @(posedge clk) disable iff (!resetn)
    eccCorrected);

  SF_ECC_UNCORRECTED: cover property (
    @(posedge clk) disable iff (!resetn)
    eccUncorrected);

  SF_LOOKUP_OF_DEAD_SET: cover property (
    @(posedge clk) disable iff (!resetn)
    lookupHit && lookupError);
endmodule

module chi_slc_ras_sva (
  input logic clk,
  input logic resetn,
  input logic tagCorrected,
  input logic tagUncorrected
);
  SLC_TAG_CORRECTED: cover property (
    @(posedge clk) disable iff (!resetn)
    tagCorrected);

  SLC_TAG_UNCORRECTED: cover property (
    @(posedge clk) disable iff (!resetn)
    tagUncorrected);
endmodule

module chi_qos_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT,
  parameter int unsigned NUM_PORTS = 1
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_PORTS-1:0] inValid,
  input logic [NUM_PORTS-1:0] outValid,
  input logic [NUM_PORTS-1:0][7:0] tokens,
  input logic [NUM_PORTS-1:0][7:0] burst
);
  for (genvar p = 0; p < NUM_PORTS; p++) begin : per_port
    if (CFG.qosRegEn) begin : regulated
      QOS_INJECTION_TAKES_A_TOKEN: assert property (
        @(posedge clk) disable iff (!resetn)
        outValid[p] |-> (tokens[p] != 8'd0));

      // A lowered burst cuts the bucket the next cycle.
      QOS_TOKENS_BOUNDED: assert property (
        @(posedge clk) disable iff (!resetn)
        $stable(burst[p]) |-> (tokens[p] <= burst[p]));

      QOS_PORT_HELD: cover property (
        @(posedge clk) disable iff (!resetn)
        inValid[p] && !outValid[p]);
    end
  end
endmodule

module chi_obs_sva #(
  parameter int unsigned NUM_REC = 1,
  parameter int unsigned SELECT_W = 1
) (
  input logic clk,
  input logic resetn,
  input logic [NUM_REC-1:0] rasUncorrected,
  input logic [NUM_REC-1:0] rasIrq,
  input logic rasClear,
  input logic [SELECT_W-1:0] selected
);
  for (genvar r = 0; r < NUM_REC; r++) begin : per_record
    RAS_UNCORRECTED_RAISES_IRQ: assert property (
      @(posedge clk) disable iff (!resetn)
      rasUncorrected[r] |=> rasIrq[r]);

    RAS_IRQ_HOLDS_UNTIL_CLEARED: assert property (
      @(posedge clk) disable iff (!resetn)
      rasIrq[r] && !(rasClear && (int'(selected) == r)) |=> rasIrq[r]);

    RAS_IRQ_RAISED_AND_CLEARED: cover property (
      @(posedge clk) disable iff (!resetn)
      $rose(rasIrq[r]) ##[1:$] $fell(rasIrq[r]));
  end
endmodule

module chi_hnf_eo_sva #(
  parameter int unsigned POS_DEPTH = 1,
  parameter int unsigned POS_W = 1,
  parameter int unsigned NUM_REQUESTERS = 1,
  parameter int unsigned EO_REQ_W = 1,
  parameter int unsigned EO_TICKET_W = 1
) (
  input logic clk,
  input logic resetn,
  input logic startValid,
  input logic startTracked,
  input logic [EO_REQ_W-1:0] startReq,
  input logic [EO_TICKET_W-1:0] startTicket,
  input logic [NUM_REQUESTERS-1:0][EO_TICKET_W-1:0] eoServing,
  input logic [POS_DEPTH-1:0] eoBlocked,
  input logic [POS_DEPTH-1:0] posActive
);
  EO_STARTS_ON_ITS_TICKET: assert property (
    @(posedge clk) disable iff (!resetn)
    startValid && startTracked |-> (startTicket == eoServing[startReq]));

  EO_WAITS_ON_ANOTHER_REQUEST: cover property (
    @(posedge clk) disable iff (!resetn)
    (eoBlocked & posActive) != '0);
endmodule

module chi_hnf_gpt_slc_sva (
  input logic clk,
  input logic resetn,
  input logic slcUpdateValid,
  input logic slcUpdateReady,
  input logic slcUpdateForGpt,
  input logic gptLineHeld,
  input logic gptSlcRead,
  input logic slcReadHit,
  input logic gptErr
);
  GPT_FILL_ONLY_WHILE_LINE_FREE: assert property (
    @(posedge clk) disable iff (!resetn)
    slcUpdateValid && slcUpdateForGpt |-> !gptLineHeld);

  // A line read with an error or poison never goes into the SLC.
  GPT_FILL_ONLY_GOOD_DATA: assert property (
    @(posedge clk) disable iff (!resetn)
    slcUpdateValid && slcUpdateForGpt |-> !gptErr);

  GPT_READ_SLC_HIT: cover property (
    @(posedge clk) disable iff (!resetn)
    gptSlcRead && slcReadHit);

  GPT_LINE_FILLED: cover property (
    @(posedge clk) disable iff (!resetn)
    slcUpdateValid && slcUpdateReady && slcUpdateForGpt);
endmodule

module chi_cfg_slave_sva #(
  parameter chi_cfg_pkg::chi_cfg_t CFG = chi_cfg_pkg::CHI_CFG_DEFAULT
) (
  input logic clk,
  input logic resetn,
  input logic regionUpdate,
  input logic [CFG.addrW-1:0] regionUpdateBase,
  input logic [CFG.addrW-1:0] regionUpdateLimit,
  input logic [chi_cfg_pkg::CHI_SAM_ATTR_W-1:0] regionUpdateAttributes,
  input logic commitRefused
);
  REGION_COMMIT_LEGAL: assert property (
    @(posedge clk) disable iff (!resetn)
    regionUpdate |-> chi_pkg::samRegionLegal(
                       CFG, chi_pkg::CHI_MAX_ADDR_W'(regionUpdateBase),
                       chi_pkg::CHI_MAX_ADDR_W'(regionUpdateLimit),
                       regionUpdateAttributes));

  REGION_COMMIT_REFUSED: cover property (
    @(posedge clk) disable iff (!resetn)
    commitRefused);
endmodule

module chi_quiescence_sva (
  input logic clk,
  input logic resetn,
  input logic apbRegionUpdate,
  input logic trafficQuiescent
);
  REGION_UPDATE_WHEN_QUIESCENT: assert property (
    @(posedge clk) disable iff (!resetn)
    apbRegionUpdate |-> $past(trafficQuiescent));
endmodule

bind chi_hnf_top chi_hnf_eo_sva #(
  .POS_DEPTH(POS_DEPTH), .POS_W(POS_W), .NUM_REQUESTERS(NUM_REQUESTERS),
  .EO_REQ_W(EO_REQ_W), .EO_TICKET_W(EO_TICKET_W)
) chi_hnf_eo_assertions (
  .clk(clk), .resetn(resetn), .startValid(startValid),
  .startTracked(entry[startIndex].eoTracked), .startReq(entry[startIndex].eoReq),
  .startTicket(entry[startIndex].eoTicket), .eoServing(eoServing),
  .eoBlocked(eoBlocked), .posActive(posActive)
);

bind chi_hnf_top chi_hnf_gpt_slc_sva chi_hnf_gpt_slc_assertions (
  .clk(clk), .resetn(resetn), .slcUpdateValid(slcUpdateValid),
  .slcUpdateReady(slcUpdateReady), .slcUpdateForGpt(slcUpdateForGpt),
  .gptLineHeld(gptLineHeld), .gptSlcRead(gptSlcRead), .slcReadHit(slcReadHit),
  .gptErr(gptErr)
);

bind chi_cfg_slave chi_cfg_slave_sva #(
  .CFG(CFG)
) chi_cfg_slave_assertions (
  .clk(PCLK), .resetn(PRESETn), .regionUpdate(regionUpdate),
  .regionUpdateBase(regionUpdateBase), .regionUpdateLimit(regionUpdateLimit),
  .regionUpdateAttributes(regionUpdateAttributes),
  .commitRefused(transfer && PWRITE && (PADDR == ADDR_COMMIT) && PSTRB[0]
                 && !commitLegal)
);

bind chi_interconnect_top chi_quiescence_sva chi_quiescence_assertions (
  .clk(clk), .resetn(resetn), .apbRegionUpdate(apbRegionUpdate),
  .trafficQuiescent(trafficQuiescent)
);

bind chi_sysco chi_sysco_sva #(
  .CFG(CFG), .NUM_COH(NUM_COH)
) chi_sysco_assertions (
  .clk(clk), .resetn(resetn), .coReq(coReq), .coAck(coAck),
  .drained(drained)
);

bind chi_hnf_top chi_hnf_sysco_sva #(
  .NUM_RNF(NUM_RNF), .NUM_OWNERS(NUM_OWNERS), .RNF_W(RNF_W),
  .POS_DEPTH(POS_DEPTH)
) chi_hnf_sysco_assertions (
  .clk(clk), .resetn(resetn), .rnfSnoopable(rnfSnoopable), .rnfIdle(rnfIdle),
  .sfRnfCleared(sfRnfCleared), .ownerPending(ownerPending),
  .snpIssueFire(snpIssueFire),
  .snpIssueTarget(snpIssueTarget),
  .allocValid(posAllocValid && posAllocReady),
  .allocOpcode(allocEntry.req.opcode),
  .allocIsRnf(allocEntry.reqIsRnf),
  .allocRnf(allocEntry.reqRnf)
);

bind chi_mn_dvm chi_mn_sysco_sva #(
  .NUM_DVM_NODES(NUM_DVM_NODES), .TGT_W(TGT_W)
) chi_mn_sysco_assertions (
  .clk(clk), .resetn(resetn), .nodeSnoopable(nodeSnoopable),
  .snpFire(snpFire), .snpPartTwo(snpPartTwo), .snpTarget(snpTarget)
);

bind chi_snoop_filter chi_sf_system_sva #(
  .NUM_RNF(NUM_RNF)
) chi_sf_system_assertions (
  .clk(clk), .resetn(resetn), .liveMask(liveMask), .lookupHit(lookupHit),
  .lookupError(lookupError), .lookupSharers(lookupSharers),
  .victimValid(victimValid), .victimSharers(victimSharers),
  .eccCorrected(eccCorrected), .eccUncorrected(eccUncorrected)
);

bind chi_slc chi_slc_ras_sva chi_slc_ras_assertions (
  .clk(clk), .resetn(resetn), .tagCorrected(tagCorrected),
  .tagUncorrected(tagUncorrected)
);

bind chi_qos_reg chi_qos_sva #(
  .CFG(CFG), .NUM_PORTS(NUM_PORTS)
) chi_qos_assertions (
  .clk(clk), .resetn(resetn), .inValid(inValid), .outValid(outValid),
  .tokens(tokens), .burst(burst)
);

bind chi_obs_regs chi_obs_sva #(
  .NUM_REC(NUM_REC), .SELECT_W(SELECT_W)
) chi_obs_assertions (
  .clk(PCLK), .resetn(PRESETn), .rasUncorrected(rasUncorrected),
  .rasIrq(rasIrq), .rasClear(rasClear), .selected(selected)
);
