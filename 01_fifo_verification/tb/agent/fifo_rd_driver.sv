// Read agent. Mirror of the write agent -- see fifo_wr_driver.sv for why
// the semaphore is required.
class fifo_rd_driver #(parameter int unsigned DATA_WIDTH = 8,
                       parameter int unsigned DEPTH      = 4);

    virtual fifo_if #(DATA_WIDTH, DEPTH) vif;
    semaphore                            bus_sem;
    int                                  n_reads;
    int                                  drive_count;
    event                                done;

    function new(virtual fifo_if #(DATA_WIDTH, DEPTH) vif,
                 semaphore                            bus_sem,
                 int                                  n_reads);
        this.vif     = vif;
        this.bus_sem = bus_sem;
        this.n_reads = n_reads;
    endfunction

    task automatic run();
        repeat (n_reads) begin
            bus_sem.get(1);
            vif.cb_drv.rd_en_i <= 1'b1;
            @(vif.cb_drv);
            vif.cb_drv.rd_en_i <= 1'b0;
            bus_sem.put(1);
            drive_count++;
        end
        -> done;
    endtask

endclass