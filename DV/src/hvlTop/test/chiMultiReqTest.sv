// Always SKIP. The DUT ignores multiReqEn, and the requester drives
// MultiReq as 0. [ASSUMPTION:15] See OPEN QUESTIONS finding F-4.

class chiMultiReqTest extends chiBaseTest;
  `uvm_component_utils(chiMultiReqTest)

  function new(string name = "chiMultiReqTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    if (chiSkip(1'b1, "multiReqEn is ignored by the DUT (F-4)"))
      return;
  endtask
endclass
