`timescale 1ns/1ps
`define CYCLE       22.0     // CLK period, modify by yourself
`define HCYCLE      (`CYCLE/2)
`define MAX_CYCLE   1_000_000
`define RST_DELAY   2

`ifdef tb1
    `define PAT_R	"../00_TESTBED/PATTERN/packet1/SNR10dB_pat_r.dat"
    `define PAT_Y	"../00_TESTBED/PATTERN/packet1/SNR10dB_pat_y_hat.dat"
    `define HardB	"../00_TESTBED/PATTERN/packet1/SNR10dB_hb.dat"
	`define LLR		"../00_TESTBED/PATTERN/packet1/SNR10dB_llr.dat"
	`define threshold 120
`elsif tb2
    `define PAT_R	"../00_TESTBED/PATTERN/packet2/SNR10dB_pat_r.dat"
    `define PAT_Y	"../00_TESTBED/PATTERN/packet2/SNR10dB_pat_y_hat.dat"
    `define HardB	"../00_TESTBED/PATTERN/packet2/SNR10dB_hb.dat"
	`define LLR		"../00_TESTBED/PATTERN/packet2/SNR10dB_llr.dat"
	`define threshold 120
`elsif tb3
    `define PAT_R	"../00_TESTBED/PATTERN/packet3/SNR10dB_pat_r.dat"
    `define PAT_Y	"../00_TESTBED/PATTERN/packet3/SNR10dB_pat_y_hat.dat"
    `define HardB	"../00_TESTBED/PATTERN/packet3/SNR10dB_hb.dat"
	`define LLR		"../00_TESTBED/PATTERN/packet3/SNR10dB_llr.dat"
	`define threshold 120
`elsif tb4
    `define PAT_R	"../00_TESTBED/PATTERN/packet4/SNR15dB_pat_r.dat"
    `define PAT_Y	"../00_TESTBED/PATTERN/packet4/SNR15dB_pat_y_hat.dat"
    `define HardB	"../00_TESTBED/PATTERN/packet4/SNR15dB_hb.dat"
	`define LLR		"../00_TESTBED/PATTERN/packet4/SNR15dB_llr.dat"
	`define threshold 10
`elsif tb5
    `define PAT_R	"../00_TESTBED/PATTERN/packet5/SNR15dB_pat_r.dat"
    `define PAT_Y	"../00_TESTBED/PATTERN/packet5/SNR15dB_pat_y_hat.dat"
    `define HardB	"../00_TESTBED/PATTERN/packet5/SNR15dB_hb.dat"
	`define LLR		"../00_TESTBED/PATTERN/packet5/SNR15dB_llr.dat"
	`define threshold 10
`elsif tb6
    `define PAT_R	"../00_TESTBED/PATTERN/packet6/SNR15dB_pat_r.dat"
    `define PAT_Y	"../00_TESTBED/PATTERN/packet6/SNR15dB_pat_y_hat.dat"
    `define HardB	"../00_TESTBED/PATTERN/packet6/SNR15dB_hb.dat"
	`define LLR		"../00_TESTBED/PATTERN/packet6/SNR15dB_llr.dat"
	`define threshold 10
`else
    `define PAT_R	"../00_TESTBED/PATTERN/packet1/SNR10dB_pat_r.dat"
    `define PAT_Y	"../00_TESTBED/PATTERN/packet1/SNR10dB_pat_y_hat.dat"
    `define HardB	"../00_TESTBED/PATTERN/packet1/SNR10dB_hb.dat"
	`define LLR		"../00_TESTBED/PATTERN/packet1/SNR10dB_llr.dat"
	`define threshold 120
`endif

// Rename it to Your SDF file, same operation for .f file
`ifdef GSIM
	`define SDFFILE "ml_demodulator_syn.sdf"  // Modify your sdf file name
`elsif POST
	`define SDFFILE "ml_demodulator_pr.sdf"  // Modify your sdf file name
`endif

module testbed;
	// Parameters
    // localparam A  = 0;

    // Ch1, define port and reg
	// For I/O
    reg				i_clk;
    reg				i_reset;
    reg				i_trig;
    reg [159:0]		i_y_hat;
    reg [319:0]		i_r;
    reg				i_rd_rdy;
    wire			o_rd_vld;
    wire [7:0]		o_llr;
    wire			o_hard_bit;

	// For Golden&Pattern
	reg  [319:0] PAT_R_mem		[0:999];	// Feed in SRAM
	reg  [159:0] PAT_Y_mem		[0:999];	// op_mode, 1024 items
	reg  [7:0]   LLR_mem		[0:7999];	// correct output, 4096 items
	reg  		 HardBit_mem 	[0:7999];	// for cmp

	`ifdef debug
		integer	debug	=1;
	`else
		integer	debug	=0;
	`endif

	reg warning;

	real	D0, D1;
    // Ch2, Instantiation
	ml_demodulator u_ml_demodulator (
		.i_clk		(i_clk),
		.i_reset	(i_reset),
		.i_trig		(i_trig),
		.i_y_hat	(i_y_hat),
		.i_r		(i_r),
		.i_rd_rdy	(i_rd_rdy),
		.o_rd_vld	(o_rd_vld),
		.o_llr		(o_llr),
		.o_hard_bit	(o_hard_bit)
	);

    // Ch3, clk
	initial i_clk = 1'b0;
	always begin #(`HCYCLE) i_clk = ~i_clk; end

    // Write out wavgform file
    initial begin
		`ifdef VCD
			$dumpfile("ml_demodulator.vcd");
			$dumpvars;
		`endif
        `ifdef FSDB
            `ifdef SYN
                $fsdbDumpfile("ml_demodulator_syn.fsdb");
            `elsif APR
                $fsdbDumpfile("ml_demodulator.fsdb");
            `else
                $fsdbDumpfile("ml_demodulator.fsdb");
            `endif
            //$fsdbDumpvars(0, "+mda");
            $fsdbDumpvars;
			$fsdbDumpMDA;
        `endif
    end

	initial begin
		`ifndef SDF
			`ifdef tb1
				$fsdbDumpfile("ml_demodulator_p1.fsdb");
			`elsif tb2
				$fsdbDumpfile("ml_demodulator_p2.fsdb");
			`elsif tb3
				$fsdbDumpfile("ml_demodulator_p3.fsdb");
			`elsif tb4
				$fsdbDumpfile("ml_demodulator_p4.fsdb");
			`elsif tb5
				$fsdbDumpfile("ml_demodulator_p5.fsdb");
			`else
				$fsdbDumpfile("ml_demodulator_p6.fsdb");
			`endif
			$fsdbDumpvars(0, "+mda");
			$fsdbDumpvars;
		`endif
	end

	// For gate-level simulation only
	`ifdef SDF
		initial $sdf_annotate(`SDFFILE, u_ml_demodulator);
		initial #1 $display("SDF File %s were used for this simulation.", `SDFFILE);
		//initial warning = 0;
		initial warning = 1;
	`else
		initial warning = 1;
	`endif

    // Ch4, Flush op_mode then Feed pattern into reg
	initial begin
		$readmemh(`PAT_R, 	PAT_R_mem);		// readmemh 不是 readmemb
		$readmemh(`PAT_Y,	PAT_Y_mem);
		$readmemh(`LLR,		LLR_mem);
		$readmemb(`HardB, 	HardBit_mem);
	end
	
	// Ch5, reset and end-control
	integer				rst_finish;
	initial begin
		// $display("Reseting!");
		rst_finish      = 0;
		# (               0.25 * `CYCLE)	i_reset = 1;
		# ((`RST_DELAY - 0.25) * `CYCLE)	i_reset	= 0; rst_finish	= 1;
		# (         `MAX_CYCLE * `CYCLE);
		$write("%c[7;31m",27);
		$display("Error! Runtime exceeded!");
		$write("%c[0m",27);
		$finish;
	end

    // Ch6, compare result
	integer				T_cycle;
    integer				input_pter;		// 輸入資料的 Index
	integer				output_pter;	// 輸出資料的 Index
	integer				Has_Accept;
	integer				error;
	integer				seed;
	integer             count1RE;
	integer             err_flag;

    initial begin
		T_cycle			= -1;
		input_pter		= 0;
		output_pter		= 0;
		Has_Accept		= 0;
		error			= 0;
		i_trig			= 0;
		count1RE        = 0;
		err_flag        = 0;

		wait(rst_finish);
        while ( output_pter<8000 ) begin
		// while ( output_pter<8 ) begin
			@(posedge i_clk);
			// 資料餵入
			`ifndef debug
				# 1;
			`endif

			if ( T_cycle > 64*999 )begin
				i_trig		= 1'b0;
			end else if ( (T_cycle+1)%64 == 0 ) begin // originally is (T_cycle%64 == 63)
				i_trig		= 1'b1;
				i_y_hat		= PAT_Y_mem[input_pter];
				i_r			= PAT_R_mem[input_pter];
				input_pter	= input_pter + 1;
			end else begin
				i_trig		= 1'b0;
			end

			// 資料讀取
			`ifndef debug
				# (`CYCLE-2);
			`endif
			if ( T_cycle%640 == 0 ) begin
				Has_Accept	= 0;
			end
			if ( (639-(T_cycle%640))==(128 - Has_Accept) ) begin	// 如果剩餘回合數=還沒立起的周期數
				i_rd_rdy	= 1'b1;
				if ( o_rd_vld ) begin
					if ( o_hard_bit !== HardBit_mem[output_pter] ) begin
						error	= error + 1;
						$write("%c[7;31m",27);
						$display("ERROR: at HB [#%d] your Hard Bit=%b, golden=%b", 
								output_pter, o_hard_bit, HardBit_mem[output_pter]);
						$display("In the meanwhile, your LLR=%h, golden=%h",
								o_llr, LLR_mem[output_pter]);
						$write("%c[0m",27);
					end else if ( o_llr == 0 ) begin
						error	= error + 1;
						$write("%c[7;31m",27);
						$display("ERROR: at LLR [#%d] your LLR is zero", 
								output_pter, o_llr, LLR_mem[output_pter]);
						$write("%c[0m",27);
					end
					if(warning) begin
						if ( o_llr !== LLR_mem[output_pter] ) begin
							$write("%c[1;31m",27);
							if (debug) begin
								D0		= $signed( o_llr );
								D1		= $signed( LLR_mem[output_pter] );
								$display("Warning: at LLR [#%d] your LLR=%f, golden=%f",
									output_pter, D0/(2**4), D1/(2**4));
							end else begin
								$display("Warning: at LLR [#%d] your LLR=%h, golden=%h", 
									output_pter, o_llr, LLR_mem[output_pter]);
							end
							$write("%c[0m",27);
						end
					end
					output_pter		= output_pter + 1;
					Has_Accept		= Has_Accept + 1;
				end
			end else if ( Has_Accept == 128 ) begin	// 如果本輪已經立起128T
				i_rd_rdy	= 1'b0;
			end else if ( $dist_uniform(seed, 0, 4) == 0 ) begin
				i_rd_rdy	= 1'b1;
				if ( o_rd_vld ) begin
					if ( o_hard_bit !== HardBit_mem[output_pter] ) begin
						error	 = err_flag ? error : (error + 1);
						err_flag = 1;
						$write("%c[7;31m",27);
						$display("ERROR: at HB [#%d] your Hard Bit=%b, golden=%b", 
								output_pter, o_hard_bit, HardBit_mem[output_pter]);
						$display("In the meanwhile, your LLR=%h, golden=%h",
								o_llr, LLR_mem[output_pter]);
						$write("%c[0m",27);
					end else if ( o_llr === 0 ) begin
						error	 = err_flag ? error : (error + 1);
						err_flag = 1;
						$write("%c[7;31m",27);
						$display("ERROR: at LLR [#%d] your LLR is zero, golden=%h", 
								output_pter, LLR_mem[output_pter]);
						$write("%c[0m",27);
					end else if ( o_llr[7] !== o_hard_bit ) begin
						error	 = err_flag ? error : (error + 1);
						err_flag = 1;
						$write("%c[7;31m",27);
						$display("ERROR: at HB [#%d] your Hard Bit=%b, golden=%b", 
								output_pter, o_hard_bit, HardBit_mem[output_pter]);
						$display("In the meanwhile, your LLR=%h, golden=%h, but your HB != LLR[7]=%b",
								o_llr, LLR_mem[output_pter], o_llr[7]);
						$write("%c[0m",27);
					end
					if(warning) begin
						if ( o_llr !== LLR_mem[output_pter] ) begin
							$write("%c[1;31m",27);
							if (debug) begin
								D0		= $signed( o_llr );
								D1		= $signed( LLR_mem[output_pter] );
								$display("Warning: at LLR [#%d] your LLR=%f, golden=%f",
									output_pter, D0/(2**4), D1/(2**4));
							end else begin
								$display("Warning: at LLR [#%d] your LLR=%h, golden=%h", 
									output_pter, o_llr, LLR_mem[output_pter]);
							end
							$write("%c[0m",27);
						end
					end
					output_pter		= output_pter + 1;
					Has_Accept		= Has_Accept + 1;
					if(count1RE < 8) begin
						count1RE = count1RE + 1;
					end
					else begin
						count1RE = 0;
						err_flag = 0;
					end
				end
			end else begin
				i_rd_rdy	= 1'b0;
			end
			
			// T_cycle + 1
			T_cycle = T_cycle + 1;
		end	// while(output_pter<8000)

		$display("error=%d", error);
        if ( error < `threshold ) begin
			$write("%c[7;33m",27);
            $display("----------------------------------------------");
            $display("-            PASS! Congraduation!             -");
			$display("      Number of Wrong Pattern is %d/1000      ", error);
			$display("Data Error Rate = %1.3f, whcih should lower than %1.3f", error / 1000.0, `threshold / 1000.0);
            $display("----------------------------------------------");
			$write("%c[0m",27);
        end else begin
			$write("%c[7;31m",27);
            $display("----------------------------------------------------");
            $display("      Wrong! Error percenttage beyond threshold      ");
			$display("      Number of Wrong Pattern is %d/1000      ", error);
			$display("Data Error Rate = %1.3f, whcih should lower than %1.3f", error / 1000.0, `threshold / 1000.0);
            $display("----------------------------------------------------");
			$write("%c[0m",27);
        end
        # ( 2 * `CYCLE);
        $finish;
	end		// initial
endmodule
