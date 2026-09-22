// CleanShared, CleanInvalid, and MakeInvalid. These opcodes are not
// behind a feature enable. [SPEC:IHI0050H B8.4]

class chiCmoTest extends chiBaseTest;
  `uvm_component_utils(chiCmoTest)

  function new(string name = "chiCmoTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_CMO);
  endtask
endclass
