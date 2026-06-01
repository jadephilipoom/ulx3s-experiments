.PHONY: all clean

clean:
	rm -f abc.history top.json ulx3s.config ulx3s.bit

top.json: top.ys top.v
	yosys top.ys 

ulx3s.config: top.json
	nextpnr-ecp5 --85k --json top.json --lpf ulx3s_v20.lpf --textcfg ulx3s.config 

ulx3s.bit: ulx3s.config
	ecppack ulx3s.config ulx3s.bit

prog: ulx3s.bit
	fujprog ulx3s.bit
