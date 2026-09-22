//==============================================================================
// topEnv
//
// The top-level environment. It builds one requester agent per configured
// RN-F/RN-D/RN-I port and one subordinate agent per configured SN-F/SN-I
// port — never for a configured-out class, matching hdlTop, which builds no
// BFM behind a sentinel port — plus the scoreboard with its four reference
// models.
//
// Configuration flows one way: the test builds a topEnvConfig, flips its
// knobs, and publishes it under "topEnvConfig" before this env is created.
// This env reads it, derives one agent config per port from it, and hands a
// copy to the scoreboard. The per-agent configs are kept in the public
// reqCfg/subCfg arrays so a test can reach a specific port's policy after
// the env exists; because the config objects are handles shared with the
// agents, a field the driver reads at run time (the subordinate's retry and
// error-injection policy) can still be turned by a test then.
//
// A test that needs a per-port config the defaults do not produce — a
// different outstanding cap on one requester, say — publishes a fully formed
// chiRequesterConfig/chiSubordinateConfig at the agent's own path before the
// env builds. The env looks there first and uses what it finds untouched;
// only when nothing was published does it derive and publish its own.
//
// Stimulus on/off is one knob, topEnvConfig.activeStimulus: with it cleared
// every agent is built passive, so the monitors, the coverage and the whole
// scoreboard still see the boundary but no driver or sequencer exists. That
// is the mode a bring-up test uses to watch the link come up on its own.
//==============================================================================

class topEnv extends uvm_env;

  topEnvConfig cfg;

  // Agents and their configs, indexed by node ordinal so that a test, a
  // sequence and the log all name a port the same way hdlTop does.
  chiRequesterAgent    reqAgents[int unsigned];
  chiSubordinateAgent  subAgents[int unsigned];
  chiRequesterConfig   reqCfg[int unsigned];
  chiSubordinateConfig subCfg[int unsigned];

  topScoreboard scoreboard;

  `uvm_component_utils(topEnv)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(topEnvConfig)::get(this, "", "topEnvConfig", cfg))
      `uvm_fatal("ENV/CFG", {"no topEnvConfig published: the test must build ",
        "one and set it at the env's path before the env is created"})

    for (int unsigned i = 0; i < chiGlobalsPkg::NUM_RNF; i++)
      buildRequester(chiGlobalsPkg::RN_F, i);
    for (int unsigned i = 0; i < chiGlobalsPkg::NUM_RND; i++)
      buildRequester(chiGlobalsPkg::RN_D, i);
    for (int unsigned i = 0; i < chiGlobalsPkg::NUM_RNI; i++)
      buildRequester(chiGlobalsPkg::RN_I, i);
    for (int unsigned i = 0; i < chiGlobalsPkg::NUM_SNF; i++)
      buildSubordinate(chiGlobalsPkg::SN_F, i);
    for (int unsigned i = 0; i < chiGlobalsPkg::NUM_SNI; i++)
      buildSubordinate(chiGlobalsPkg::SN_I, i);

    scoreboard = topScoreboard::type_id::create("scoreboard", this);
    uvm_config_db#(topEnvConfig)::set(this, "scoreboard", "topEnvConfig", cfg);
  endfunction

  // One requester agent for port index idx of class cls. The config is
  // normalised here as well as in the agent so that the ordinal — and with
  // it the agent's name and its config_db path — is known before the agent
  // exists; chiNormalize is idempotent, so the agent's own call is harmless.
  function automatic void buildRequester(input chiGlobalsPkg::chiNodeClassE cls,
                                         input int unsigned idx);
    chiRequesterConfig c;
    chiRequesterConfig published;
    string nm;
    int unsigned ord;
    c = chiRequesterConfig::type_id::create("reqCfg");
    c.nodeClass = cls;
    c.portIndex = idx;
    c.portActive = 1'b1;
    c.outstandingCap = cfg.requesterOutstanding;
    c.chiNormalize();
    ord = c.nodeOrdinal;
    nm = $sformatf("reqAgent%0d", ord);
    if (uvm_config_db#(chiRequesterConfig)::get(this, nm, "chiRequesterConfig",
                                                published))
      c = published;
    else
      uvm_config_db#(chiRequesterConfig)::set(this, nm, "chiRequesterConfig", c);
    reqCfg[ord] = c;
    reqAgents[ord] = chiRequesterAgent::type_id::create(nm, this);
    reqAgents[ord].is_active = cfg.activeStimulus ? UVM_ACTIVE : UVM_PASSIVE;
  endfunction

  // One subordinate agent for port index idx of class cls, with the
  // environment's retry and error-injection policy as the starting point.
  function automatic void buildSubordinate(input chiGlobalsPkg::chiNodeClassE cls,
                                           input int unsigned idx);
    chiSubordinateConfig c;
    chiSubordinateConfig published;
    string nm;
    int unsigned ord;
    c = chiSubordinateConfig::type_id::create("subCfg");
    c.nodeClass = cls;
    c.portIndex = idx;
    c.portActive = 1'b1;
    c.outstandingCap = cfg.subordinateOutstanding;
    c.enableRetry = cfg.subordinateEnableRetry;
    c.injectRespErr = cfg.subordinateInjectRespErr;
    c.chiNormalize();
    ord = c.nodeOrdinal;
    nm = $sformatf("subAgent%0d", ord);
    if (uvm_config_db#(chiSubordinateConfig)::get(this, nm, "chiSubordinateConfig",
                                                  published))
      c = published;
    else
      uvm_config_db#(chiSubordinateConfig)::set(this, nm, "chiSubordinateConfig", c);
    subCfg[ord] = c;
    subAgents[ord] = chiSubordinateAgent::type_id::create(nm, this);
    subAgents[ord].is_active = cfg.activeStimulus ? UVM_ACTIVE : UVM_PASSIVE;
  endfunction

  // Every monitor proxy's raw sample streams land on the scoreboard's two
  // imps. The guard is for the passive build: an agent whose port is
  // inactive builds no monitor, and there is nothing to connect.
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    foreach (reqAgents[ord]) begin
      if (reqAgents[ord].monitor != null) begin
        reqAgents[ord].monitor.flitSamplePort.connect(scoreboard.flitImp);
        reqAgents[ord].monitor.linkPort.connect(scoreboard.linkImp);
      end
    end
    foreach (subAgents[ord]) begin
      if (subAgents[ord].monitor != null) begin
        subAgents[ord].monitor.flitSamplePort.connect(scoreboard.flitImp);
        subAgents[ord].monitor.linkPort.connect(scoreboard.linkImp);
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("ENV/SUMMARY", $sformatf(
      "topEnv: %0d requester agents, %0d subordinate agents, stimulus %s",
      reqAgents.num(), subAgents.num(),
      cfg.activeStimulus ? "ACTIVE" : "PASSIVE"), UVM_MEDIUM)
  endfunction

endclass
