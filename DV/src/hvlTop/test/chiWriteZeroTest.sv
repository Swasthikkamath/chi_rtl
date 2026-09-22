// WriteNoSnpZero, then ReadNoSnp of the same line. The memory model
// zeros the transfer on Comp and compares the read. [ASSUMPTION:8]

class chiWriteZeroTest extends chiBaseTest;
  `uvm_component_utils(chiWriteZeroTest)

  function new(string name = "chiWriteZeroTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_ZERO);
  endtask
endclass
