// Shared-line traffic that can forward a snoop, when dctEn is set.
// [ASSUMPTION:15]

class chiDctTest extends chiBaseTest;
  `uvm_component_utils(chiDctTest)

  function new(string name = "chiDctTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.dctEn, "dctEn"))
      return;
    if (chiSkip(NUM_RNF < 2, "NUM_RNF < 2"))
      return;
    chiStart(CHI_VSEQ_SHARED);
  endtask
endclass
