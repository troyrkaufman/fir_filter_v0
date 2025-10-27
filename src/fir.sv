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
        $readmemh("fir_coe.txt", coeffs);
//        for (int i = 0; i < 8; i++)
//            $display("coeff[%0d] = %0d", i, coeffs[i]);
    end 


    // === Ready/Valid handshake ===
    always_ff @(posedge clk) begin
        if (!nrst) begin
            s_tready <= 1'b0;
            enable_fir <= 1'b0;
        end else begin
            s_tready  <= 1'b1;
            enable_fir <= s_tvalid && s_tready;
        end
    end
    
    // --- unpack and average all channel lanes ---
        logic signed [DATA_WIDTH-1:0] ch [CHANNELS];
        logic signed [DATA_WIDTH+4:0] ch_sum;  // +4 bits for 16-lane sum
        //assign ch_sum = '0;

    // === FIR tap delay line (averages all 16 channels) ===
always_ff @(posedge clk) begin
    if (!nrst) begin
        foreach (samples[i])
            samples[i] <= '0;
        ch_sum <= '0;
    end else if (enable_fir) begin
        // unpack each 16-bit slice and sum
        for (int c = 0; c < CHANNELS; c++) begin
            ch[c] = $signed(s_tdata[c*DATA_WIDTH +: DATA_WIDTH]);
            ch_sum += ch[c];
        end

        // divide by 16 (shift right by 4) to keep Q1.15 scaling
        samples[0] <= ch_sum >>> 4;

        // shift previous samples down the delay line
        for (int i = 1; i < TAP_COUNT; i++)
            samples[i] <= samples[i-1];
    end
end

    // === Multiply-Accumulate and Decimation ===
    always_ff @(posedge clk) begin
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