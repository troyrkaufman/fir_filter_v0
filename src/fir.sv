
// ============================================================================
// FIR Filter (Dual Channel, Decimation by 8)
// Author: Troy Kaufman
// Date: 11/05/2025
// ----------------------------------------------------------------------------
// Implements a 2-channel FIR filter with 8 parallel input samples per channel.
// Each channel has its own 121-tap delay line. The filter coefficients are
// shared between both channels. Output is decimated by 8.
// ============================================================================

`timescale 1ns/1ps

module fir #(
    parameter int TAP_COUNT   = 121,   // Number of taps
    parameter int DATA_WIDTH  = 16,    // Input sample width
    parameter int COEF_WIDTH  = 16,    // Coefficient width
    parameter int DECIM       = 8,     // Decimation rate
    parameter int CHANNELS    = 2,     // Dual-channel input
    parameter int P_SAMPLES   = 8      // Parallel samples per channel
)(
    input  logic                        clk,
    input  logic                        nrst,          // Active-low reset
    input  logic                        s_tvalid,
    output logic                        s_tready,
    input  logic [CHANNELS*P_SAMPLES*DATA_WIDTH-1:0] s_tdata,
    output logic                        m_tvalid,
    output logic signed [31:0]          m_tdata        // combined output (CH0+CH1)
);

    // Internal Signals
    logic enable_fir;
    logic pos_enable_fir, delay0;
    logic [2:0] decim_count;

    // Delay lines for each channel
    logic signed [DATA_WIDTH-1:0] taps0 [0:TAP_COUNT-1];
    logic signed [DATA_WIDTH-1:0] taps1 [0:TAP_COUNT-1];

    // Shared coefficient memory
    logic signed [COEF_WIDTH-1:0] coeffs [0:TAP_COUNT-1];

    // Accumulators
    logic signed [47:0] acc0, acc1;

    // Load coefficients from file
    initial begin
        $display("Loading FIR coefficients...");
        $readmemh("fir_coe.txt", coeffs);
    end

    // Ready/Valid handshake
    always_ff @(posedge clk) begin
        if (!nrst) begin
            s_tready   <= 1'b0;
            enable_fir <= 1'b0;
        end else begin
            s_tready   <= 1'b1;
            enable_fir <= s_tvalid && s_tready;
        end
    end
    logic delay1;
    // Detect rising edge of enable_fir
    always_ff @(posedge clk) begin
        if (!nrst) begin
            delay0 <= 0;
            delay1 <= 0;
        end else begin
            delay0 <= enable_fir;
            delay1 <= delay0;
    end
    end

    assign pos_enable_fir = delay0 && !delay1;

    // Delay line shift and load
    always_ff @(posedge clk) begin
        if (!nrst) begin
            for (int i = 0; i < TAP_COUNT; i++) begin
                taps0[i] <= '0;
                taps1[i] <= '0;
            end
        end
        else if (enable_fir) begin
            for (int i = TAP_COUNT-1; i >= 1; i--) begin
                taps0[i] <= taps0[i - P_SAMPLES];
                taps1[i] <= taps1[i - P_SAMPLES];
            end

            // Load new parallel samples
            for (int j = 0; j < P_SAMPLES; j++) begin
                taps0[j] <= $signed(s_tdata[16*j +: 16]);
                taps1[j] <= $signed(s_tdata[(P_SAMPLES*DATA_WIDTH) + 16*j +: 16]);
            end
    end
    end

    logic signed [47:0] temp_acc0 = 0;
    logic signed [47:0] temp_acc1 = 0;

    logic signed [32:0] debug_mult;
    
    // Multiply-Accumulate (MAC) and Decimation
    always_ff @(posedge clk) begin
        if (!nrst) begin
            acc0        <= '0;
            acc1        <= '0;
            decim_count <= '0;
            m_tvalid    <= 1'b0;
            m_tdata     <= '0;
            debug_mult <= 0;
        end 
        else if (enable_fir) begin
            temp_acc0 = '0;
            temp_acc1 = '0;
            for (int k = 0; k < TAP_COUNT; k++) begin
                temp_acc0 = temp_acc0 + ($signed(taps0[k]) * $signed(coeffs[k]));
                temp_acc1 = temp_acc1 + ($signed(taps1[k]) * $signed(coeffs[k]));
            end

            m_tvalid <= 1;
            m_tdata <= $signed(temp_acc0 >>> 15) + $signed(temp_acc1 >>> 15);
       end else 
            m_tvalid <= 0;
    end
endmodule