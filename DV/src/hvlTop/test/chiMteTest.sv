// One ReadNoSnp with TagOp set. Tag and TU are on the flit whether or
// not mteEn is set; this test runs only when the enable is set.
// [ASSUMPTION:15] [SPEC:IHI0050H B13.9.1]

class chiMteTest extends chiBaseTest;
  `uvm_component_utils(chiMteTest)

  function new(string name = "chiMteTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.mteEn, "mteEn"))
      return;
    pinTagOp = 1'b1;
    tagOpValue = 2'b01;
    chiStart(CHI_VSEQ_READ);
  endtask
endclass
