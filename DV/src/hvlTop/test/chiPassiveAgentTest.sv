// RN-F 1 is held quiet: its driver drives STOP and issues nothing.
// RN-F 0 issues one ReadNoSnp. The quiet port's request count stays 0.
// [ASSUMPTION:18] See OPEN QUESTIONS Q18.

class chiPassiveAgentTest extends chiBaseTest;
  `uvm_component_utils(chiPassiveAgentTest)

  function new(string name = "chiPassiveAgentTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    topEnvConfig cfg;
    if (NUM_RNF >= 2) begin
      cfg = topEnvConfig::type_id::create("topEnvConfig");
      cfg.holdQuietRnf[1] = 1'b1;
      uvm_config_db#(topEnvConfig)::set(this, "env", "topEnvConfig", cfg);
    end
    super.build_phase(phase);
  endfunction

  task chiRun();
    int unsigned quietOrdinal;
    if (chiSkip(NUM_RNF < 2, "NUM_RNF < 2"))
      return;
    chiStart(CHI_VSEQ_READ);
    quietOrdinal = OFF_RNF + 1;
    if (env.scoreboard.lifecycleModel.txReqCount.exists(quietOrdinal)
        && (env.scoreboard.lifecycleModel.txReqCount[quietOrdinal] != 0))
      `uvm_error("chiPassiveAgentTest", "quiet RN-F issued a request")
    if (!env.scoreboard.lifecycleModel.txReqCount.exists(OFF_RNF)
        || (env.scoreboard.lifecycleModel.txReqCount[OFF_RNF] == 0))
      `uvm_error("chiPassiveAgentTest", "active RN-F issued no request")
  endtask
endclass
