// CHI environment: every agent, plus the virtual sequencer that coordinates
// them.
//
// The agents are built from the configuration array, so the agent count and
// each agent's classification come from one place. Nothing here is written per
// class: an RN-F agent and an RN-I agent are the same component built from
// different configuration, which is what lets the count and the mix change
// without editing this file.
class chiEnv extends uvm_env;

  chiEnvConfig cfg;

  chiRequesterAgent   requesterAgent   [];
  chiSubordinateAgent subordinateAgent [];

  chiVirtualSequencer virtualSequencer;

  `uvm_component_utils(chiEnv)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db #(chiEnvConfig)::get(this, "", "chiEnvConfig", cfg))
      `uvm_fatal(get_type_name(), "no chiEnvConfig")

    requesterAgent   = new[cfg.numRequesterAgents];
    subordinateAgent = new[cfg.numSubordinateAgents];

    // Each agent's configuration is published on the path of that agent alone,
    // so agent i cannot pick up agent j's classification.
    for (int unsigned i = 0; i < cfg.numRequesterAgents; i++) begin
      uvm_config_db #(chiRequesterAgentConfig)::set(
          this, $sformatf("requesterAgent_%0d*", i),
          "chiRequesterAgentConfig", cfg.requesterCfg[i]);
      requesterAgent[i] = chiRequesterAgent::type_id::create(
                              $sformatf("requesterAgent_%0d", i), this);
    end

    for (int unsigned i = 0; i < cfg.numSubordinateAgents; i++) begin
      uvm_config_db #(chiSubordinateAgentConfig)::set(
          this, $sformatf("subordinateAgent_%0d*", i),
          "chiSubordinateAgentConfig", cfg.subordinateCfg[i]);
      subordinateAgent[i] = chiSubordinateAgent::type_id::create(
                                $sformatf("subordinateAgent_%0d", i), this);
    end

    virtualSequencer = chiVirtualSequencer::type_id::create("virtualSequencer",
                                                            this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    for (int unsigned i = 0; i < cfg.numRequesterAgents; i++)
      if (cfg.requesterCfg[i].isActive == UVM_ACTIVE)
        virtualSequencer.requesterSequencer[i] = requesterAgent[i].sequencer;
    for (int unsigned i = 0; i < cfg.numSubordinateAgents; i++)
      if (cfg.subordinateCfg[i].isActive == UVM_ACTIVE)
        virtualSequencer.subordinateSequencer[i] =
            subordinateAgent[i].sequencer;
  endfunction
endclass
