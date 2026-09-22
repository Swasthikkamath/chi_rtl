// An exclusive load followed by an exclusive store on one line.
// [ASSUMPTION:15] [SPEC:IHI0050H B2.10]

class chiExclusiveTest extends chiBaseTest;
  `uvm_component_utils(chiExclusiveTest)

  function new(string name = "chiExclusiveTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.exclEn, "exclEn"))
      return;
    chiStart(CHI_VSEQ_EXCL);
  endtask
endclass
