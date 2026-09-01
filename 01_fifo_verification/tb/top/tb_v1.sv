`timescale 1ns/1ps
`define DUMP
module tb_sync_fifo;

    localparam int unsigned DATA_WIDTH = 8;
    localparam int unsigned DEPTH      = 4;

    logic clk_i;
    logic rst_ni;
    logic flush_i;

    logic                  wr_en_i;
    logic [DATA_WIDTH-1:0] wr_data_i;

    logic                  rd_en_i;
    logic [DATA_WIDTH-1:0] rd_data_o;
    logic                  rd_valid_o;

    logic full_o;
    logic empty_o;
    logic almost_full_o;
    logic almost_empty_o;

    logic [$clog2(DEPTH+1)-1:0] occupancy_o;
    logic [$clog2(DEPTH+1)-1:0] free_count_o;

    logic overflow_o;
    logic underflow_o;
    logic overflow_sticky_o;
    logic underflow_sticky_o;

    // 100 MHz clock
    initial clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    // One waveform idiom for both simulators: run.py passes +define+DUMP and
    // +wave=<path>, so Questa and Verilator emit the same VCD for GTKWave.
    `ifdef DUMP
    initial begin
        string wave_file;
        if (!$value$plusargs("wave=%s", wave_file))
            wave_file = "dump.vcd";
        $dumpfile(wave_file);
        $dumpvars(0, tb_sync_fifo);
    end
    `endif

    sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(DEPTH),
        .FWFT_ENABLE(0),
        .OUTPUT_REGISTER_ENABLE(1),
        .CLEAR_MEMORY_ON_RESET(0)
    ) dut (
        .*
    );

    initial begin
        rst_ni  = 1'b0;
        flush_i = 1'b0;
        wr_en_i = 1'b0;
        wr_data_i = '0;
        rd_en_i = 1'b0;

        // Hold reset for two clock cycles.
        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;

        // Avoid checking in the same simulation region as the clock edge.
        @(posedge clk_i);
        #1;

        assert (empty_o)
            $display("PASS: FIFO is empty after reset");
        else
            $fatal(1, "FAIL: FIFO must be empty after reset");

        assert (!full_o)
            $display("PASS: FIFO is not full after reset");
        else
            $fatal(1, "FAIL: FIFO must not be full after reset");

        assert (occupancy_o == 0)
            $display("PASS: FIFO occupancy is zero after reset");
        else
            $fatal(1, "FAIL: FIFO occupancy must be zero after reset");

        $display("RESET TEST PASSED");

        // Further tests will be added here.

        $finish;
    end

endmodule