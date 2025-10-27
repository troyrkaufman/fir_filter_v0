# Verification Process

## fir_tb.sv

I stimulated the zeroth channel with 16'7fff and checked the corresponding output and it was the 
coefficient as expected.

## fir_sc_tb.sv (Self Checking)

I was able to get the phase and magnitude somewhat the same as observed in my outputs:

`
[FAIL] n=0 exp=352 got=251 diff=-101
[FAIL] n=1 exp=642 got=752 diff=110
[FAIL] n=2 exp=-1248 got=-1076 diff=172
[FAIL] n=3 exp=-146 got=-450 diff=-304
[FAIL] n=4 exp=785 got=1619 diff=834
[FAIL] n=5 exp=-4712 got=-4782 diff=-70
[FAIL] n=6 exp=-924 got=-1214 diff=-290
[FAIL] n=7 exp=-661 got=-440 diff=221
[FAIL] n=8 exp=-4342 got=-3752 diff=590
[FAIL] n=9 exp=-8 got=-1022 diff=-1014
[FAIL] n=10 exp=1440 got=1923 diff=483
`

These differences might seem large, however, we must consider that this is on a 16 bit scale
with differences ranging from the low hundreds to just over a thousand. This means that there is 
error range of 0.1 to 1.5%.