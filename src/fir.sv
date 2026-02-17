
// ============================================================================
// FIR Filter (Dual Path, Decimation by 8)
// Author: Troy Kaufman
// Date: 11/05/2025
// ----------------------------------------------------------------------------
// Implements a 2-path FIR filter with 8 parallel input samples per path.
// Each path has its own 121-tap delay line. The filter coefficients are
// shared between both channels. Output is decimated by 8.
// ============================================================================

`timescale 1ns/1ps

module fir #(
    parameter int TAP_COUNT   = 121,   // Number of taps
    parameter int DATA_WIDTH  = 16,    // Input sample width
    parameter int COEF_WIDTH  = 16,    // Coefficient width
    parameter int DECIM       = 8,     // Decimation rate
    parameter int CHANNELS    = 2,     // Dual-path input
    parameter int P_SAMPLES   = 8      // Parallel samples per path
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
    logic signed [47:0] temp_acc0 = 0;
    logic signed [47:0] temp_acc1 = 0;
    logic signed [31:0] t_data_next;
    logic signed [15:0] acc0;
    logic signed [31:0] acc1;
    
    logic m_tvalid_next;

    // Delay lines for each path
    logic signed [DATA_WIDTH-1:0] taps0 [0:TAP_COUNT-1];
    logic signed [DATA_WIDTH-1:0] taps1 [0:TAP_COUNT-1];

    // Shared coefficient memory
    logic signed [COEF_WIDTH-1:0] coeffs [0:TAP_COUNT-1];

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

    // Delay line shift and load
    always_ff @(posedge clk) begin
        if (!nrst) begin
            for (int i = 0; i < TAP_COUNT; i++) begin
                taps0[i] <= '0;
                taps1[i] <= '0;
            end
        end
        else if (enable_fir) begin
            for (int i = TAP_COUNT-1; i >= P_SAMPLES; i--) begin
                    taps0[i] <= $signed(taps0[i-P_SAMPLES]);
                    taps1[i] <= $signed(taps1[i-P_SAMPLES]);
            end 
            for (int j = P_SAMPLES-1; j >= 0; j--) begin
                taps0[j] <= $signed(s_tdata[(j*DATA_WIDTH) +: DATA_WIDTH]);
                taps1[j] <= $signed(s_tdata[(j*DATA_WIDTH + 'd128) +: DATA_WIDTH]);
            end
    end
    end
    
    // MAC and Normalization Logic
    always_comb begin
        if (!nrst) begin
            acc0            = '0;
            acc1            = '0;
            m_tvalid_next   = 1'b0;
            m_tdata         = '0;
            t_data_next     = 0;
        end 
        else if (enable_fir) begin 
            temp_acc0       = '0;
            temp_acc1       = '0;
            for (int k = 0; k < TAP_COUNT; k++) begin
                temp_acc0 = $signed(temp_acc0) + ($signed(taps0[k]) * $signed(coeffs[k]));
                temp_acc1 = $signed(temp_acc1) + ($signed(taps1[k]) * $signed(coeffs[k]));
            end
            acc0            = temp_acc0>>>19;
            acc1            = (temp_acc1>>>19)<<16;
            t_data_next     = {acc1[31:16], acc0}; 
            m_tvalid_next   = 1;
       end else 
            m_tvalid_next   = 0;
    end
    
    logic [31:0] delay_tdata [0:65];
    logic [65:0] delay_tvalid;
    
    // Shift registers to match Xilinx's FIR Compiler delay
    always_ff@(posedge clk) begin
        if (!nrst) begin
            for (int i = 0; i < 66; i++) begin
                delay_tdata[i] <= '0;
            end
            delay_tvalid <= '0;
        end else begin
            for(int i = 0; i < 'd65; i++) begin 
                delay_tdata[i+1] <= delay_tdata[i];
            end
            
            delay_tdata[0] <= t_data_next;       
            delay_tvalid <= {m_tvalid_next, delay_tvalid[65:1]};
        end
    end
    
    // AXIS valid flag output
    assign m_tvalid = delay_tvalid[0];
    
    // AXIS data output
    always_ff@(posedge clk) begin 
        if (!nrst) begin
            m_tdata <= '0;
        end else if (m_tvalid && (delay_tvalid[1] && delay_tvalid[0])) begin // ensures the final output is consistent with Xilinx's implementation
            m_tdata <= delay_tdata[65];
        end
    
    end
    
endmodule