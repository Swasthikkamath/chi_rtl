// Virtual sequencer: handles to every agent sequencer in the environment.
//
// The arrays are sized from the environment configuration rather than fixed,
// because the number of agents is a configuration parameter. A virtual
// sequence walks these arrays, which is how one sequence body covers any agent
// count.
class chiVirtualSequencer extends uvm_sequencer;

  chiEnvConfig cfg;

  chiRequesterSequencer   requesterSequencer   [];
  chiSubordinateSequencer subordinateSequencer [];

  `uvm_component_utils(chiVirtualSequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(chiEnvConfig)::get(this, "", "chiEnvConfig", cfg))
      `uvm_fatal(get_type_name(), "no chiEnvConfig")
    requesterSequencer   = new[cfg.numRequesterAgents];
    subordinateSequencer = new[cfg.numSubordinateAgents];
  endfunction
endclass
