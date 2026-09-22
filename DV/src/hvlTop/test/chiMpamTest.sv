// One ReadNoSnp with MPAM set, when mpamEn is set. The slot is 15 bits
// whenever the enable is on. [ASSUMPTION:15] See OPEN QUESTIONS Q15.

class chiMpamTest extends chiBaseTest;
  `uvm_component_utils(chiMpamTest)

  function new(string name = "chiMpamTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (!chiGate(CHI_CFG.mpamEn, "mpamEn"))
      return;
    pinMpam = 1'b1;
    mpamValue = 15'h15;
    chiStart(CHI_VSEQ_READ);
  endtask
endclass
