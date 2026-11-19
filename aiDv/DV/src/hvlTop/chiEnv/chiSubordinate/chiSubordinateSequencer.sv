// Sequencer for one Subordinate agent.
//
// A Subordinate originates no transactions, so what runs on this sequencer is
// response policy rather than stimulus. The driver polls it without blocking,
// so leaving it idle is a valid configuration and simply means the configured
// default latency applies.
class chiSubordinateSequencer extends uvm_sequencer #(chiSubordinateTx);

  chiSubordinateAgentConfig cfg;

  `uvm_component_utils(chiSubordinateSequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
