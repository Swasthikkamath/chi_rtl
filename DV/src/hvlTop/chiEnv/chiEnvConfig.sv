// Configuration for the CHI environment.
//
// This is where the agent count and the per-instance classification are
// decided. Both are derived from chiGlobalsPkg by default, which means they
// are derived from the same chi_cfg_t the DUT was elaborated with, so an agent
// cannot go missing or be built as the wrong class when the configuration
// changes. A test that wants something different overrides the arrays after
// calling initialise.
class chiEnvConfig extends uvm_object;

  int unsigned numRequesterAgents;
  int unsigned numSubordinateAgents;

  chiRequesterAgentConfig   requesterCfg   [];
  chiSubordinateAgentConfig subordinateCfg [];

  // Checking and coverage are separable so a long soak run can keep the
  // checks and drop the sampling cost, or a bring-up run can do neither.
  bit hasScoreboard = 1'b1;
  bit hasCoverage   = 1'b1;

  `uvm_object_utils(chiEnvConfig)

  function new(string name = "chiEnvConfig");
    super.new(name);
  endfunction

  // Build one configuration per agent, each carrying its own classification.
  // The class of Requester agent i comes from requesterClassOf, which is the
  // same function hdlTop used to decide which interface array that agent's
  // BFMs were attached to. Using one function for both is what keeps the HVL
  // agent and the HDL port it drives in agreement.
  function void initialise();
    numRequesterAgents   = NUM_REQUESTER_AGENTS;
    numSubordinateAgents = NUM_SUBORDINATE_AGENTS;

    requesterCfg   = new[numRequesterAgents];
    subordinateCfg = new[numSubordinateAgents];

    for (int unsigned i = 0; i < numRequesterAgents; i++) begin
      requesterCfg[i]           = chiRequesterAgentConfig::type_id::create(
                                      $sformatf("requesterCfg_%0d", i));
      requesterCfg[i].agentId   = i;
      requesterCfg[i].nodeClass = requesterClassOf(i);
      requesterCfg[i].configureFromClass();
    end

    for (int unsigned i = 0; i < numSubordinateAgents; i++) begin
      subordinateCfg[i]           = chiSubordinateAgentConfig::type_id::create(
                                        $sformatf("subordinateCfg_%0d", i));
      subordinateCfg[i].agentId   = i;
      subordinateCfg[i].nodeClass = subordinateClassOf(i);
      subordinateCfg[i].configureFromClass();
    end
  endfunction

  function string convert2string();
    string text;
    text = $sformatf("chiEnvConfig: %0d requesters, %0d subordinates\n",
                     numRequesterAgents, numSubordinateAgents);
    foreach (requesterCfg[i])
      text = {text, "  ", requesterCfg[i].convert2string(), "\n"};
    foreach (subordinateCfg[i])
      text = {text, "  ", subordinateCfg[i].convert2string(), "\n"};
    return text;
  endfunction
endclass
