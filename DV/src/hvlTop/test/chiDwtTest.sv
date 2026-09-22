// One WriteNoSnp, which is the request a direct write transfer would
// carry, when dwtEn is set. [ASSUMPTION:15]

class chiDwtTest extends chiBaseTest;
  `uvm_component_utils(chiDwtTest)

  function new(string name = "chiDwtTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.dwtEn, "dwtEn"))
      return;
    chiStart(CHI_VSEQ_WRITE);
  endtask
endclass
