// Analysis sink for L-Credit grants. Credits are carried as events rather
// than counted only at the end, because a flit sent one cycle before its
// credit arrives leaves the same total behind as one sent a cycle after,
// and only the live ledger in topLinkModel can tell the two apart.
// [SPEC:IHI0050H B14.2 Flow control]

class topCreditSink extends uvm_subscriber#(chiCreditSampleT);
  topScoreboard sb;

  `uvm_component_utils(topCreditSink)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void write(chiCreditSampleT t);
    sb.chiNoteCredit(t);
  endfunction
endclass
