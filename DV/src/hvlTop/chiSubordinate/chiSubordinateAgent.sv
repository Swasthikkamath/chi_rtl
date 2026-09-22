// One agent covers SN-F and SN-I. The node class lives in the config,
// not in a subclass, so a passive port and an active port share the
// same code. An inactive port builds nothing.

class chiSubordinateAgent extends uvm_agent;
  chiSubordinateConfig cfg;
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
      sequencer = chiSubordinateSequencer::type_id::create("sequencer", this);
      driver = chiSubordinateDriverProxy::type_id::create("driver", this);
      sequencer.cfg = cfg;
      uvm_config_db#(chiSubordinateConfig)::set(this, "driver", "chiSubordinateConfig", cfg);
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
