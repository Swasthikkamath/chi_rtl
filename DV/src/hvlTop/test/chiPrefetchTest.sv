// PrefetchTgt is the only request with no response of any kind, and the
// only one a Requester sends straight to a Subordinate rather than to a
// Home. Two things are checked, and the first is about the testbench as
// much as the DUT: the Requester must deallocate as soon as the hint is
// sent, so the read that follows it has to complete. The second is that
// the hint actually crossed the interconnect, which nothing but a count at
// the far end can say, because silence is the correct response.
//
// The hint carries TxnID 0 and it may do so while another transaction from
// the same Requester is using TxnID 0, so this also exercises the one case
// where TxnID is not a unique key.
// [SPEC:IHI0050H B4.2.6.2 Prefetch transaction] [SPEC:IHI0050H B2.4.2]
// [SPEC:IHI0050H B3.3.1 TgtID determination]

class chiPrefetchTest extends chiBaseTest;
  `uvm_component_utils(chiPrefetchTest)

  function new(string name = "chiPrefetchTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (chiSkip(NUM_SNF < 1, "NUM_SNF < 1"))
      return;
    chiStart(CHI_VSEQ_PREFETCH);
  endtask

  function void check_phase(uvm_phase phase);
    int unsigned arrived;
    super.check_phase(phase);
    if (NUM_SNF < 1)
      return;
    if (env.scoreboard.lifecycleModel.rnPrefetchCount == 0) begin
      `uvm_error("chiPrefetchTest", "no PrefetchTgt was ever issued")
      return;
    end
    arrived = 0;
    foreach (env.agents.snfAgent[i])
      if (env.agents.snfAgent[i].driver != null)
        arrived += env.agents.snfAgent[i].driver.prefetchTgtSeen;
    // A Subordinate is permitted to discard the hint, but the interconnect
    // is not permitted to lose it: the Requester addressed an SN-F by
    // NodeID and the request is a routed REQ flit like any other.
    if (arrived == 0)
      `uvm_error("chiPrefetchTest",
        $sformatf({"%0d PrefetchTgt requests were issued to an SN-F NodeID and none ",
                   "arrived at any SN-F"}, env.scoreboard.lifecycleModel.rnPrefetchCount))
    else
      `uvm_info("chiPrefetchTest",
        $sformatf("%0d PrefetchTgt issued, %0d arrived at an SN-F",
                  env.scoreboard.lifecycleModel.rnPrefetchCount, arrived), UVM_LOW)
  endfunction
endclass
