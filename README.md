# Decimation by 8 FIR filter

## Progress Update

* The custom behavioral FIR filter displays a similar behavior to the FIR Compiler's output the model is meant to replace. 

* The testbench attached uses impulse, step, and sinusoidal inputs to stimulate the design. 

* In all tests, the average difference between the behavioral model and the Xilinx implementation is 2-3 signed decimal values out of 2^16 possibilites. 