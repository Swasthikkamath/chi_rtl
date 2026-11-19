// Subordinate sequence library.
//
// These supply response policy, not transactions. The driver answers requests
// whether or not one of these is running; what they change is how long it
// takes and, later, whether an error is reported.

class chiSubordinateBaseSeq extends uvm_sequence #(chiSubordinateTx);

  chiSubordinateSequencer localSequencer;

  // How many policy items to offer. The driver consumes one per request it
  // serves and falls back to the configured default when none is waiting, so
  // this is a supply that can legitimately run out.
  rand int unsigned policyCount;

  constraint reasonableCount {
    policyCount inside {[1:512]};
  }

  `uvm_object_utils(chiSubordinateBaseSeq)

  function new(string name = "chiSubordinateBaseSeq");
    super.new(name);
    policyCount = 256;
  endfunction

  task pre_start();
    if (!$cast(localSequencer, m_sequencer))
      `uvm_fatal(get_type_name(), "sequencer is not a chiSubordinateSequencer")
  endtask
endclass

// Constant, short latency. The least interesting behaviour and the easiest to
// debug against, so it is what the first traffic test uses.
class chiSubordinateFixedLatencySeq extends chiSubordinateBaseSeq;
  rand int unsigned latency;

  constraint latencyRange {
    latency inside {[0:8]};
  }

  `uvm_object_utils(chiSubordinateFixedLatencySeq)

  function new(string name = "chiSubordinateFixedLatencySeq");
    super.new(name);
    latency = 2;
  endfunction

  task body();
    chiSubordinateTx item;
    for (int unsigned i = 0; i < policyCount; i++) begin
      item = chiSubordinateTx::type_id::create("item");
      start_item(item);
      if (!item.randomize() with {
            responseDelay == local::latency;
            injectError   == RESP_ERR_OK;
          })
        `uvm_error(get_type_name(), "randomization failed")
      finish_item(item);
    end
  endtask
endclass

// Varying latency, so responses from different Subordinates interleave and
// arrive at the Home Nodes out of request order. This is what exercises the
// fabric's reordering rather than just its happy path.
class chiSubordinateRandomLatencySeq extends chiSubordinateBaseSeq;
  `uvm_object_utils(chiSubordinateRandomLatencySeq)

  function new(string name = "chiSubordinateRandomLatencySeq");
    super.new(name);
  endfunction

  task body();
    chiSubordinateTx item;
    for (int unsigned i = 0; i < policyCount; i++) begin
      item = chiSubordinateTx::type_id::create("item");
      start_item(item);
      if (!item.randomize() with {
            responseDelay inside {[0:12]};
            injectError == RESP_ERR_OK;
          })
        `uvm_error(get_type_name(), "randomization failed")
      finish_item(item);
    end
  endtask
endclass
