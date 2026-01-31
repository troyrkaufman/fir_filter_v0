// ============================================================================
// FIR Filter Testbench (Dual Channel, Decimation by 8)
// Author: Troy Kaufman
// Date: 11/07/2025
// ----------------------------------------------------------------------------
// Tests a 2 channel 8 lane 16 bit input decimation by 8 FIR filter. Inputs 
// include impulses, steps, and sinusoids. A behavioral model was created to 
// test the design against using the same inputs. 
// ============================================================================

`timescale 1ns/1ps

module fir_tb;

	// Parameters (match DUT)
	localparam int CHANNELS   = 2;
	localparam int DW         = 16;
	localparam int TAP_COUNT  = 120;
	localparam int COEFW      = 16;
	localparam int DECIM      = 8;
	localparam int PSAMPLES   = 8;
	localparam int CLK_PER    = 10;   // 100 MHz
	
	// Parameters for CORDIC
	localparam CORDIC_CLK_PERIOD = 2;
	localparam signed [15:0] PI_POS = 16'h6488;
	localparam signed [15:0] PI_NEG = 16'h9878;
	localparam PHASE_INC_2MHz = 200;   // phase jump for 30MHz sine 
	localparam PHASE_INC_30MHz = 3000; // phase jump for 30MHz sine wave
	
	// internal variables for CORDIC
	logic cordic_clk = 1'b0;
	logic phase_tvalid = 1'b0;
	logic signed [15:0] phase_2MHz = 0;
	logic signed [15:0] phase_30MHz = 0;
	logic sincos_2MHz_tvalid;
	logic sincos_30MHz_tvalid;
	logic signed [15:0] sin_2MHz, cos_2MHz;
	logic signed [15:0] sin_30MHz, cos_30MHz;
	
	logic signed [15:0] noisy_signal = 0;
	logic signed [15:0] filtered_signal;
	

	// DUT I/O
	logic clk;
	logic resetn;                     // active low reset in DUT is "nrst"
	logic s_tvalid;
	logic s_tready;
	logic [CHANNELS*DW*PSAMPLES-1:0] s_tdata;
	logic m_tvalid;
	logic signed [31:0]     m_tdata;
	logic signed               xil_s_tdata;
	logic signed [31:0]     xil_m_tdata;
	
	// Queues
	logic [15:0] expected_outputs [$];
	logic [15:0] outputs [$];

	// Instantiate DUT
	fir_troy #(
		.TAP_COUNT (TAP_COUNT),
		.DATA_WIDTH(DW),
		.COEF_WIDTH(COEFW),
		.DECIM     (DECIM),
		.CHANNELS  (CHANNELS)
	) dut (
		.clk      (clk),
		.nrst     (resetn),
		.s_tvalid (s_tvalid),
		.s_tready (s_tready),
		.s_tdata  (s_tdata),
		.m_tvalid (m_tvalid),
		.m_tdata  (m_tdata)
	);
	
	// create a 30 MHz sine wave
	cordic_0 cordic_inst_0(
	   .aclk                   (cordic_clk),
	   .s_axis_phase_tvalid    (phase_tvalid),
	   .s_axis_phase_tdata     (phase_30MHz),
	   .m_axis_dout_tvalid     (sinccos_30MHz_tvalid),
	   .m_axis_dout_tdata      ({sin_30MHz, cos_30MHz})
	);
	
	
	cordic_0 cordic_inst_1(
           .aclk                   (cordic_clk),
           .s_axis_phase_tvalid    (phase_tvalid),
           .s_axis_phase_tdata     (phase_2MHz),
           .m_axis_dout_tvalid     (sinccos_2MHz_tvalid),
           .m_axis_dout_tdata      ({sin_2MHz, cos_2MHz})
        );
	
	// Instantiate Xilinx FIR Compiler
	fir_compiler_0 fir_xil(
	       .aclk(clk), 
	       .aresetn(resetn), 
	       .s_axis_data_tvalid(s_tvalid),
	       .s_axis_data_tready(xil_s_tready),
	       .s_axis_data_tdata(s_tdata),
	       .m_axis_data_tvalid(xil_m_tvalid),
	       .m_axis_data_tdata(xil_m_tdata)
	);

	// Clock
	always begin clk = 1'b0; #(CLK_PER/2); clk = 1'b1; #(CLK_PER/2); end

	// Coeffs loaded with same file as DUT
	logic signed [15:0] coef  [0:TAP_COUNT-1];
	// Input sequence (post-averaging notionally; we drive all channels the same)
	logic signed [15:0] x     [0:2047];       // enough headroom
	
	
	task impulse();
		@(posedge clk);
		s_tvalid <= 1;
		wait(s_tready);
		@(posedge clk);
		s_tdata[255:240] <= 16'h7fff;
		s_tdata[15:0] <= 16'h7fff;
		@(posedge clk);
		s_tdata <= '0;
		s_tvalid <= 0;
	
	endtask
	
	task step();
		@(posedge clk);
		s_tvalid <= 1;
		@(posedge clk);
		wait(s_tready);
		for(int i=0;i<'d527;i++)
			s_tdata[255:240] <= (i < 16) ? '0 : 16'sh7fff;
		@(posedge clk);
		s_tdata <= '0;
		//repeat (500) @(posedge clk);
		s_tvalid <= 0;
	endtask
	
	// phase sweep
	always @ (posedge cordic_clk)
	   begin
	       phase_tvalid <= 1'b1;
	       
	       // sweep phase to execute 2MHz sine
	       if (phase_2MHz + PHASE_INC_2MHz < PI_POS) begin
	           phase_2MHz <= phase_2MHz + PHASE_INC_2MHz;
	       end else begin 
	           phase_2MHz <= PI_NEG + (phase_2MHz + PHASE_INC_2MHz - PI_POS);
	       end
	       
	       // sweep phase to execute 30MHz sine
	       if (phase_30MHz + PHASE_INC_30MHz < PI_POS) begin
               phase_30MHz <= phase_30MHz + PHASE_INC_30MHz;
           end else begin 
               phase_30MHz <= PI_NEG + (phase_30MHz + PHASE_INC_30MHz - PI_POS);
           end
	       
	   end
	   
	 // create 500 MHz Cordic clock
	   always begin 
	       cordic_clk = #(CORDIC_CLK_PERIOD/2) ~cordic_clk;
	   end
	   
	// sinudoid table
	task sinusoid();
	   begin 
	       @(posedge clk);
           s_tvalid <= 1;
           @(posedge clk);
           wait(s_tready);
           @(posedge clk);
           for (int i = 0; i < 51; i++) begin 
            @(posedge clk);
            s_tdata[255:240] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[239:224] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[223:208] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[207:192] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[191:176] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[175:160] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[159:144] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[143:128] = (sin_2MHz + sin_30MHz) / 2;
            
            s_tdata[127:112] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[111:96] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[95:80] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[79:64] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[63:49] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[48:33] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[32:16] = (sin_2MHz + sin_30MHz) / 2;
            s_tdata[15:0] = (sin_2MHz + sin_30MHz) / 2;
           end
           @(posedge clk);
           s_tdata <= '0;
           s_tvalid <= 0;   
	   end
	endtask
	
	// Reset & init
	initial begin
		clk      = 0;
		resetn   = 0;
		s_tvalid = 0;
		s_tdata  = 256'h0;

		$readmemh("fir_coe.txt", coef);

		// Release reset after some clocks
		repeat (5) @(posedge clk);
		resetn = 1;
		
		// send an impulse
		//impulse();
		//repeat (25) @(posedge clk);

		// send an input step
		//step();
		@(posedge clk);

		// send a sinusoid
		sinusoid();
		@(posedge clk);
		//wait(!xil_s_tready);

		$display("Simulation done.");
		$finish;
	end


endmodule