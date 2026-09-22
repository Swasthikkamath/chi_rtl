// Carries the port configuration so a sequence can read the policy it
// is about to update.

class chiSubordinateSequencer extends uvm_sequencer#(chiSubordinateTx);
  chiSubordinateConfig cfg;

  `uvm_component_utils(chiSubordinateSequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
