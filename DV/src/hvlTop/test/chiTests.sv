// Test library.
//
// Each test is a choice of virtual sequence plus whatever configuration that
// sequence needs. They are deliberately ordered from least to most
// demanding: if the traffic tests fail, the bring-up test says whether the
// links were ever the problem.

// Links only. This is the first thing to run on a new configuration, because
// every other test depends on the links reaching RUN and it is the one test
// whose failure has an unambiguous cause.
class chiLinkBringUpTest extends chiBaseTest;
  `uvm_component_utils(chiLinkBringUpTest)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    // No traffic to drain.
    drainCycles = 200;
  endfunction

  function uvm_sequence_base testSequence();
    return chiLinkBringUpVirtualSeq::type_id::create("linkBringUpSeq");
  endfunction
endclass

// Mixed coherent read and write traffic from every Requester over a shared
// window. This is the Stage 1 workhorse: it exercises the read and write flows
// end to end and, because the window is shared, produces snoops as a
// side-effect rather than by contrivance.
class chiCoherentTrafficTest extends chiBaseTest;
  `uvm_component_utils(chiCoherentTrafficTest)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function uvm_sequence_base testSequence();
    chiCoherentTrafficVirtualSeq seq_;
    seq_ = chiCoherentTrafficVirtualSeq::type_id::create("coherentTrafficSeq");
    void'(seq_.randomize() with { accessesPerAgent == 16; });
    return seq_;
  endfunction
endclass

// Heavy contention on four lines. Where the traffic test produces snoops
// incidentally, this produces them deliberately and in volume, including the
// ones that have to move dirty data out of one cache and into another.
class chiSharedLineTest extends chiBaseTest;
  `uvm_component_utils(chiSharedLineTest)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function uvm_sequence_base testSequence();
    chiSharedLineVirtualSeq seq_;
    seq_ = chiSharedLineVirtualSeq::type_id::create("sharedLineSeq");
    void'(seq_.randomize() with { accessesPerAgent == 24; });
    return seq_;
  endfunction
endclass

// Enough concurrent traffic to exhaust the Home Nodes' transaction pools and
// force the retry handshake. A deeper outstanding limit per Requester is what
// makes this happen: with one transaction each the fabric is never short of
// resources and RetryAck is never sent [SPEC:IHI0050H B2.10].
class chiRetryStressTest extends chiBaseTest;
  `uvm_component_utils(chiRetryStressTest)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    drainCycles = 4000;
  endfunction

  function void configureEnv();
    super.configureEnv();
    foreach (cfg.chiCfg.requesterCfg[i])
      cfg.chiCfg.requesterCfg[i].maxOutstanding = 16;
  endfunction

  function uvm_sequence_base testSequence();
    return chiRetryStressVirtualSeq::type_id::create("retryStressSeq");
  endfunction
endclass

// The same traffic as chiCoherentTrafficTest with one Requester left passive,
// which checks that the environment builds and checks correctly when not every
// agent is driving.
class chiPassiveAgentTest extends chiBaseTest;
  `uvm_component_utils(chiPassiveAgentTest)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void configureEnv();
    super.configureEnv();
    // A passive Requester has no driver, so nothing brings its link up and it
    // stays in STOP. The scoreboard's link check would then fail, which is
    // correct behaviour and the reason this test also relaxes it.
    if (cfg.chiCfg.numRequesterAgents > 1)
      cfg.chiCfg.requesterCfg[cfg.chiCfg.numRequesterAgents-1].isActive =
          UVM_PASSIVE;
    cfg.hasScoreboard = 1'b0;
  endfunction

  function uvm_sequence_base testSequence();
    chiCoherentTrafficVirtualSeq seq_;
    seq_ = chiCoherentTrafficVirtualSeq::type_id::create("coherentTrafficSeq");
    void'(seq_.randomize() with { accessesPerAgent == 8; });
    return seq_;
  endfunction
endclass
