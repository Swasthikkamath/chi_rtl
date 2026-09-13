// Sequencer for one Requester agent.
//
// It carries the agent configuration so that a sequence running on it can see
// the class of the Requester it is driving, which is how one sequence library
// serves a fully coherent and an I/O coherent master without the test having
// to pick a different sequence per class.
class chiRequesterSequencer extends uvm_sequencer #(chiRequesterTx);

  chiRequesterAgentConfig cfg;

  `uvm_component_utils(chiRequesterSequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
