// Analysis sink for one RSP direction of one port.

class topRspSink extends uvm_subscriber#(chiRspFlitT);
  int unsigned ordinal;
  chiNodeClassE nodeClass;
  bit isTx;
  topScoreboard sb;

  `uvm_component_utils(topRspSink)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ordinal = 0;
    isTx = 1'b0;
    nodeClass = RN_F;
  endfunction

  function void write(chiRspFlitT t);
    sb.chiNoteRsp(ordinal, nodeClass, isTx, t);
  endfunction
endclass
