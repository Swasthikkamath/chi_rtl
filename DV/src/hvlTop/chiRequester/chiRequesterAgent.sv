// One agent covers RN-F, RN-D, and RN-I. The node class lives in the
// config, not in a subclass, so a passive port and an active port share
// the same code. An inactive port builds nothing.

class chiRequesterAgent extends uvm_agent;
  chiRequesterConfig cfg;
  chiRequesterSequencer sequencer;
  chiRequesterDriverProxy driver;
  chiRequesterMonitorProxy monitor;
  chiRequesterCoverage cov;

  `uvm_component_utils(chiRequesterAgent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(chiRequesterConfig)::get(this, "", "chiRequesterConfig", cfg))
      `uvm_fatal("chiRequesterConfig", "config_db get failed for key chiRequesterConfig")
    cfg.chiNormalize();
    if (!cfg.portActive) begin
      is_active = UVM_PASSIVE;
      return;
    end
    monitor = chiRequesterMonitorProxy::type_id::create("monitor", this);
    cov = chiRequesterCoverage::type_id::create("cov", this);
    cov.cfg = cfg;
    uvm_config_db#(chiRequesterConfig)::set(this, "monitor", "chiRequesterConfig", cfg);
    uvm_config_db#(chiRequesterConfig)::set(this, "cov", "chiRequesterConfig", cfg);
    if (is_active == UVM_ACTIVE) begin
      sequencer = chiRequesterSequencer::type_id::create("sequencer", this);
      driver = chiRequesterDriverProxy::type_id::create("driver", this);
      sequencer.cfg = cfg;
      uvm_config_db#(chiRequesterConfig)::set(this, "driver", "chiRequesterConfig", cfg);
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
