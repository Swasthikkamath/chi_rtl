// One DVMOp from RN-F 0. expectDvmDbidResp stays at its default of 0,
// which tolerates the missing DBIDResp phase. [ASSUMPTION:14]
// See OPEN QUESTIONS Q11.

class chiDvmTest extends chiBaseTest;
  `uvm_component_utils(chiDvmTest)

  function new(string name = "chiDvmTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.dvmEn, "dvmEn"))
      return;
    chiStart(CHI_VSEQ_DVM);
  endtask
endclass
