// One Requester agent.
//
// The agent is the same component for every Requester class. What changes with
// class is held in the configuration and read from it here: only a fully
// coherent Requester gets a cache model, because only it holds cacheable state
// [SPEC:IHI0050H B1.6.1].
class chiRequesterAgent extends uvm_agent;

  chiRequesterAgentConfig cfg;

  chiRequesterSequencer     sequencer;
  chiRequesterDriverProxy   driverProxy;
  chiRequesterMonitorProxy  monitorProxy;
  chiRequesterCoverage      coverage;
  chiRequesterCacheModel    cacheModel;

  `uvm_component_utils(chiRequesterAgent)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(chiRequesterAgentConfig)::get(
            this, "", "chiRequesterAgentConfig", cfg))
      `uvm_fatal(get_type_name(), "no chiRequesterAgentConfig")

    monitorProxy     = chiRequesterMonitorProxy::type_id::create("monitorProxy",
                                                                 this);
    monitorProxy.cfg = cfg;
    if (!uvm_config_db #(virtual chiMonitorBfm)::get(
            this, "", $sformatf("chiRequesterMonitorBfm_%0d", cfg.agentId),
            monitorProxy.bfm))
      `uvm_fatal(get_type_name(),
                 $sformatf("no monitor BFM for requester %0d", cfg.agentId))

    coverage     = chiRequesterCoverage::type_id::create("coverage", this);
    coverage.cfg = cfg;

    if (cfg.isActive == UVM_ACTIVE) begin
      sequencer     = chiRequesterSequencer::type_id::create("sequencer", this);
      sequencer.cfg = cfg;

      driverProxy     = chiRequesterDriverProxy::type_id::create("driverProxy",
                                                                 this);
      driverProxy.cfg = cfg;
      if (!uvm_config_db #(virtual chiRequesterDriverBfm)::get(
              this, "", $sformatf("chiRequesterDriverBfm_%0d", cfg.agentId),
              driverProxy.bfm))
        `uvm_fatal(get_type_name(),
                   $sformatf("no driver BFM for requester %0d", cfg.agentId))

      if (cfg.hasCache) begin
        cacheModel = chiRequesterCacheModel::type_id::create("cacheModel");
        driverProxy.cache = cacheModel;
      end
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    monitorProxy.analysisPort.connect(coverage.analysis_export);
    if (cfg.isActive == UVM_ACTIVE)
      driverProxy.seq_item_port.connect(sequencer.seq_item_export);
  endfunction
endclass
