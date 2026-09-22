// Analysis sink for link-state samples on one port.

class topLinkSink extends uvm_subscriber#(chiLinkSampleT);
  int unsigned ordinal;
  topScoreboard sb;

  `uvm_component_utils(topLinkSink)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ordinal = 0;
  endfunction

  function void write(chiLinkSampleT t);
    sb.chiNoteLink(t);
  endfunction
endclass
