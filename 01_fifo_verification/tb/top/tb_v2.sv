`timescale 1ns/1ps
`define DUMP

module tb_sync_fifo_v2;

    localparam int unsigned DATA_WIDTH = 8;
    localparam int unsigned DEPTH      = 4;

    logic clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    fifo_if #(.DATA_WIDTH(DATA_WIDTH), .DEPTH(DEPTH)) fif (clk_i);

    task automatic fifo_write(input logic [DATA_WIDTH-1:0] data);
        fif.cb_drv.wr_en_i   <= 1'b1;
        fif.cb_drv.wr_data_i <= data;
        @(fif.cb_drv);                  // DUT samples here
        fif.cb_drv.wr_en_i   <= 1'b0;
        fif.cb_drv.wr_data_i <= '0;
    endtask

    task automatic do_reset();
        fif.rst_ni = 1'b0;              // note: blocking `=` is correct here
        fif.flush_i = 1'b0;
        fif.wr_en_i = 1'b0;
        fif.rd_en_i = 1'b0;
        fif.wr_data_i = '0;
        repeat (2) @(posedge clk_i);
        fif.rst_ni = 1'b1;
        @(fif.cb_drv);
    endtask

    task automatic fifo_read(output logic [DATA_WIDTH-1:0] data,
                             output bit                    valid);
        fif.cb_drv.rd_en_i <= 1'b1;
        @(fif.cb_drv);              // DUT accepts the read at this edge
        fif.cb_drv.rd_en_i <= 1'b0;
        @(fif.cb_mon);              // rd_data_o / rd_valid_o now observable
        valid = fif.cb_mon.rd_valid_o;
        data  = fif.cb_mon.rd_data_o;
    endtask

    task automatic fifo_flush();
        fif.cb_drv.flush_i <= 1'b1;
        @(fif.cb_drv);
        fif.cb_drv.flush_i <= 1'b0;
        @(fif.cb_mon);
    endtask

    int pass_count, fail_count;
    task automatic check(string name, bit condition);
        if (condition) begin
            pass_count++;
            $display("PASS: %s", name);
        end else begin
            fail_count++;
            $error("FAIL: %s", name);
        end
    endtask

    sync_fifo #(
        .DATA_WIDTH             (DATA_WIDTH),
        .DEPTH                  (DEPTH),
        .FWFT_ENABLE            (0),
        .OUTPUT_REGISTER_ENABLE (1),
        .CLEAR_MEMORY_ON_RESET  (0)
    ) dut (
        .clk_i      (clk_i),
        .rst_ni     (fif.rst_ni),
        .flush_i    (fif.flush_i),
        .wr_en_i    (fif.wr_en_i),
        .wr_data_i  (fif.wr_data_i),
        .rd_en_i    (fif.rd_en_i),
        .rd_data_o  (fif.rd_data_o),
        .rd_valid_o (fif.rd_valid_o),
        .full_o     (fif.full_o),
        .empty_o     (fif.empty_o),
        .almost_full_o     (fif.almost_full_o),
        .almost_empty_o     (fif.almost_empty_o),
        .occupancy_o     (fif.occupancy_o),
        .free_count_o     (fif.free_count_o),
        .overflow_o     (fif.overflow_o),
        .underflow_o     (fif.underflow_o),
        .overflow_sticky_o     (fif.overflow_sticky_o),
        .underflow_sticky_o     (fif.underflow_sticky_o)
    );

    initial begin
        logic [DATA_WIDTH-1:0] rdata;
        bit                    rvalid;

        do_reset();
        check("empty after reset",     fif.cb_mon.empty_o);
        check("not full after reset", !fif.cb_mon.full_o);
        check("occupancy 0 after reset", fif.cb_mon.occupancy_o == 0);

        fifo_write(8'h11);
        fifo_write(8'h22);
        fifo_write(8'h33);
        @(fif.cb_mon);
        check("occupancy 3 after 3 writes", fif.cb_mon.occupancy_o == 3);

        fifo_read(rdata, rvalid);
        check("read 1 valid", rvalid);
        check("read 1 data",  rdata == 8'h11);

        fifo_read(rdata, rvalid);
        check("read 2 valid", rvalid);
        check("read 2 data",  rdata == 8'h22);

        check("occupancy 1 after 2 reads", fif.cb_mon.occupancy_o == 1);

        // flush from partially filled
        fifo_write(8'h44);
        fifo_flush();
        check("empty after flush",       fif.cb_mon.empty_o);
        check("occupancy 0 after flush", fif.cb_mon.occupancy_o == 0);
        check("free == DEPTH",           fif.cb_mon.free_count_o == DEPTH);

        // reusable after flush
        fifo_write(8'hA5);
        fifo_read(rdata, rvalid);
        check("reuse after flush", rvalid && rdata == 8'hA5);

        $display("=== %0d passed, %0d failed ===", pass_count, fail_count);
        $display(fail_count == 0 ? "TEST PASSED" : "TEST FAILED");

        #100
        $finish;
    end

    `ifdef DUMP
    initial begin
        string wave_file;
        if (!$value$plusargs("wave=%s", wave_file))
            wave_file = "dump.vcd";
        $dumpfile(wave_file);
        $dumpvars(0, tb_sync_fifo_v2);
    end
    `endif

    initial begin
        #10000;
        $display("TEST FAILED - timeout");
        $fatal(1, "Timeout");
    end

endmodule


