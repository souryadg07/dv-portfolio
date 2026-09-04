class reset_test #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH      = 4
) extends base_test #(DATA_WIDTH, DEPTH);

  function new(string name, virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
               fifo_scoreboard#(DATA_WIDTH) sb);
    super.new(name, vif, sb);  // ← parent constructor MUST be called
  endfunction

  virtual task run();
    do_reset();  // inherited
    check("empty after reset", vif.cb_mon.empty_o);
    check("not full after reset", !vif.cb_mon.full_o);
    check("occupancy 0 after reset", vif.cb_mon.occupancy_o == 0);
  endtask

endclass


class full_test #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH      = 4
) extends base_test #(DATA_WIDTH, DEPTH);

  function new(string name, virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
               fifo_scoreboard#(DATA_WIDTH) sb);
    super.new(name, vif, sb);
  endfunction

  virtual task run();
    logic [DATA_WIDTH-1:0] rdata;
    bit                    rvalid;

    fifo_write(8'h11);
    fifo_write(8'h22);
    fifo_write(8'h33);
    fifo_write(8'h44);
    @(vif.cb_mon);
    check("full after 4 writes", vif.cb_mon.full_o);
    check("occupancy 4 after 4 writes", vif.cb_mon.occupancy_o == 4);

    fifo_read(rdata, rvalid);
    check("read 1 valid", rvalid);
    check("read 1 data", rdata == 8'h11);

    fifo_read(rdata, rvalid);
    check("read 2 valid", rvalid);
    check("read 2 data", rdata == 8'h22);

    check("occupancy 2 after 2 reads", vif.cb_mon.occupancy_o == 2);
  endtask

endclass


class flush_test #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH      = 4
) extends base_test #(DATA_WIDTH, DEPTH);

  function new(string name, virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
               fifo_scoreboard#(DATA_WIDTH) sb);
    super.new(name, vif, sb);
  endfunction

  virtual task run();
    logic [DATA_WIDTH-1:0] rdata;
    bit                    rvalid;

    fifo_write(8'h44);
    fifo_flush();
    check("empty after flush",       vif.cb_mon.empty_o);
    check("occupancy 0 after flush", vif.cb_mon.occupancy_o == 0);
    check("free == DEPTH",           vif.cb_mon.free_count_o == DEPTH);

    // FIFO must still work normally after a flush.
    fifo_write(8'hA5);
    fifo_read(rdata, rvalid);
    check("reuse after flush", rvalid && rdata == 8'hA5);
  endtask

endclass


class overflow_test #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH      = 4
) extends base_test #(DATA_WIDTH, DEPTH);

  function new(string name, virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
               fifo_scoreboard#(DATA_WIDTH) sb);
    super.new(name, vif, sb);
  endfunction

  virtual task run();
    logic [DATA_WIDTH-1:0] rdata;
    bit                    rvalid;

    fifo_write(8'h01);
    fifo_write(8'h02);
    fifo_write(8'h03);
    fifo_write(8'h04);
    @(vif.cb_mon);
    check("full before overflow", vif.cb_mon.full_o);

    fifo_write(8'hFF);                    // rejected write
    @(vif.cb_mon);                        // overflow_o is registered
    check("overflow_o pulsed",       vif.cb_mon.overflow_o);
    check("overflow sticky latched", vif.cb_mon.overflow_sticky_o);
    check("occupancy unchanged",     vif.cb_mon.occupancy_o == DEPTH);

    // The rejected write must not have corrupted stored data.
    fifo_read(rdata, rvalid);
    check("oldest data intact after overflow", rvalid && rdata == 8'h01);
  endtask

endclass


class underflow_test #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH      = 4
) extends base_test #(DATA_WIDTH, DEPTH);

  function new(string name, virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
               fifo_scoreboard#(DATA_WIDTH) sb);
    super.new(name, vif, sb);
  endfunction

  virtual task run();
    logic [DATA_WIDTH-1:0] rdata;
    bit                    rvalid;

    fifo_flush();
    check("empty before underflow", vif.cb_mon.empty_o);

    // No extra @(cb_mon) here -- fifo_read already advances to the edge
    // where the one-cycle underflow_o pulse is visible.
    fifo_read(rdata, rvalid);
    check("underflow_o pulsed",         vif.cb_mon.underflow_o);
    check("underflow sticky latched",   vif.cb_mon.underflow_sticky_o);
    check("no valid data on underflow", !rvalid);
    check("occupancy still zero",       vif.cb_mon.occupancy_o == 0);
  endtask

endclass