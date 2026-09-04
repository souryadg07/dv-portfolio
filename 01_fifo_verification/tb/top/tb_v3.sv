`timescale 1ns / 1ps
`define DUMP

module tb_sync_fifo_v3;

  localparam int unsigned DATA_WIDTH = 8;
  localparam int unsigned DEPTH = 4;
  `include "fifo_txn.sv"
  `include "fifo_driver.sv"
  `include "fifo_scoreboard.sv"
  `include "fifo_monitor.sv"
  `include "base_test.sv"
  `include "fifo_tests.sv"

  logic clk_i = 1'b0;
  always #5 clk_i = ~clk_i;

  fifo_if #(
      .DATA_WIDTH(DATA_WIDTH),
      .DEPTH(DEPTH)
  ) fif (
      clk_i
  );
  fifo_driver #(DATA_WIDTH, DEPTH) drv;
  fifo_monitor #(DATA_WIDTH, DEPTH) mon;
  mailbox #(fifo_txn #(DATA_WIDTH)) gen2drv;
  fifo_scoreboard #(DATA_WIDTH) sb;
  mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_wr;
  mailbox #(bit [DATA_WIDTH-1:0]) mon2sb_rd;

  base_test #(DATA_WIDTH, DEPTH) tests[$];
  int total_pass, total_fail;

  sync_fifo #(
      .DATA_WIDTH            (DATA_WIDTH),
      .DEPTH                 (DEPTH),
      .FWFT_ENABLE           (0),
      .OUTPUT_REGISTER_ENABLE(1),
      .CLEAR_MEMORY_ON_RESET (0)
  ) dut (
      .clk_i             (clk_i),
      .rst_ni            (fif.rst_ni),
      .flush_i           (fif.flush_i),
      .wr_en_i           (fif.wr_en_i),
      .wr_data_i         (fif.wr_data_i),
      .rd_en_i           (fif.rd_en_i),
      .rd_data_o         (fif.rd_data_o),
      .rd_valid_o        (fif.rd_valid_o),
      .full_o            (fif.full_o),
      .empty_o           (fif.empty_o),
      .almost_full_o     (fif.almost_full_o),
      .almost_empty_o    (fif.almost_empty_o),
      .occupancy_o       (fif.occupancy_o),
      .free_count_o      (fif.free_count_o),
      .overflow_o        (fif.overflow_o),
      .underflow_o       (fif.underflow_o),
      .overflow_sticky_o (fif.overflow_sticky_o),
      .underflow_sticky_o(fif.underflow_sticky_o)
  );

  initial begin
    fifo_txn #(DATA_WIDTH) t;

    mon2sb_wr = new();
    mon2sb_rd = new();
    sb        = new(mon2sb_wr, mon2sb_rd);
    mon       = new(fif, mon2sb_wr, mon2sb_rd, sb);

    fork
      mon.run();
      sb.run_writes();
      sb.run_reads();
    join_none

    begin
      reset_test #(DATA_WIDTH, DEPTH)     t_reset;
      full_test #(DATA_WIDTH, DEPTH)      t_full;
      flush_test #(DATA_WIDTH, DEPTH)     t_flush;
      overflow_test #(DATA_WIDTH, DEPTH)  t_ovf;
      underflow_test #(DATA_WIDTH, DEPTH) t_unf;

      t_reset = new("reset", fif, sb);
      t_full  = new("full", fif, sb);
      t_flush = new("flush", fif, sb);
      t_ovf   = new("overflow", fif, sb);
      t_unf   = new("underflow", fif, sb);

      tests.push_back(t_reset);
      tests.push_back(t_full);
      tests.push_back(t_flush);
      tests.push_back(t_ovf);
      tests.push_back(t_unf);
    end

    foreach (tests[i]) begin
      $display("--- %s ---", tests[i].name);
      tests[i].run();
      total_pass += tests[i].pass_count;
      total_fail += tests[i].fail_count;
    end


    gen2drv = new();
    drv     = new(fif, gen2drv);
    drv.target_count = 200;

    fork
      drv.run();
    join_none

    repeat (200) begin
      t = new();
      t.randomize_manual();
      gen2drv.put(t);
    end

    wait (drv.all_done.triggered);
    repeat (5) @(fif.cb_mon);

    mon.report();
    mon.report_coverage();
    sb.report();

    total_fail += sb.mismatch_count;

    $display("=== %0d passed, %0d failed ===", total_pass, total_fail);
    $display("%s", total_fail == 0 ? "TEST PASSED" : "TEST FAILED");

    if (total_pass + total_fail == 0) $fatal(1, "No checks executed -- test suite did not run");

    #100 $finish;
  end

`ifdef DUMP
  initial begin
    string wave_file;
    if (!$value$plusargs("wave=%s", wave_file)) wave_file = "dump.vcd";
    $dumpfile(wave_file);
    $dumpvars(0, tb_sync_fifo_v3);
  end
`endif

  initial begin
    #10000;
    $display("TEST FAILED - timeout");
    $fatal(1, "Timeout");
  end

endmodule


