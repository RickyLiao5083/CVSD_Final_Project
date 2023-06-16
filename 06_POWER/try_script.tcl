## PrimeTime Script
set power_enable_analysis TRUE
set power_analysis_mode time_based

read_file -format verilog  ../04_APR/ml_demodulator_pr.v
current_design ml_demodulator
link

# ===== modified to your max clock freq ===== #
create_clock -period 21.0 [get_ports i_clk]
set_propagated_clock      [get_clock i_clk]
# ===== active window ===== #
read_fsdb  -strip_path testbed/u_ml_demodulator ../05_POST/ml_demodulator.fsdb

update_power
report_power 
report_power -verbose > try_active.power

exit