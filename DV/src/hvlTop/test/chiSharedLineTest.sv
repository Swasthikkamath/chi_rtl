// Two RN-F ports read the same line shared, then the first takes it
// unique. Requires two RN-F ports. [SPEC:IHI0050H B4.2]

class chiSharedLineTest extends chiBaseTest;
  `uvm_component_utils(chiSharedLineTest)

  function new(string name = "chiSharedLineTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (chiSkip(NUM_RNF < 2, "NUM_RNF < 2"))
      return;
    chiStart(CHI_VSEQ_SHARED);
  endtask
endclass
