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
    if (cfg.holdQuiet)
      is_active = UVM_PASSIVE;
    monitor = chiRequesterMonitorProxy::type_id::create("monitor", this);
    cov = chiRequesterCoverage::type_id::create("cov", this);
    cov.cfg = cfg;
    uvm_config_db#(chiRequesterConfig)::set(this, "monitor", "chiRequesterConfig", cfg);
    uvm_config_db#(chiRequesterConfig)::set(this, "cov", "chiRequesterConfig", cfg);
    // The driver owns the pins even when the port is passive, so they
    // are driven to STOP instead of X. It does not take sequences then.
    driver = chiRequesterDriverProxy::type_id::create("driver", this);
    uvm_config_db#(chiRequesterConfig)::set(this, "driver", "chiRequesterConfig", cfg);
    if (!cfg.holdQuiet) begin
      sequencer = chiRequesterSequencer::type_id::create("sequencer", this);
      sequencer.cfg = cfg;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    if (!cfg.portActive)
      return;
    if (sequencer != null) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
      driver.cov = cov;
    end
  endfunction
endclass
