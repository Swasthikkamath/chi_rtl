// Configuration for the top environment.
class topEnvConfig extends uvm_object;

  chiEnvConfig chiCfg;

  bit hasScoreboard = 1'b1;
  bit hasCoverage   = 1'b1;

  `uvm_object_utils(topEnvConfig)

  function new(string name = "topEnvConfig");
    super.new(name);
  endfunction

  function void initialise();
    chiCfg = chiEnvConfig::type_id::create("chiCfg");
    chiCfg.initialise();
  endfunction
endclass
