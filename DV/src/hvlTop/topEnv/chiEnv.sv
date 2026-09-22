// Builds one agent per configured requester and subordinate port.
// The node class lives in each agent's config. holdQuiet comes from
// topEnvConfig and is applied before the agent is created.
// [ASSUMPTION:4] [ASSUMPTION:5]

class chiEnv extends uvm_env;
  topEnvConfig cfg;
  chiRequesterAgent rnfAgent[$];
  chiRequesterAgent rndAgent[$];
  chiRequesterAgent rniAgent[$];
  chiSubordinateAgent snfAgent[$];
  chiSubordinateAgent sniAgent[$];
  chiSubordinateMemory sharedMem;

  `uvm_component_utils(chiEnv)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(topEnvConfig)::get(this, "", "topEnvConfig", cfg))
      `uvm_fatal("topEnvConfig", "config_db get failed for key topEnvConfig")
    sharedMem = chiSubordinateMemory::type_id::create("chiSubordinateMemory");
    chiBuildRnf();
    chiBuildRnd();
    chiBuildRni();
    chiBuildSnf();
    chiBuildSni();
  endfunction

  function void chiBuildRnf();
    for (int unsigned i = 0; i < NUM_RNF; i++) begin
      chiRequesterConfig portCfg;
      string leaf;
      leaf = $sformatf("rnfAgent[%0d]", i);
      portCfg = chiRequesterConfig::type_id::create(leaf);
      portCfg.nodeClass = RN_F;
      portCfg.portIndex = i;
      portCfg.holdQuiet = cfg.chiHoldQuiet(RN_F, i);
      portCfg.chiNormalize();
      uvm_config_db#(chiRequesterConfig)::set(this, leaf, "chiRequesterConfig", portCfg);
      rnfAgent.push_back(chiRequesterAgent::type_id::create(leaf, this));
    end
  endfunction

  function void chiBuildRnd();
    for (int unsigned i = 0; i < NUM_RND; i++) begin
      chiRequesterConfig portCfg;
      string leaf;
      leaf = $sformatf("rndAgent[%0d]", i);
      portCfg = chiRequesterConfig::type_id::create(leaf);
      portCfg.nodeClass = RN_D;
      portCfg.portIndex = i;
      portCfg.holdQuiet = cfg.chiHoldQuiet(RN_D, i);
      portCfg.chiNormalize();
      uvm_config_db#(chiRequesterConfig)::set(this, leaf, "chiRequesterConfig", portCfg);
      rndAgent.push_back(chiRequesterAgent::type_id::create(leaf, this));
    end
  endfunction

  function void chiBuildRni();
    for (int unsigned i = 0; i < NUM_RNI; i++) begin
      chiRequesterConfig portCfg;
      string leaf;
      leaf = $sformatf("rniAgent[%0d]", i);
      portCfg = chiRequesterConfig::type_id::create(leaf);
      portCfg.nodeClass = RN_I;
      portCfg.portIndex = i;
      portCfg.holdQuiet = cfg.chiHoldQuiet(RN_I, i);
      portCfg.chiNormalize();
      uvm_config_db#(chiRequesterConfig)::set(this, leaf, "chiRequesterConfig", portCfg);
      rniAgent.push_back(chiRequesterAgent::type_id::create(leaf, this));
    end
  endfunction

  function void chiBuildSnf();
    for (int unsigned i = 0; i < NUM_SNF; i++) begin
      chiSubordinateConfig portCfg;
      string leaf;
      leaf = $sformatf("snfAgent[%0d]", i);
      portCfg = chiSubordinateConfig::type_id::create(leaf);
      portCfg.nodeClass = SN_F;
      portCfg.portIndex = i;
      portCfg.holdQuiet = cfg.chiHoldQuiet(SN_F, i);
      portCfg.chiNormalize();
      uvm_config_db#(chiSubordinateConfig)::set(this, leaf, "chiSubordinateConfig", portCfg);
      uvm_config_db#(chiSubordinateMemory)::set(this, leaf, "chiSubordinateMemory", sharedMem);
      snfAgent.push_back(chiSubordinateAgent::type_id::create(leaf, this));
    end
  endfunction

  function void chiBuildSni();
    for (int unsigned i = 0; i < NUM_SNI; i++) begin
      chiSubordinateConfig portCfg;
      string leaf;
      leaf = $sformatf("sniAgent[%0d]", i);
      portCfg = chiSubordinateConfig::type_id::create(leaf);
      portCfg.nodeClass = SN_I;
      portCfg.portIndex = i;
      portCfg.holdQuiet = cfg.chiHoldQuiet(SN_I, i);
      portCfg.chiNormalize();
      uvm_config_db#(chiSubordinateConfig)::set(this, leaf, "chiSubordinateConfig", portCfg);
      uvm_config_db#(chiSubordinateMemory)::set(this, leaf, "chiSubordinateMemory", sharedMem);
      sniAgent.push_back(chiSubordinateAgent::type_id::create(leaf, this));
    end
  endfunction
endclass
