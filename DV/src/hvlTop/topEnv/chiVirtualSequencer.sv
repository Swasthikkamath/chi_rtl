// Handles for every active sequencer. A virtual sequence starts
// per-port sequences on these. Passive ports leave a null handle.

class chiVirtualSequencer extends uvm_sequencer;
  chiRequesterSequencer rnfSeqr[$];
  chiRequesterSequencer rndSeqr[$];
  chiRequesterSequencer rniSeqr[$];
  chiSubordinateSequencer snfSeqr[$];
  chiSubordinateSequencer sniSeqr[$];

  `uvm_component_utils(chiVirtualSequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
endclass
