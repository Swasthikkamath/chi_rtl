// Carries the port configuration so a sequence can constrain items to
// the node class without reaching into the driver.

class chiRequesterSequencer extends uvm_sequencer#(chiRequesterTx);
  chiRequesterConfig cfg;

  `uvm_component_utils(chiRequesterSequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
