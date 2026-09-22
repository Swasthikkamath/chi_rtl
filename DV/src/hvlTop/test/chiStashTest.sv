// One StashOnceShared from RN-F 0 when stashEn is set.
// [ASSUMPTION:15] [SPEC:IHI0050H B8.5]

class chiStashTest extends chiBaseTest;
  `uvm_component_utils(chiStashTest)

  function new(string name = "chiStashTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.stashEn, "stashEn"))
      return;
    chiStart(CHI_VSEQ_STASH);
  endtask
endclass
