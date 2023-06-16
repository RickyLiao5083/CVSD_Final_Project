`timescale 1ns/1ps
`define MAX_CYCLE 1000000
`define CYCLE 21.0
module testbed;
    reg          i_clk;
    reg          i_reset;
    reg          i_trig;
    reg  [159:0] i_y_hat;
    reg  [319:0] i_r;
    reg          i_rd_rdy;
    wire         o_rd_vld;
    wire [  7:0] o_llr;
    wire         o_hard_bit;


    wire      o_handshake;
    wire      read_ans_done;
    reg       rd_vld_retention_flag;
    reg [7:0] ans;
    reg [63:0] ans_LLR;
    reg [7:0] gold;
    reg [9:0] cnt_0;
    reg [7:0] cnt_1;

    reg [159:0] pat_y_hat  [ 0:999];
    reg [319:0] pat_r      [ 0:999];
    reg [  7:0] llr_golden [0:7999];
    reg         hb_golden  [0:7999]; 

    integer i, j, k;
    real err_rate;


    `ifdef GSIM
        `define SDFFILE     "../03_GATE/ml_demodulator_syn.sdf"          // Modify your gsim sdf file name
    `elsif POST
        `define SDFFILE     "../05_POST/ml_demodulator_pr.sdf"          // Modify your pr sdf file name
    `endif

    `ifdef SDF
        initial $sdf_annotate(`SDFFILE, u_dut);
        initial #1 $display("SDF File %s were used for this simulation.", `SDFFILE);
    `endif

    initial begin
        `ifdef p1
            $readmemh ("../00_TESTBED/PATTERN/packet1/SNR10dB_pat_y_hat.dat", pat_y_hat);
            $readmemh ("../00_TESTBED/PATTERN/packet1/SNR10dB_pat_r.dat", pat_r);
            $readmemh ("../00_TESTBED/PATTERN/packet1/SNR10dB_llr.dat", llr_golden);
            $readmemb ("../00_TESTBED/PATTERN/packet1/SNR10dB_hb.dat", hb_golden);
            $display  ("#----Pattern used in this testbench is P1 SNR10dB!----#");
        `elsif p2
            $readmemh ("../00_TESTBED/PATTERN/packet2/SNR10dB_pat_y_hat.dat", pat_y_hat);
            $readmemh ("../00_TESTBED/PATTERN/packet2/SNR10dB_pat_r.dat", pat_r);
            $readmemh ("../00_TESTBED/PATTERN/packet2/SNR10dB_llr.dat", llr_golden);
            $readmemb ("../00_TESTBED/PATTERN/packet2/SNR10dB_hb.dat", hb_golden);
            $display  ("#----Pattern used in this testbench is P2 SNR10dB!----#");
        `elsif p3
            $readmemh ("../00_TESTBED/PATTERN/packet3/SNR10dB_pat_y_hat.dat", pat_y_hat);
            $readmemh ("../00_TESTBED/PATTERN/packet3/SNR10dB_pat_r.dat", pat_r);
            $readmemh ("../00_TESTBED/PATTERN/packet3/SNR10dB_llr.dat", llr_golden);
            $readmemb ("../00_TESTBED/PATTERN/packet3/SNR10dB_hb.dat", hb_golden);
            $display  ("#----Pattern used in this testbench is P3 SNR10dB!----#");
        `elsif p4
            $readmemh ("../00_TESTBED/PATTERN/packet4/SNR15dB_pat_y_hat.dat", pat_y_hat);
            $readmemh ("../00_TESTBED/PATTERN/packet4/SNR15dB_pat_r.dat", pat_r);
            $readmemh ("../00_TESTBED/PATTERN/packet4/SNR15dB_llr.dat", llr_golden);
            $readmemb ("../00_TESTBED/PATTERN/packet4/SNR15dB_hb.dat", hb_golden);
            $display  ("#----Pattern used in this testbench is P4 SNR15dB!----#");
        `elsif p5
            $readmemh ("../00_TESTBED/PATTERN/packet5/SNR15dB_pat_y_hat.dat", pat_y_hat);
            $readmemh ("../00_TESTBED/PATTERN/packet5/SNR15dB_pat_r.dat", pat_r);
            $readmemh ("../00_TESTBED/PATTERN/packet5/SNR15dB_llr.dat", llr_golden);
            $readmemb ("../00_TESTBED/PATTERN/packet5/SNR15dB_hb.dat", hb_golden);
            $display  ("#----Pattern used in this testbench is P5 SNR15dB!----#");
        `elsif p6
            $readmemh ("../00_TESTBED/PATTERN/packet6/SNR15dB_pat_y_hat.dat", pat_y_hat);
            $readmemh ("../00_TESTBED/PATTERN/packet6/SNR15dB_pat_r.dat", pat_r);
            $readmemh ("../00_TESTBED/PATTERN/packet6/SNR15dB_llr.dat", llr_golden);
            $readmemb ("../00_TESTBED/PATTERN/packet6/SNR15dB_hb.dat", hb_golden);
            $display  ("#----Pattern used in this testbench is P6 SNR15dB!----#");
        `else
            $readmemh ("../00_TESTBED/PATTERN/packet1/SNR10dB_pat_y_hat.dat", pat_y_hat);
            $readmemh ("../00_TESTBED/PATTERN/packet1/SNR10dB_pat_r.dat", pat_r);
            $readmemh ("../00_TESTBED/PATTERN/packet1/SNR10dB_llr.dat", llr_golden);
            $readmemb ("../00_TESTBED/PATTERN/packet1/SNR10dB_hb.dat", hb_golden);
            $display  ("#----Pattern used in this testbench is P1 SNR10dB!----#");
        `endif
    end

    ml_demodulator u_dut (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_trig         (i_trig),
        .i_y_hat        (i_y_hat),    
        .i_r            (i_r),
        .i_rd_rdy       (i_rd_rdy),
        .o_rd_vld       (o_rd_vld),
        .o_llr          (o_llr),    
        .o_hard_bit     (o_hard_bit)       
    );

    initial i_clk = 0;
    always #(`CYCLE/2.0) i_clk = ~i_clk;
    
    /*
    initial begin
        $fsdbDumpfile("testbed.fsdb");
        $fsdbDumpvars(0, testbed, "+mda");
    end
    */

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
			`ifdef p1
				$fsdbDumpfile("ml_demodulator_p1.fsdb");
			`elsif p2
				$fsdbDumpfile("ml_demodulator_p2.fsdb");
			`elsif p3
				$fsdbDumpfile("ml_demodulator_p3.fsdb");
			`elsif p4
				$fsdbDumpfile("ml_demodulator_p4.fsdb");
			`elsif p5
				$fsdbDumpfile("ml_demodulator_p5.fsdb");
			`else
				$fsdbDumpfile("ml_demodulator_p6.fsdb");
			`endif
			$fsdbDumpvars(0, "+mda");
			$fsdbDumpvars;
		`endif
	end

    initial begin
        ans                   = 0;
        ans_LLR               = 0;
        gold                  = 0;
        i_reset               = 0;
        i_trig                = 0;
        i_y_hat               = 0;
        i_r                   = 0;
        i_rd_rdy              = 0;
        cnt_0                 = 0;
        cnt_1                 = 0;
        rd_vld_retention_flag = 0;
        err_rate              = 0.0;
        reset_dut;

        for (i = 0; i < 1000; i = i + 1) begin
            input_task;
        end
    end

    // Early termination
    reg [19:0] trmn_cnt;
    initial trmn_cnt = 0;
    always @(posedge i_clk) begin
        trmn_cnt <= trmn_cnt + 1;
        if (trmn_cnt == `MAX_CYCLE) begin
            $display ("Latency is too long! Early termination.");
            $finish;
        end
    end

    integer seed;
    reg [1:0] rand_div_by_4;
    reg i_rdy_pat1;
    reg i_rdy_pat2;
    // i_rd_rdy generation
    initial begin
        seed = 0;
        rand_div_by_4 = 0;
        i_rdy_pat1 = 0;
        i_rdy_pat2 = 0;
    end
    always @(posedge i_clk or posedge i_reset) #(1.0) begin
        if (i_reset) begin
            i_rd_rdy = 0;
            cnt_0    = 0;
            cnt_1    = 0;
        end else begin
            if (i_rdy_pat1 == 0) begin
                i_rd_rdy = 1;
                if (cnt_1 < 128) begin
                    cnt_1 = cnt_1 + 1;
                end else begin
                    if (cnt_0 < 512) begin
                        i_rd_rdy = 0;
                        cnt_0  = cnt_0 + 1;
                        i_rdy_pat1 = (cnt_0 == 511)? 1 : i_rdy_pat1;
                    end else begin
                        cnt_1 = 0;
                        cnt_0 = 1;
                    end
                end 
            end else if (i_rdy_pat2 == 0) begin
                i_rd_rdy = 0;
                if (cnt_0 < 512) begin
                    cnt_0 = cnt_0 + 1;
                end else begin
                    if (cnt_1 < 128) begin
                        cnt_1  = cnt_1 + 1;
                        i_rd_rdy = 1;
                        i_rdy_pat2 = (cnt_1 == 127)? 1 : i_rdy_pat2;
                    end else begin
                        cnt_1 = 0;
                        cnt_0 = 1;
                    end
                end 
            end else begin
                rand_div_by_4 = {$random(seed)} % 4;
                if (rand_div_by_4 == 0) begin
                    i_rd_rdy = 1;
                    if (cnt_1 < 128) begin
                        cnt_1 = cnt_1 + 1;
                    end else begin
                        if (cnt_0 < 512) begin
                            cnt_0  = cnt_0 + 1;
                            i_rd_rdy = 0;
                        end else begin
                            cnt_1 = 1;
                            cnt_0 = 0;
                        end
                    end 
                end else begin
                    i_rd_rdy = 0;
                    if (cnt_0 < 512) begin
                        cnt_0 = cnt_0 + 1;
                    end else begin
                        if (cnt_1 < 128) begin
                            cnt_1  = cnt_1 + 1;
                            i_rd_rdy = 1;
                        end else begin
                            cnt_1 = 0;
                            cnt_0 = 1;
                        end
                    end 
                end
            end
        end
    end

    assign o_handshake = (i_rd_rdy & o_rd_vld);
    assign read_ans_done = (k == 8);
    initial begin
        j = 0;
        k = 0;
        for (j = 0; j < 1000; j = j + 1) begin
            read_answer;
            if (ans !== gold) begin
                $display ("Pattern %4d# decoded hard bit = %8b != expected %8b", j, ans, gold);
                err_rate = err_rate + 0.001;
            end else begin
                $display ("Pattern %4d# decoded hard bit = %8b == expected %8b ** Correct!! **", j, ans, gold);
            end
            if ((ans_LLR[63:56] === 0) || (ans_LLR[55:48] === 0) || (ans_LLR[47:40] === 0) || (ans_LLR[39:32] === 0) || (ans_LLR[31:24] === 0) || (ans_LLR[23:16] === 0) || (ans_LLR[15:8] === 0) || (ans_LLR[7:0] === 0)) begin
                $display ("LLR == 0");
                $finish;
            end
            if ({ans_LLR[63], ans_LLR[55], ans_LLR[47], ans_LLR[39], ans_LLR[31], ans_LLR[23], ans_LLR[15], ans_LLR[7]} !== ans) begin
                $display ("Hard bit != LLR sign bit");
                $finish;
            end
        end
        evaluate_pass_fail;
    end

    // i_reset will be pull-low four cycles
    task reset_dut; begin
        // pull-high
        @(posedge i_clk);
        #(1.0) i_reset = 1;
        repeat (3) @(posedge i_clk);

        // pull-low
        @(posedge i_clk);
        #(1.0) i_reset = 0;
    end endtask

    task input_task; begin
        @(posedge i_clk) #(1.0) begin
            i_trig     = 1;
            i_r     = pat_r [i];
            i_y_hat = pat_y_hat [i];
        end
        @(posedge i_clk) #(1.0) begin
            i_trig     = 0;
        end
        repeat (62) @(posedge i_clk);
    end endtask

    task read_answer; begin
        while (~read_ans_done) begin
            @(posedge i_clk) #(`CYCLE-1.0) begin
                if (o_handshake) begin
                    rd_vld_retention_flag = 0;
                    ans  [k] = o_hard_bit;
                    ans_LLR [8*(k+1)-1-:8] = o_llr;
                    gold [k] = hb_golden[8*j+k];
                    k = k + 1;
                end else begin
                    rd_vld_retention_flag = (o_rd_vld) ? 1 : rd_vld_retention_flag;
                    if (rd_vld_retention_flag) begin
                        if (~o_rd_vld) begin
                            $display ("Error! Once o_rd_vld is pulled high, it should be kept high before the next handshake!");
                            $finish;
                        end
                    end
                end
            end
        end
        k = 0;
    end endtask

    task evaluate_pass_fail; begin
        `ifdef P3
            if (err_rate < 0.01) begin
                $display("\n-----------------------------------------------------\n");
                $display("Congratulations! You have pass the test SNR15dB with error rate = %1.3f!\n", err_rate);
                $display("-------------------------PASS------------------------\n");
            end else begin
                $display("\n-----------------------------------------------------\n");
                $display("Failed! Your error rate is %1.3f >= 0.01! in SNR15dB test\n", err_rate);
                $display("-------------------------Fail------------------------\n");      
            end
        `elsif P4
            if (err_rate < 0.01) begin
                $display("\n-----------------------------------------------------\n");
                $display("Congratulations! You have pass the test SNR15dB with error rate = %1.3f!\n", err_rate);
                $display("-------------------------PASS------------------------\n");
            end else begin
                $display("\n-----------------------------------------------------\n");
                $display("Failed! Your error rate is %1.3f >= 0.01! in SNR15dB test\n", err_rate);
                $display("-------------------------Fail------------------------\n");      
            end
        `elsif P5
            if (err_rate < 0.01) begin
                $display("\n-----------------------------------------------------\n");
                $display("Congratulations! You have pass the test SNR15dB with error rate = %1.3f!\n", err_rate);
                $display("-------------------------PASS------------------------\n");
            end else begin
                $display("\n-----------------------------------------------------\n");
                $display("Failed! Your error rate is %1.3f >= 0.01! in SNR15dB test\n", err_rate);
                $display("-------------------------Fail------------------------\n");      
            end
        `else
            if (err_rate < 0.12) begin
                $display("\n-----------------------------------------------------\n");
                $display("Congratulations! You have pass the test SNR10dB with error rate = %1.3f!\n", err_rate);
                $display("-------------------------PASS------------------------\n");
            end else begin
                $display("\n-----------------------------------------------------\n");
                $display("Failed! Your error rate is %1.3f >= 0.12! in SNR10dB test\n", err_rate);
                $display("-------------------------Fail------------------------\n");      
            end
        `endif
        $finish;
    end endtask
endmodule
