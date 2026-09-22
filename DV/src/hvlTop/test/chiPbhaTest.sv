// One ReadNoSnp with PBHA set, when pbhaEn is set.
// [ASSUMPTION:15] [SPEC:IHI0050H B13.9.1]

class chiPbhaTest extends chiBaseTest;
  `uvm_component_utils(chiPbhaTest)

  function new(string name = "chiPbhaTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.pbhaEn, "pbhaEn"))
      return;
    pinPbha = 1'b1;
    pbhaValue = 'h5;
    chiStart(CHI_VSEQ_READ);
  endtask
endclass
