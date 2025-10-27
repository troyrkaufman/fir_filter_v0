// fir.sv
// Troy Kaufman
// tkaufman@g.hmc.edu  
// 10/24/25
// Simple FIR filter that mimics decimation

// Q1.15  Range [-1,1)
// y[n] = sum of k=0 to N-1 of h[k]*x[n-k] 

`timescale 1ns/1ps

module fir #(
    parameter int TAP_COUNT   = 120,
    parameter int DATA_WIDTH  = 16,
    parameter int COEF_WIDTH  = 16,
    parameter int DECIM       = 8,
    parameter int CHANNELS    = 16
)(
    input  logic                        clk,
    input  logic                        nrst,          // active-low reset
    input  logic                        s_tvalid,
    output logic                        s_tready,
    input  logic [CHANNELS*DATA_WIDTH-1:0] s_tdata,
    output logic                        m_tvalid,
    output logic signed [31:0]          m_tdata
);

    // === Internal signals ===
    logic enable_fir;
    logic [2:0] decim_count;
    logic signed [DATA_WIDTH-1:0] samples [0:TAP_COUNT-1];
    logic signed [COEF_WIDTH-1:0] coeffs  [0:TAP_COUNT-1];
    logic signed [31:0] acc;

    // === Load coefficients ===
    initial begin
        $display("Loading coefficients...");
        $readmemh("fir_coeffs.mem", coeffs);
        for (int i = 0; i < 8; i++)
            $display("coeff[%0d] = %0d", i, coeffs[i]);
    end

    // === Ready/Valid handshake ===
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            s_tready <= 1'b0;
            enable_fir <= 1'b0;
        end else begin
            s_tready  <= 1'b1;
            enable_fir <= s_tvalid && s_tready;
        end
    end

    // === FIR tap delay line ===
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            foreach (samples[i])
                samples[i] <= '0;
        end else if (enable_fir) begin
            // shift in one new sample (we’ll just use channel 0 here)
            samples[0] <= s_tdata[15:0];  // channel 0
            for (int i = 1; i < TAP_COUNT; i++)
                samples[i] <= samples[i-1];
        end
    end

    // === Multiply-Accumulate and Decimation ===
    always_ff @(posedge clk or negedge nrst) begin
        if (!nrst) begin
            acc <= 0;
            decim_count <= 0;
            m_tvalid <= 0;
            m_tdata <= 0;
        end else if (enable_fir) begin
            // perform MAC
            acc = 0;
            for (int k = 0; k < TAP_COUNT; k++)
                acc += samples[k] * coeffs[k];

            // Decimation logic
            if (decim_count == DECIM-1) begin
                decim_count <= 0;
                m_tvalid <= 1'b1;
                m_tdata <= acc >>> 15; // scale (approx fixed-point normalization)
            end else begin
                decim_count <= decim_count + 1;
                m_tvalid <= 1'b0;
            end
        end
    end

endmodule



/*
module fir #(
    parameter TAPS = 120,                   // number of taps
    parameter DECIM = 8,                    // decimation factor
    parameter WIDTH = 16,                   // bus width
    parameter CHANNELS = 16,                // 256 bits / 16 bits = 16 channels
    parameter ACCW = 48
)(
    input logic clk,                        // system clock
    input logic nrst,                       // active low reset

    // AXIS Input
    input logic s_tvalid                    // input AXIS valid
    input logic signed [255:0] s_tdata,     // input data
    output logic s_tready,                  // output AXIS ready

    // AXIS Output
    output logic m_tvalid,                  // output AXIS valid
    output logic signed [31:0] m_tdata      // 15 bit output
);

    // obtain coefficients
    logic [WIDTH-1:0] coef [0:TAPS-1];
    initial $readmemh("fir_coe.txt", coef);

    // sample shift register per channel
    logic signed [WIDTH-1:0] sample_buf [0:CHANNELS-1][0:TAP_COUNT-1];

    logic [$clog2(DECIM)-1:0] decim_cnt;

    /////////////////
    // FIR processing
    ////////////////
    always_ff @(posedge clk) begin
        if (!nrst) begin
            s_tready  <= 1'b0;
            m_tvalid  <= 1'b0;
            decim_cnt <= '0;
            m_tdata   <= '0;

            // clear sample buffers
            foreach (sample_buf[ch, k])
                sample_buf[ch][k] <= '0;

        end else begin
            s_tready <= 1'b1;

            if (s_tvalid && s_tready) begin
                // Shift buffers for each channel
                foreach (sample_buf[ch]) begin
                    // Insert new sample at index 0
                    sample_buf[ch][0] <= s_tdata[ch*WIDTH +: WIDTH];
                    for (int k = TAP_COUNT-1; k > 0; k--)
                        sample_buf[ch][k] <= sample_buf[ch][k-1];
                end

                // Update decimation counter
                if (decim_cnt == DECIM-1)
                    decim_cnt <= '0;
                else
                    decim_cnt <= decim_cnt + 1;

                // Output new decimated sample
                if (decim_cnt == DECIM-1) begin
                    logic signed [ACCW-1:0] acc;
                    logic signed [31:0]     out_fixed;

                    acc = '0;

                    // Multiply–accumulate across channels and taps
                    foreach (sample_buf[ch, k])
                        acc += sample_buf[ch][k] * coeffs[k];

                    // Fixed-point scaling: round-to-zero (truncate 15 bits)
                    out_fixed = acc >>> 15;

                    m_tdata  <= out_fixed;
                    m_tvalid <= 1'b1;
                end else begin
                    m_tvalid <= 1'b0;
                end
            end
        end
    end


endmodule 
*/