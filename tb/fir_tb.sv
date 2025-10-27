`timescale 1ns/1ps

`timescale 1ns/1ps

module fir_tb;

    // --- parameters ---
    localparam int CHANNELS  = 16;
    localparam int DW        = 16;
    localparam int CLK_PER   = 10; // 100 MHz
    localparam int DECIM     = 8;

    // --- DUT I/O ---
    logic clk;
    logic resetn;
    logic s_tvalid;
    logic s_tready;
    logic [CHANNELS*DW-1:0] s_tdata;
    logic m_tvalid;
    logic signed [31:0] m_tdata;

    // --- Instantiate DUT ---
    fir #(
        .TAP_COUNT(120),
        .DATA_WIDTH(DW),
        .COEF_WIDTH(16),
        .DECIM(DECIM),
        .CHANNELS(CHANNELS)
    ) dut (
        .clk(clk),
        .nrst(resetn),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready),
        .s_tdata(s_tdata),
        .m_tvalid(m_tvalid),
        .m_tdata(m_tdata)
    );

    // --- Clock generation ---
    always #(CLK_PER/2) clk = ~clk;

    // --- Stimulus ---
    initial begin
        clk = 0;
        resetn = 0;
        s_tvalid = 0;
        s_tdata = '0;

        #50;
        resetn = 1;
        #20;

        // impulse on channel 0
        for (int n = 0; n < 128; n++) begin
            @(negedge clk);
            s_tvalid <= 1'b1;
            s_tdata = '0;
            s_tdata[15:0] <= (n == 0) ? 16'sd32767 : 16'sd0; // impulse
        end

        @(posedge clk);
        s_tvalid <= 0;
        s_tdata  <= 0;

        repeat (40) @(posedge clk);
        $display("\nSimulation done.");
        $finish;
    end

    // --- Monitor outputs ---
    always_ff @(posedge clk) begin
        if (m_tvalid)
            $display("[%0t ns] Decimated Output: %0d", $time, m_tdata);
    end

endmodule

/*
module tb_fir_decim_8;

    // --- parameters (same as DUT)
    localparam int CHANNELS  = 16;
    localparam int DW        = 16;
    localparam int CLK_PER   = 10;   // 100 MHz clock

    // --- DUT I/O
    logic clk;
    logic resetn;

    logic s_tvalid;
    logic s_tready;
    logic [CHANNELS*DW-1:0] s_tdata;

    logic m_tvalid;
    logic [31:0] m_tdata;

    // --- instantiate DUT
    fir_decim_8 dut (
        .clk(clk),
        .nrst(resetn),
        .s_tvalid(s_tvalid),
        .s_tready(s_tready),
        .s_tdata(s_tdata),
        .m_tvalid(m_tvalid),
        .m_tdata(m_tdata)
    );

    // --- clock generator
    always #(CLK_PER/2) clk = ~clk;

    // --- stimulus
    initial begin
        clk = 0;
        resetn = 0;
        s_tvalid = 0;
        s_tdata = '0;

        // apply reset
        #50;
        resetn = 1;

        // wait for reset release
        #20;

        // send an impulse on channel 0
        // (all zeros except one sample = 1.0 -> 32767)
        for (int n = 0; n < 64; n++) begin
            @(posedge clk);

            s_tvalid <= 1'b1;

            // zero all channels
            s_tdata = '0;

            // create an impulse at n=0 on channel 0
            if (n == 0)
                s_tdata[15:0] = 16'sd32767;
            else
                s_tdata[15:0] = 16'sd0;

            // if your DUT has handshake logic, wait for ready
            wait (s_tready);
        end

        // stop stimulus
        @(posedge clk);
        s_tvalid <= 0;
        s_tdata  <= 0;

        // let simulation run a bit longer
        repeat (30) @(posedge clk);

        $display("\nSimulation done.");
        $finish;
    end

    // --- monitor outputs
    always_ff @(posedge clk) begin
        if (m_tvalid)
            $display("[%0t ns] Output: %0d", $time, m_tdata);
    end

endmodule
*/