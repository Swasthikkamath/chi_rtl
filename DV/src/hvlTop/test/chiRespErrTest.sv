// Subordinates answer with NDERR. Two things must happen and only the
// first was being checked: the read must still complete, so the link can
// deactivate, and the error must still be NDERR when it reaches the
// Requester. An interconnect that quietly replaced the error with OK
// would retire the transaction just as cleanly, so the lifecycle alone
// cannot tell the two apart.
// [SPEC:IHI0050H B9.4 Error response] [SPEC:IHI0050H B4.8]

class chiRespErrTest extends chiBaseTest;
  `uvm_component_utils(chiRespErrTest)

  function new(string name = "chiRespErrTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_RESP_ERR);
  endtask

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (env.scoreboard.lifecycleModel.rnNonDataErrSeen == 0)
      `uvm_error("chiRespErrTest",
        {"every Subordinate was answering NDERR and no Requester ever received a ",
         "non-data error; the interconnect did not carry the error back"})
    else
      `uvm_info("chiRespErrTest",
        $sformatf("%0d NDERR completions reached a Requester",
                  env.scoreboard.lifecycleModel.rnNonDataErrSeen), UVM_LOW)
  endfunction
endclass
