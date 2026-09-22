// One ReadNoSnp, which is the request a direct memory transfer would
// carry, when dmtEn is set. [ASSUMPTION:15]

class chiDmtTest extends chiBaseTest;
  `uvm_component_utils(chiDmtTest)

  function new(string name = "chiDmtTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.dmtEn, "dmtEn"))
      return;
    chiStart(CHI_VSEQ_READ);
  endtask
endclass
