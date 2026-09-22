// Analysis sink for one REQ direction of one port. write() is a
// function, so the scoreboard fan-out it calls is a function too.

class topReqSink extends uvm_subscriber#(chiReqFlitT);
  int unsigned ordinal;
  chiNodeClassE nodeClass;
  bit isTx;
  topScoreboard sb;

  `uvm_component_utils(topReqSink)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ordinal = 0;
    isTx = 1'b0;
    nodeClass = RN_F;
  endfunction

  function void write(chiReqFlitT t);
    sb.chiNoteReq(ordinal, nodeClass, isTx, t);
  endfunction
endclass
