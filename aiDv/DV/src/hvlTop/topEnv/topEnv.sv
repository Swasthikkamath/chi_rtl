// Top environment: the CHI environment plus the checking and coverage that
// span every agent.
//
// The scoreboard and the cross-agent coverage live here rather than inside the
// agents because both need to see all ports at once. A per-agent scoreboard
// could check that one Requester's own transactions completed, but not that
// two Requesters never held the same line Unique, which is the property that
// actually matters.
class topEnv extends uvm_env;

  topEnvConfig cfg;

  chiEnv        chiEnvironment;
  topScoreboard scoreboard;
  topCoverage   coverage;

  `uvm_component_utils(topEnv)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(topEnvConfig)::get(this, "", "topEnvConfig", cfg))
      `uvm_fatal(get_type_name(), "no topEnvConfig")

    uvm_config_db #(chiEnvConfig)::set(this, "*", "chiEnvConfig", cfg.chiCfg);

    chiEnvironment = chiEnv::type_id::create("chiEnvironment", this);

    if (cfg.hasScoreboard)
      scoreboard = topScoreboard::type_id::create("scoreboard", this);
    if (cfg.hasCoverage)
      coverage = topCoverage::type_id::create("coverage", this);
  endfunction

  // Each monitor's single analysis port fans out to both the scoreboard and
  // the cross-agent coverage. This is what the one-port arrangement buys: a
  // second port would need connecting twice here and unpacking twice in both
  // subscribers.
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    for (int unsigned i = 0; i < cfg.chiCfg.numRequesterAgents; i++) begin
      if (cfg.hasScoreboard)
        chiEnvironment.requesterAgent[i].monitorProxy.analysisPort.connect(
            scoreboard.requesterFifo[i].analysis_export);
      if (cfg.hasCoverage)
        chiEnvironment.requesterAgent[i].monitorProxy.analysisPort.connect(
            coverage.requesterFifo[i].analysis_export);
    end

    if (cfg.hasScoreboard)
      for (int unsigned i = 0; i < cfg.chiCfg.numSubordinateAgents; i++)
        chiEnvironment.subordinateAgent[i].monitorProxy.analysisPort.connect(
            scoreboard.subordinateFifo[i].analysis_export);
  endfunction
endclass
