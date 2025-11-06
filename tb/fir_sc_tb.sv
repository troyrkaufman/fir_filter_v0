

`timescale 1ns/1ps

module fir_tb;

  // ===== Parameters (match DUT) =====
  localparam int CHANNELS   = 16;
  localparam int DW         = 16;
  localparam int TAP_COUNT  = 121;
  localparam int COEFW      = 16;
  localparam int DECIM      = 8;
  localparam int CLK_PER    = 10;   // 100 MHz

  // ===== DUT I/O =====
  logic clk;
  logic resetn;                     // active low reset in DUT is "nrst"
  logic s_tvalid;
  logic s_tready;
  logic [CHANNELS*DW-1:0] s_tdata;
  logic m_tvalid;
  logic signed [31:0]     m_tdata;

  // ===== Instantiate DUT =====
  fir #(
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

  // ===== Clock =====
  always begin clk = 1'b0; #(CLK_PER/2); clk = 1'b1; #(CLK_PER/2); end

  // ===== Reference data (globals so Vivado is happy) =====
  // Coeffs loaded with same file as DUT
  logic signed [15:0] coef  [0:TAP_COUNT-1];
  // Input sequence (post-averaging notionally; we drive all channels the same)
  logic signed [15:0] x     [0:2047];       // enough headroom
  // Expected decimated outputs
  logic signed [31:0] y_ref [0:1023];
  logic signed [47:0] debug_sample;
  
      int exp_i = 0;
      int act_i =0;
      int diff  = 0;


  // ===== Small helpers =====
  function automatic int abs_int(input int v);
    return (v < 0) ? -v : v;
  endfunction
  // Behavioral FIR reference model that accesses globals directly.
  // Computes y[n] = sum_k x[n-k] * coef[k], no bounds underflow.
  function automatic signed [31:0] fir_model_idx(input int n);
    logic signed [47:0] acc; acc = 0;
    debug_sample = 0;
    for (int k = 0; k < TAP_COUNT; k++) begin
      if (n - k >= 0) begin 
        acc += x[n - k] * coef[k];
      end  
    end
    return acc >>> 15;
  endfunction

  // ===== Output logging & compare state =====
  integer f_out;
  int     out_idx = 0;          // counts decimated outputs seen
  int debug_n;
  // ===== Reset & init =====
  initial begin
    clk      = 0;
    resetn   = 0;
    s_tvalid = 0;
    s_tdata  = '0;

    // Place fir_coe.txt in the sim working dir, or give a RELATIVE path here.
    $readmemh("fir_coe.txt", coef);
    // Simple impulse stimulus
    for (int n = 0; n < 2048; n++) begin 
      x[n] = (n == 0) ? 16'sh7FFF : 16'sd0;
      end
      
    // Precompute expected decimated outputs
    for (int n = 0; n < 1024; n++)
      y_ref[n] = fir_model_idx(n * DECIM + (DECIM - 1));

    // Open log
    f_out = $fopen("fir_output.txt", "w");
    if (f_out == 0) begin
      $display("ERROR: cannot open fir_output.txt"); $finish;
    end else begin
      $display("Opened fir_output.txt (handle %0d)", f_out);
    end

    // Release reset after some clocks
    repeat (5) @(posedge clk);
    resetn = 1;
    @(posedge clk);

    // ===== Stream the input with proper AXIS timing =====
    /*for (int n = 0; n < 1024; n++) begin
      s_tvalid <= 1'b1;
      @(posedge clk);
      // present data BEFORE the handshake edge
      //for (int ch = 0; ch < CHANNELS; ch++)
        //s_tdata[ch*DW +: DW] <= x[n];
        s_tdata[0] <= 16'h7fff;
        @(posedge clk); 
        s_tdata[0] <= 16'h0;

      while (!s_tready);
    end
    */
    s_tvalid <= 1;
    //repeat (255) begin 
    @(posedge clk);
    s_tdata[255:240] <= 16'h7fff;
    //
    //end
    @(posedge clk);
    s_tdata <= '0;
    // Deassert after last word
    @(posedge clk);
    s_tvalid <= 1'b1;
    s_tdata  <= '0;
    
    // subsequent clocks: zeros
    for (int n = 0; n < 1000; n++) begin
      s_tdata <= '0;
      @(posedge clk);
    end

    // Let the pipeline drain a bit
    repeat (100) @(posedge clk);

    $display("Simulation tail done.");
    $finish;
  end

  // ===== Capture & compare DUT outputs =====
  always_ff @(posedge clk) begin
    if (m_tvalid) begin
      $fwrite(f_out, "%0d\n", $signed(m_tdata));

      // Compare against reference
       exp_i = y_ref[out_idx];
       act_i = m_tdata;
       diff  = act_i - exp_i;
        
        //$display("Compare Samples: Expected sample: %0d; Observed sample: %0d", debug_sample, dut.samples[0]);
        
      if (abs_int(diff) > 3)
        $display("[FAIL] n=%0d exp=%0d got=%0d diff=%0d",
                 out_idx, exp_i, act_i, diff);
      else
        $display("[PASS] n=%0d exp=%0d got=%0d",
                 out_idx, exp_i, act_i);

      out_idx++;
    end
  end

  // ===== Close logs =====
  final begin
    if (f_out) $fclose(f_out);
  end

endmodule