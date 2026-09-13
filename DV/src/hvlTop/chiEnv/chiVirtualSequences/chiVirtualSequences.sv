// Virtual sequence library: what runs across all agents at once.
//
// Every one of these starts the Subordinate response policies before it starts
// any Requester traffic. The ordering is not cosmetic: a Subordinate with no
// policy sequence running still answers requests using its configured default,
// but starting the policies first means the latency profile a test asked for
// is in force from the first request rather than from part way through.
//
// None of these wait for the links to come up. Bring-up is the driver's own
// first action and the link layer blocks every send until its channel has a
// credit, so a request issued at time zero is held at the link layer until it
// can legally go. A virtual sequence that polled for link state would be
// duplicating that interlock, and would have to reach into the BFMs to do it.

class chiVirtualBaseSeq extends uvm_sequence #(uvm_sequence_item);

  chiVirtualSequencer localSequencer;
  chiEnvConfig        cfg;

  `uvm_object_utils(chiVirtualBaseSeq)

  function new(string name = "chiVirtualBaseSeq");
    super.new(name);
  endfunction

  task pre_start();
    if (!$cast(localSequencer, m_sequencer))
      `uvm_fatal(get_type_name(), "sequencer is not a chiVirtualSequencer")
    cfg = localSequencer.cfg;
  endtask

  // Subordinate policies run for the whole test, so they are launched without
  // being waited on.
  protected task startSubordinateResponders();
    for (int unsigned i = 0; i < cfg.numSubordinateAgents; i++) begin
      if (localSequencer.subordinateSequencer[i] == null) continue;
      fork
        automatic int unsigned k = i;
        begin
          chiSubordinateFixedLatencySeq seq_;
          seq_ = chiSubordinateFixedLatencySeq::type_id::create(
                     $sformatf("subResp_%0d", k));
          void'(seq_.randomize() with { latency == 2; });
          seq_.start(localSequencer.subordinateSequencer[k]);
        end
      join_none
    end
    #0;
  endtask

  protected task startSubordinateRandomResponders();
    for (int unsigned i = 0; i < cfg.numSubordinateAgents; i++) begin
      if (localSequencer.subordinateSequencer[i] == null) continue;
      fork
        automatic int unsigned k = i;
        begin
          chiSubordinateRandomLatencySeq seq_;
          seq_ = chiSubordinateRandomLatencySeq::type_id::create(
                     $sformatf("subResp_%0d", k));
          void'(seq_.randomize());
          seq_.start(localSequencer.subordinateSequencer[k]);
        end
      join_none
    end
    #0;
  endtask
endclass

// Bring the links up and do nothing else. This is the test that tells you
// whether the two sides of every link agree, before any protocol activity
// could confuse the picture.
class chiLinkBringUpVirtualSeq extends chiVirtualBaseSeq;
  `uvm_object_utils(chiLinkBringUpVirtualSeq)

  function new(string name = "chiLinkBringUpVirtualSeq");
    super.new(name);
  endfunction

  task body();
    startSubordinateResponders();
    // The drivers bring their own links up in run_phase. Nothing else is
    // needed here; the scoreboard's link accounting is what judges the result.
  endtask
endclass

// Reads and writes from every Requester at once, over a shared address window
// so that the Requesters contend and the Home Nodes have to snoop.
class chiCoherentTrafficVirtualSeq extends chiVirtualBaseSeq;

  rand int unsigned accessesPerAgent;

  constraint countRange {
    accessesPerAgent inside {[4:64]};
  }

  `uvm_object_utils(chiCoherentTrafficVirtualSeq)

  function new(string name = "chiCoherentTrafficVirtualSeq");
    super.new(name);
    accessesPerAgent = 16;
  endfunction

  task body();
    startSubordinateResponders();

    // All Requesters run together and the sequence returns when the last one
    // finishes, which is what makes them contend rather than take turns.
    fork
      begin
        for (int unsigned i = 0; i < cfg.numRequesterAgents; i++) begin
          if (localSequencer.requesterSequencer[i] == null) continue;
          fork
            automatic int unsigned k = i;
            begin
              chiRequesterRandomSeq seq_;
              seq_ = chiRequesterRandomSeq::type_id::create(
                         $sformatf("reqTraffic_%0d", k));
              void'(seq_.randomize() with {
                      accessCount == accessesPerAgent;
                    });
              // One window shared by every agent, so two Requesters reach for
              // the same line and the fabric has to keep them coherent.
              seq_.addrBase  = 'h0000_2000;
              seq_.addrRange = 'h0000_0800;
              seq_.start(localSequencer.requesterSequencer[k]);
            end
          join_none
        end
        wait fork;
      end
    join
  endtask
endclass

// Heavy contention on a handful of lines. This is what generates snoops in
// volume, including the ones that have to move dirty data.
class chiSharedLineVirtualSeq extends chiVirtualBaseSeq;

  rand int unsigned accessesPerAgent;

  constraint countRange {
    accessesPerAgent inside {[4:64]};
  }

  `uvm_object_utils(chiSharedLineVirtualSeq)

  function new(string name = "chiSharedLineVirtualSeq");
    super.new(name);
    accessesPerAgent = 24;
  endfunction

  task body();
    startSubordinateRandomResponders();
    fork
      begin
        for (int unsigned i = 0; i < cfg.numRequesterAgents; i++) begin
          if (localSequencer.requesterSequencer[i] == null) continue;
          fork
            automatic int unsigned k = i;
            begin
              chiRequesterSharedLineSeq seq_;
              seq_ = chiRequesterSharedLineSeq::type_id::create(
                         $sformatf("reqShared_%0d", k));
              void'(seq_.randomize() with {
                      accessCount == accessesPerAgent;
                    });
              seq_.addrBase  = 'h0000_4000;
              seq_.addrRange = 4 * CHI_LINE_BYTES;
              seq_.start(localSequencer.requesterSequencer[k]);
            end
          join_none
        end
        wait fork;
      end
    join
  endtask
endclass

// Push hard enough that the Home Nodes run out of transaction slots and start
// answering RetryAck. Without a test like this the retry path is dead code
// that nothing has ever executed [SPEC:IHI0050H B2.10].
class chiRetryStressVirtualSeq extends chiVirtualBaseSeq;
  `uvm_object_utils(chiRetryStressVirtualSeq)

  function new(string name = "chiRetryStressVirtualSeq");
    super.new(name);
  endfunction

  task body();
    // Slow Subordinates keep each Home Node's transaction occupied for longer,
    // which is what makes its pool fill.
    startSubordinateRandomResponders();
    fork
      begin
        for (int unsigned i = 0; i < cfg.numRequesterAgents; i++) begin
          if (localSequencer.requesterSequencer[i] == null) continue;
          fork
            automatic int unsigned k = i;
            begin
              chiRequesterRetryStressSeq seq_;
              seq_ = chiRequesterRetryStressSeq::type_id::create(
                         $sformatf("reqRetry_%0d", k));
              void'(seq_.randomize());
              seq_.start(localSequencer.requesterSequencer[k]);
            end
          join_none
        end
        wait fork;
      end
    join
  endtask
endclass
