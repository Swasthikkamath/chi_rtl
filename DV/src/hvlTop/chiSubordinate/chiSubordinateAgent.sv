// One agent covers SN-F and SN-I, with the node class in the config rather
// than in a subclass, matching the requester agent.
//
// A passive Subordinate is a real configuration and not only a debug aid:
// with the driver absent nothing answers the interconnect, which is how a
// test proves the DUT does not depend on a response arriving before it can
// make progress elsewhere.

class chiSubordinateAgent extends uvm_agent;
  chiSubordinateConfig cfg;
  chiSubordinateMemory mem;
  chiSubordinateSequencer sequencer;
  chiSubordinateDriverProxy driver;
  chiSubordinateMonitorProxy monitor;
  chiSubordinateCoverage cov;

  `uvm_component_utils(chiSubordinateAgent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(chiSubordinateConfig)::get(this, "", "chiSubordinateConfig", cfg))
      `uvm_fatal("chiSubordinateConfig", "config_db get failed for key chiSubordinateConfig")
    cfg.chiNormalize();
    if (!cfg.portActive) begin
      is_active = UVM_PASSIVE;
      return;
    end
    monitor = chiSubordinateMonitorProxy::type_id::create("monitor", this);
    cov = chiSubordinateCoverage::type_id::create("cov", this);
    cov.cfg = cfg;
    uvm_config_db#(chiSubordinateConfig)::set(this, "monitor", "chiSubordinateConfig", cfg);
    uvm_config_db#(chiSubordinateConfig)::set(this, "cov", "chiSubordinateConfig", cfg);
    if (is_active == UVM_ACTIVE) begin
      // The store is created by whoever builds the agents and shared across
      // all of them, because the DUT decides which port an address reaches.
      if (!uvm_config_db#(chiSubordinateMemory)::get(this, "", "chiSubordinateMemory", mem))
        `uvm_fatal("chiSubordinateMemory", "config_db get failed for key chiSubordinateMemory")
      sequencer = chiSubordinateSequencer::type_id::create("sequencer", this);
      driver = chiSubordinateDriverProxy::type_id::create("driver", this);
      sequencer.cfg = cfg;
      uvm_config_db#(chiSubordinateConfig)::set(this, "driver", "chiSubordinateConfig", cfg);
      uvm_config_db#(chiSubordinateMemory)::set(this, "driver", "chiSubordinateMemory", mem);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (!cfg.portActive)
      return;
    if (is_active == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
      driver.cov = cov;
    end
  endfunction
endclass
