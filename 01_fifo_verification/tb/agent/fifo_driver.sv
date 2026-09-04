class fifo_driver #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH      = 4
);

  virtual fifo_if #(DATA_WIDTH, DEPTH) vif;
  mailbox #(fifo_txn #(DATA_WIDTH))    gen2drv;
  int                                  drive_count;

  function new(virtual fifo_if #(DATA_WIDTH, DEPTH) vif, mailbox#(fifo_txn#(DATA_WIDTH)) gen2drv);
    this.vif     = vif;
    this.gen2drv = gen2drv;
  endfunction

  // Drive one transaction for one clock cycle.
  task automatic drive(fifo_txn#(DATA_WIDTH) t);
    vif.cb_drv.wr_en_i   <= t.wr_en;
    vif.cb_drv.rd_en_i   <= t.rd_en;
    vif.cb_drv.wr_data_i <= t.wr_data;
    @(vif.cb_drv);
    vif.cb_drv.wr_en_i <= 1'b0;
    vif.cb_drv.rd_en_i <= 1'b0;
    drive_count++;
  endtask

  // Pull transactions forever. Blocks when the mailbox is empty.
  task automatic run();
    fifo_txn #(DATA_WIDTH) t;
    forever begin
      gen2drv.get(t);  // blocking: waits until something arrives
      drive(t);
    end
  endtask

endclass
