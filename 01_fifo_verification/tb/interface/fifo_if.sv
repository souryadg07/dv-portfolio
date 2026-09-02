`timescale 1ns/1ps
interface fifo_if #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH      = 4
) (input logic clk_i);
    logic rst_ni;

    logic                  flush_i;
    logic                  wr_en_i;
    logic [DATA_WIDTH-1:0] wr_data_i;
    logic                  rd_en_i;

    logic [DATA_WIDTH-1:0] rd_data_o;
    logic                  rd_valid_o;
    logic                  full_o;
    logic                  empty_o;
    logic                  almost_full_o;
    logic                  almost_empty_o;

    logic [$clog2(DEPTH+1)-1:0] occupancy_o;
    logic [$clog2(DEPTH+1)-1:0] free_count_o;

    logic overflow_o;
    logic underflow_o;
    logic overflow_sticky_o;
    logic underflow_sticky_o;

    // ------------------------------------------------------------
    // Driver clocking block
    // ------------------------------------------------------------
    clocking cb_drv @(posedge clk_i);
        default input #1step output #1ns; //Read inputs 1 step before the clock edge; drive outputs 1 ns after it.

        output flush_i;
        output wr_en_i;
        output wr_data_i;
        output rd_en_i;

        input  full_o;
        input  empty_o;
        input  occupancy_o;
    endclocking

    // ------------------------------------------------------------
    // Monitor clocking block
    // ------------------------------------------------------------
    clocking cb_mon @(posedge clk_i);
        default input #1step; //Read inputs 1 step before the clock edge;

        input flush_i;
        input wr_en_i;
        input wr_data_i;
        input rd_en_i;

        input rd_data_o;
        input rd_valid_o;
        input full_o;
        input empty_o;
        input almost_full_o;
        input almost_empty_o;

        input occupancy_o;
        input free_count_o;

        input overflow_o;
        input underflow_o;
        input overflow_sticky_o;
        input underflow_sticky_o;
    endclocking

    // ------------------------------------------------------------
    // Modports
    // ------------------------------------------------------------
    modport DRV (
        clocking cb_drv,
        output   rst_ni,
        input    clk_i
    );

    modport MON (
        clocking cb_mon,
        input    rst_ni,
        input    clk_i
    );

    modport DUT (
        input  clk_i,
        input  rst_ni,
        input  flush_i,
        input  wr_en_i,
        input  wr_data_i,
        input  rd_en_i,

        output rd_data_o,
        output rd_valid_o,
        output full_o,
        output empty_o,
        output almost_full_o,
        output almost_empty_o,
        output occupancy_o,
        output free_count_o,
        output overflow_o,
        output underflow_o,
        output overflow_sticky_o,
        output underflow_sticky_o
    );

endinterface