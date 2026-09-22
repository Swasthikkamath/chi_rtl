// One ReadNoSnp from RN-D 0. The default configuration has no RN-D,
// and this test reports SKIP in that case. [ASSUMPTION:5]

class chiRndReadTest extends chiBaseTest;
  `uvm_component_utils(chiRndReadTest)

  function new(string name = "chiRndReadTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (chiSkip(NUM_RND == 0, "NUM_RND == 0"))
      return;
    chiStart(CHI_VSEQ_RND_READ);
  endtask
endclass
