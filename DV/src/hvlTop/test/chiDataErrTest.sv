// A data error on one line, and a clean read of another line in the same
// run. Where chiRespErrTest makes every response an error and so only asks
// whether errors survive the crossing at all, this one asks whether an
// error is delivered to the transaction it belongs to: the DERR must reach
// the read of the line it was injected for, and the read of the other line
// must still come back OK.
//
// An interconnect that attaches a completion to the wrong transaction
// passes every lifecycle and ordering check, because both transactions do
// complete. The line the error landed on is the only thing that separates
// the two cases. [SPEC:IHI0050H B9.4 Error response]

class chiDataErrTest extends chiBaseTest;
  `uvm_component_utils(chiDataErrTest)

  function new(string name = "chiDataErrTest", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  task chiRun();
    chiStart(CHI_VSEQ_DATA_ERR);
  endtask

  function void check_phase(uvm_phase phase);
    chiAddrT errLine;
    chiAddrT cleanLine;
    super.check_phase(phase);
    errLine = lineAlign(coherentLineAddr(CHI_ERR_LINE_INDEX));
    cleanLine = lineAlign(coherentLineAddr(CHI_CLEAN_LINE_INDEX));
    if (!env.scoreboard.lifecycleModel.rnErrByLine.exists(errLine))
      `uvm_error("chiDataErrTest",
        $sformatf({"a Subordinate answered line %0h with DERR and the Requester that ",
                   "read that line never saw an error"}, errLine))
    if (env.scoreboard.lifecycleModel.rnErrByLine.exists(cleanLine))
      `uvm_error("chiDataErrTest",
        $sformatf({"line %0h had no error injected for it and the Requester received ",
                   "%0d error completions for it"},
                  cleanLine, env.scoreboard.lifecycleModel.rnErrByLine[cleanLine]))
    if (env.scoreboard.lifecycleModel.rnNonDataErrSeen != 0)
      `uvm_error("chiDataErrTest",
        $sformatf("a DERR was injected and %0d NDERR completions arrived",
                  env.scoreboard.lifecycleModel.rnNonDataErrSeen))
  endfunction
endclass
