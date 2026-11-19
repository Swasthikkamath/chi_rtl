// One Subordinate agent.
//
// Every Subordinate gets a memory model, whatever its class: both SN-F and
// SN-I are endpoints that must return data for a read and retain it for a
// write. What differs between them is which address region the fabric routes
// to them, which is the System Address Map's business rather than the agent's.
class chiSubordinateAgent extends uvm_agent;

  chiSubordinateAgentConfig cfg;

  chiSubordinateSequencer    sequencer;
  chiSubordinateDriverProxy  driverProxy;
  chiSubordinateMonitorProxy monitorProxy;
  chiSubordinateCoverage     coverage;
  chiSubordinateMemoryModel  memoryModel;

  `uvm_component_utils(chiSubordinateAgent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(chiSubordinateAgentConfig)::get(
            this, "", "chiSubordinateAgentConfig", cfg))
      `uvm_fatal(get_type_name(), "no chiSubordinateAgentConfig")

    monitorProxy     = chiSubordinateMonitorProxy::type_id::create(
                           "monitorProxy", this);
    monitorProxy.cfg = cfg;
    if (!uvm_config_db #(virtual chiMonitorBfm)::get(
            this, "", $sformatf("chiSubordinateMonitorBfm_%0d", cfg.agentId),
            monitorProxy.bfm))
      `uvm_fatal(get_type_name(),
                 $sformatf("no monitor BFM for subordinate %0d", cfg.agentId))

    coverage     = chiSubordinateCoverage::type_id::create("coverage", this);
    coverage.cfg = cfg;

    if (cfg.isActive == UVM_ACTIVE) begin
      sequencer     = chiSubordinateSequencer::type_id::create("sequencer",
                                                               this);
      sequencer.cfg = cfg;

      driverProxy     = chiSubordinateDriverProxy::type_id::create(
                            "driverProxy", this);
      driverProxy.cfg = cfg;
      if (!uvm_config_db #(virtual chiSubordinateDriverBfm)::get(
              this, "", $sformatf("chiSubordinateDriverBfm_%0d", cfg.agentId),
              driverProxy.bfm))
        `uvm_fatal(get_type_name(),
                   $sformatf("no driver BFM for subordinate %0d", cfg.agentId))

      memoryModel        = chiSubordinateMemoryModel::type_id::create(
                               "memoryModel");
      driverProxy.memory = memoryModel;
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    monitorProxy.analysisPort.connect(coverage.analysis_export);
    if (cfg.isActive == UVM_ACTIVE)
      driverProxy.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
