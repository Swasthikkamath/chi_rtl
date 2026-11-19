// Passive reconstruction of one Subordinate port's activity.
//
// As with the Requester monitor, everything here comes from the pins rather
// than from the driver, so a driver that builds a malformed flit is reported
// as having sent what it actually sent.
class chiSubordinateMonitorProxy extends uvm_monitor;

  chiSubordinateAgentConfig cfg;
  virtual chiMonitorBfm     bfm;

  uvm_analysis_port #(chiSubordinateTx) analysisPort;

  protected int unsigned flitsSeen;
  protected int unsigned eventsSeen;

  `uvm_component_utils(chiSubordinateMonitorProxy)

  function new(string name, uvm_component parent);
    super.new(name, parent);
    analysisPort = new("analysisPort", this);
  endfunction

  task run_phase(uvm_phase phase);
    fork
      flitLoop();
      eventLoop();
    join
  endtask

  protected task flitLoop();
    chiSampledFlitS  sample;
    chiSubordinateTx tx;
    forever begin
      bfm.getFlit(sample);
      tx = chiSubordinateTx::type_id::create("tx");
      tx.txKind    = CHI_TX_PROTOCOL_FLIT;
      tx.direction = sample.direction;
      tx.channel   = sample.channel;
      tx.agentId   = cfg.agentId;
      tx.nodeClass = cfg.nodeClass;

      case (sample.channel)
        CHI_CHANNEL_REQ:
          tx.reqFlit = unpackReqFlit(CHI_CFG,
              sample.flit[CHI_MAX_REQ_FLIT_W-1:0]);
        CHI_CHANNEL_RSP:
          tx.rspFlit = unpackRspFlit(CHI_CFG,
              sample.flit[CHI_MAX_RSP_FLIT_W-1:0]);
        CHI_CHANNEL_DAT:
          tx.datFlit = unpackDatFlit(CHI_CFG,
              sample.flit[CHI_MAX_DAT_FLIT_W-1:0]);
        default:
          // A Subordinate has no snoop channel carrying protocol content, so
          // anything here is a finding rather than an observation
          // [SPEC:IHI0050H B1.6.1].
          `uvm_error(get_type_name(), "snoop flit observed at a Subordinate")
      endcase

      flitsSeen++;
      `uvm_info(get_type_name(), tx.convert2string(), UVM_DEBUG)
      analysisPort.write(tx);
    end
  endtask

  protected task eventLoop();
    chiLinkEventS    event_;
    chiSubordinateTx tx;
    forever begin
      bfm.getLinkEvent(event_);
      tx = chiSubordinateTx::type_id::create("tx");
      tx.txKind    = CHI_TX_LINK_EVENT;
      tx.linkEvent = event_;
      tx.direction = event_.direction;
      tx.channel   = event_.channel;
      tx.agentId   = cfg.agentId;
      tx.nodeClass = cfg.nodeClass;
      eventsSeen++;
      analysisPort.write(tx);
    end
  endtask

  function void report_phase(uvm_phase phase);
    `uvm_info(get_type_name(),
              $sformatf("subordinate %0d %s: %0d flits, %0d link events",
                        cfg.agentId, cfg.nodeClass.name(), flitsSeen,
                        eventsSeen), UVM_LOW)
  endfunction
endclass
