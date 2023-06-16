set_clock_latency -source -early -max -rise  -0.824711 [get_ports {i_clk}] -clock i_clk 
set_clock_latency -source -early -max -fall  -0.866322 [get_ports {i_clk}] -clock i_clk 
set_clock_latency -source -late -max -rise  -0.824711 [get_ports {i_clk}] -clock i_clk 
set_clock_latency -source -late -max -fall  -0.866322 [get_ports {i_clk}] -clock i_clk 
