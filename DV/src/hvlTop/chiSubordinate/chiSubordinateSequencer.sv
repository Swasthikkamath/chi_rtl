// Carries response-policy rules to one Subordinate driver. There is no
// response channel back: a rule is advice the driver applies to whatever
// arrives, not a request that completes.

class chiSubordinateSequencer extends uvm_sequencer#(chiSubordinateTx);
  chiSubordinateConfig cfg;

  `uvm_component_utils(chiSubordinateSequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
