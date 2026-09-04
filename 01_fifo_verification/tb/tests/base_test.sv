// Base test: owns the environment handle, the DUT-poking tasks, and the
// pass/fail bookkeeping. Every concrete test extends this and overrides
// run() with its own scenario.
class base_test #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH      = 4
);

  virtual fifo_if #(DATA_WIDTH, DEPTH) vif;
  fifo_scoreboard #(DATA_WIDTH)        sb;

  string                               name;
  int                                  pass_count;
  int                                  fail_count;

  function new(string name, virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
               fifo_scoreboard#(DATA_WIDTH) sb);
    this.name = name;
    this.vif  = vif;
    this.sb   = sb;
  endfunction

  // ---- The thing derived tests override. `virtual` is what makes
  // ---- polymorphism work; without it, a base handle always runs
  // ---- this empty version instead of the derived one.
  virtual task run();
//  task run();
    $display("base_test::run() -- nothing to do");
  endtask

  // ---- Shared helpers, inherited by every derived test ----

  task automatic check(string label, bit condition);
    if (condition) begin
      pass_count++;
      $display("  PASS: %s", label);
    end else begin
      fail_count++;
      $error("  FAIL: %s", label);
    end
  endtask

  task automatic fifo_write(input logic [DATA_WIDTH-1:0] data);
    vif.cb_drv.wr_en_i   <= 1'b1;
    vif.cb_drv.wr_data_i <= data;
    @(vif.cb_drv);
    vif.cb_drv.wr_en_i   <= 1'b0;
    vif.cb_drv.wr_data_i <= '0;
  endtask

  task automatic fifo_read(output logic [DATA_WIDTH-1:0] data, output bit valid);
    vif.cb_drv.rd_en_i <= 1'b1;
    @(vif.cb_drv);
    vif.cb_drv.rd_en_i <= 1'b0;
    @(vif.cb_mon);
    valid = vif.cb_mon.rd_valid_o;
    data  = vif.cb_mon.rd_data_o;
  endtask

  task automatic fifo_flush();
    vif.cb_drv.flush_i <= 1'b1;
    @(vif.cb_drv);
    vif.cb_drv.flush_i <= 1'b0;
    @(vif.cb_mon);
  endtask

  task automatic do_reset();
    vif.rst_ni    = 1'b0;
    vif.flush_i   = 1'b0;
    vif.wr_en_i   = 1'b0;
    vif.rd_en_i   = 1'b0;
    vif.wr_data_i = '0;
    repeat (2) @(posedge vif.clk_i);
    vif.rst_ni = 1'b1;
    @(vif.cb_drv);
  endtask

endclass
