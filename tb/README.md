# FIR Filter Notes

The custom behavioral FIR filter behaves similarly to Xilinx's FIR Compiler. It is synthesizable but will not close timing. A shift register was used to start producing outputs to align with Xilinx's FIR Compiler. 

The majority of the data averages between 2-3 signed decimals away from the golden reference model's output. The maximum output difference found between both models has been observed to be a 7 signed decimal value away. 