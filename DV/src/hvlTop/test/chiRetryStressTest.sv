// Every subordinate retries the next AllowRetry=1 request once, then
// RN-F 0 issues several ReadNoSnp transactions. [ASSUMPTION:6]
// See OPEN QUESTIONS Q6.

class chiRetryStressTest extends chiBaseTest;
  `uvm_component_utils(chiRetryStressTest)

  function new(string name = "chiRetryStressTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_RETRY);
  endtask
endclass
