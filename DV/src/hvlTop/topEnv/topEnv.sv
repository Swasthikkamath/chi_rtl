// Integration environment. One chiEnv holds every requester and
// subordinate agent. The scoreboard owns the four reference models.
// The virtual sequencer collects the active sequencers only.
// [ASSUMPTION:18] [ASSUMPTION:18a]

class topEnv extends uvm_env;
  topEnvConfig cfg;
  chiEnv agents;
  topScoreboard scoreboard;
  topCoverage cov;
  chiVirtualSequencer virtualSequencer;

  `uvm_component_utils(topEnv)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(topEnvConfig)::get(this, "", "topEnvConfig", cfg)) begin
      cfg = topEnvConfig::type_id::create("topEnvConfig");
      uvm_config_db#(topEnvConfig)::set(this, "", "topEnvConfig", cfg);
    end
    uvm_config_db#(topEnvConfig)::set(this, "agents", "topEnvConfig", cfg);
    uvm_config_db#(topEnvConfig)::set(this, "scoreboard", "topEnvConfig", cfg);
    agents = chiEnv::type_id::create("agents", this);
    scoreboard = topScoreboard::type_id::create("scoreboard", this);
    cov = topCoverage::type_id::create("cov", this);
    virtualSequencer = chiVirtualSequencer::type_id::create("virtualSequencer", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    scoreboard.cov = cov;
    foreach (agents.rnfAgent[i])
      chiConnectRequester(agents.rnfAgent[i]);
    foreach (agents.rndAgent[i])
      chiConnectRequester(agents.rndAgent[i]);
    foreach (agents.rniAgent[i])
      chiConnectRequester(agents.rniAgent[i]);
    foreach (agents.snfAgent[i])
      chiConnectSubordinate(agents.snfAgent[i]);
    foreach (agents.sniAgent[i])
      chiConnectSubordinate(agents.sniAgent[i]);
  endfunction

  function void chiConnectRequester(input chiRequesterAgent agent);
    int unsigned ordinal;
    if ((agent == null) || (agent.monitor == null))
      return;
    ordinal = agent.cfg.nodeOrdinal;
    agent.monitor.txReqPort.connect(scoreboard.txReqSink[ordinal].analysis_export);
    agent.monitor.rxReqPort.connect(scoreboard.rxReqSink[ordinal].analysis_export);
    agent.monitor.txRspPort.connect(scoreboard.txRspSink[ordinal].analysis_export);
    agent.monitor.rxRspPort.connect(scoreboard.rxRspSink[ordinal].analysis_export);
    agent.monitor.txDatPort.connect(scoreboard.txDatSink[ordinal].analysis_export);
    agent.monitor.rxDatPort.connect(scoreboard.rxDatSink[ordinal].analysis_export);
    agent.monitor.rxSnpPort.connect(scoreboard.rxSnpSink[ordinal].analysis_export);
    agent.monitor.linkPort.connect(scoreboard.linkSink[ordinal].analysis_export);
    if (agent.sequencer == null)
      return;
    if (agent.cfg.nodeClass == RN_D)
      virtualSequencer.rndSeqr.push_back(agent.sequencer);
    else if (agent.cfg.nodeClass == RN_I)
      virtualSequencer.rniSeqr.push_back(agent.sequencer);
    else
      virtualSequencer.rnfSeqr.push_back(agent.sequencer);
  endfunction

  function void chiConnectSubordinate(input chiSubordinateAgent agent);
    int unsigned ordinal;
    if ((agent == null) || (agent.monitor == null))
      return;
    ordinal = agent.cfg.nodeOrdinal;
    // flitPort is every sample, including CompAck and L-Credit returns that
    // have no typed port. Connecting the typed ports as well would count
    // those flits twice.
    agent.monitor.flitPort.connect(scoreboard.flitSink[ordinal].analysis_export);
    agent.monitor.linkPort.connect(scoreboard.linkSink[ordinal].analysis_export);
    if (agent.sequencer == null)
      return;
    if (agent.cfg.nodeClass == SN_I)
      virtualSequencer.sniSeqr.push_back(agent.sequencer);
    else
      virtualSequencer.snfSeqr.push_back(agent.sequencer);
  endfunction
endclass
