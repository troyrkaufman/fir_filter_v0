`timescale 1ns/1ps

module fir_tb;

  // ===== Parameters (match DUT) =====
  localparam int CHANNELS   = 2;
  localparam int DW         = 16;
  localparam int TAP_COUNT  = 120;
  localparam int COEFW      = 16;
  localparam int DECIM      = 8;
  localparam int PSAMPLES   = 8;
  localparam int CLK_PER    = 3;   // 100 MHz

  // ===== DUT I/O =====
  logic clk;
  logic resetn;                     // active low reset in DUT is "nrst"
  logic s_tvalid;
  logic s_tready;
  logic [CHANNELS*DW*PSAMPLES-1:0] s_tdata;
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
  
  task impulse();
    @(posedge clk);
    s_tvalid <= 1;
    wait(s_tready);
    @(posedge clk);
    s_tdata[255:240] <= 16'h7fff;
    @(posedge clk);
    s_tdata <= '0;
    repeat (500) @(posedge clk);
    s_tvalid <= 0;
  endtask
  
  task step();
    @(posedge clk);
    s_tvalid <= 1;
    @(posedge clk);
    wait(s_tready);
    for(int i=0;i<'d527;i++)
        s_tdata[255:240] <= (i < 16) ? '0 : 16'sh7fff;
    repeat (500) @(posedge clk);
    s_tvalid <= 0;
    s_tdata <= '0;
  endtask
  
  task sinusoid(
      input real ch_freq,
      input real fs_hz,
      input real amp,
      input int num_frames);
    
    static real two_pi = 6.28318530718;
    int frame, i;
    logic signed [15:0] lane_A [0:7];
    logic signed [15:0] lane_B [0:7];

    $display("=== Sending sinusoidal input: fA and fB=%0.2f Hz, frames=%0d ===",
             ch_freq, num_frames);

    s_tvalid <= 1;

    for (frame = 0; frame < num_frames; frame++) begin
        // Fill 8 samples per channel
        for (i = 0; i < 8; i++) begin
            automatic real t = (frame * 8 + i) / fs_hz;

            lane_A[i] = $rtoi(amp * $sin(two_pi * ch_freq * t) * 32767.0);
            lane_B[i] = $rtoi(amp * $sin(two_pi * ch_freq * t) * 32767.0);

            // Optionally store for reference model if desired:
            x[frame * 8 + i] = lane_A[i];
        end

        // Pack Channel B (upper 128 bits) and Channel A (lower 128 bits)
        s_tdata = {
            lane_B[7], lane_B[6], lane_B[5], lane_B[4],
            lane_B[3], lane_B[2], lane_B[1], lane_B[0],
            lane_A[7], lane_A[6], lane_A[5], lane_A[4],
            lane_A[3], lane_A[2], lane_A[1], lane_A[0]
        };

        @(posedge clk);
    end

    s_tvalid <= 0;
    s_tdata  <= '0;

    $display("=== Finished sending sine input ===");  
  endtask
  
  // ===== Reset & init =====
  initial begin
    clk      = 0;
    resetn   = 0;
    s_tvalid = 0;
    s_tdata  = 256'h0;

    // Place fir_coe.txt in the sim working dir, or give a RELATIVE path here.
    $readmemh("fir_coe.txt", coef);
    /*
    // Simple impulse stimulus
    for (int n = 0; n < 2048; n++) begin 
      x[n] = (n == 0) ? 16'sh7FFF : 16'sd0;
      end
      
    // Precompute expected decimated outputs
    for (int n = 0; n < 1024; n++)
      y_ref[n] = fir_model_idx(n * DECIM + (DECIM - 1) - 8);
    */
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
    impulse();
    @(posedge clk);
    step();
    @(posedge clk);
    sinusoid(1000.0, 100000.0, 0.8, 128); //input channel freq, sample freq, amp, num frames
    
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
     /*           
      if (abs_int(diff) > 3)
        $display("[FAIL] n=%0d exp=%0d got=%0d diff=%0d",
                 out_idx, exp_i, act_i, diff);
      else
        $display("[PASS] n=%0d exp=%0d got=%0d",
                 out_idx, exp_i, act_i);
*/
      out_idx++;
    end
  end

  // ===== Close logs =====
  final begin
    if (f_out) $fclose(f_out);
  end

endmodule