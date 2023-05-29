module ml_demodulator(
    input           i_clk,
    input           i_reset,
    input           i_trig,
    input [159:0]   i_y_hat,
    input [319:0]   i_r,
    input           i_rd_rdy,
    output          o_rd_vld,
    output [7:0]    o_llr,
    output          o_hard_bit
);

    // Inner use
    reg        [6:0]    Ccnt;            // 6bit表示64cyc。最高 bit 表有無接觸過 input
    reg        [6:0]    Ncnt;            // 6bit表示64cyc


    reg signed [19:0]   r_11;
    reg signed [19:0]   r_12[1:0];
    reg signed [19:0]   r_22;
    reg signed [19:0]   r_13[1:0];
    reg signed [19:0]   r_23[1:0];
    reg signed [19:0]   r_33;
    reg signed [19:0]   r_14[1:0];
    reg signed [19:0]   r_24[1:0];
    reg signed [19:0]   r_34[1:0];
    reg signed [19:0]   r_44;
    reg signed [19:0]   y[3:0][1:0];

    reg signed [25:0]   xkb[3:0][1:0][1:0];     // xkb0, xkb1 (S15.10)
    reg signed [25:0]   xkb_n[3:0][1:0][1:0];   // xkb0, xkb1 (S15.10)
   
    // 用於計算的中間變數
    reg        [7:0]    operand;   // 用於 Specify S0~S3
    reg signed [19:0]   tmp[31:0];       // 計算媒介。定義加法中的每一項為何
    reg signed [22:0]   Rs[7:0]; // Rs[0]、Rs[1] 對應第一列的實部與虛部
    reg signed [22:0]   Rs_sqrt2;
    reg signed [22:0]   y_Rs[7:0];
    reg signed [22:0]   Squared[7:0];   // 本來是 22:0
    reg signed [25:0]   A;
    reg signed [7:0]    XKB_n[3:0][1:0];         // XKB_n      (S3.4)


    // 用於傳遞 xkb_min 的變數
    reg signed [25:0]  surrogate[3:0][3:0][1:0][1:0];    // (S15.10)
   
    // 用於暫存輸出資料的變數。之後優化可以只存 hard bit 而不用存 soft bit'
    // 因為要暫存 16*8 筆資料，所以 EN_LLR_pool 需要 16 個
    // 當某一 EN_LLR_pool[idx]=1 ，則以idx為起點往上，含自己共8個 LLR_pool 都要更新數據
    // 這個 idx 就是 write_pter
    reg                EN_LLR_pool[15:0];
    // 只存 hard bit 的話：
    // reg signed         LLR_pool_soft[127:0];
    reg signed [7:0]   LLR_pool[127:0];     // 用於儲存 llr 結果，需要 16*8 個暫存 reg
    reg        [6:0]   read_pter;           // read_pter 需要詳細指出哪個，所以需要 16*8=128 (7bit) 的精細度
    reg        [3:0]   write_pter;          // write_pter 則是一次填8筆
    wire               Not_Activate;


    // 只有兩狀況兩指針會相等。第一是一開始。當過了64cyc後，寫指針會移動到1，此時就valid
    // 第二是當寫指針趕上讀指針。這代表寫的比讀的快，便產生覆寫。此時其實是不該發生的錯誤
    assign o_rd_vld     = ( read_pter[6-:4]==write_pter )?  0 : 1;
    assign o_llr        = LLR_pool[read_pter];
    assign o_hard_bit   = LLR_pool[read_pter][7];
    assign Not_Activate = ( Ccnt==7'd0 )&(~i_trig);

    reg                 working_n;
    reg                 working;
    always @( * ) begin
        if ( Not_Activate ) // 預設不推cnt，唯有在接觸到有效輸入後，才在下一cyc開始計算 cnt
            working_n   = working;
        else
            working_n   = 1'b1;
    end


    // 因為不知道第一個 input 何時來，因此用 cnt 最高bit 表示有無接觸過 input
    // 若有，則開始 push。一開始全0、當遇到 input 則 Ncnt=1_000_001
    always @( * ) begin
        if ( &Ccnt[5:0] )    // 當 111_111 時，下一輪就是 1_000_000
            Ncnt    = 7'b1_000_000;
        else if ( ~working ) // 當一切全0，遇到 input 則開始推
            Ncnt    = Ccnt;
        else
            Ncnt    = Ccnt + 1;
    end


    // 控制讀寫指針
    reg             EN_write_pter;
    always @( * ) begin
        if ( &Ccnt[5:0] )    // 當 111_111 時，就要讓 write_pter 往下推一位
        // if ( Ccnt == 7'b1_000_000 )    // 當 7'b1_000_000 時，就要讓 write_pter 往下推一位
            EN_write_pter   = 1'b1;
        else
            EN_write_pter   = 1'b0;
    end
    reg             EN_read_pter;
    always @( * ) begin
        if ( i_rd_rdy & o_rd_vld )    // 當外面讀取且輸出有效時，就要讓 read_pter 往下推一位
            EN_read_pter    = 1'b1;
        else
            EN_read_pter    = 1'b0;
    end


    integer i, j;
    always @( * ) begin
    // always@( i_trig, i_y_hat, i_r, Ccnt ) begin
        // 新的設計64cyc完成一個input，故一個cyc就要算完 A0~S3, A4~A7 ...
        // 後續證明，A0, A1, A2, A3 要依序計算才不用處理衝突
        operand     = { Ccnt[5:0], 2'b00 }; // A0
        case ( operand[7] ) // S4_虛部
            1'b0: begin // 如果 S4_虛部是正的
                tmp[11] = -r_14[1];
                tmp[12] = r_14[0];
                tmp[21] = -r_24[1];
                tmp[22] = r_24[0];
                tmp[27] = -r_34[1];
                tmp[28] = r_34[0];
                tmp[31] = r_44;
            end
            default: begin //1'b1 如果 S4_虛部是負的
                tmp[11] = r_14[1];
                tmp[12] = -r_14[0];
                tmp[21] = r_24[1];
                tmp[22] = -r_24[0];
                tmp[27] = r_34[1];
                tmp[28] = -r_34[0];
                tmp[31] = -r_44;
            end
        endcase
        case ( operand[6] ) // S4_實部
            1'b0: begin // 如果 S4_實部是正的
                tmp[10] = r_14[0];
                tmp[13] = r_14[1];
                tmp[20] = r_24[0];
                tmp[23] = r_24[1];
                tmp[26] = r_34[0];
                tmp[29] = r_34[1];
                tmp[30] = r_44;
            end
            default: begin //1'b1 如果 S4_實部是負的
                tmp[10] = -r_14[0];
                tmp[13] = -r_14[1];
                tmp[20] = -r_24[0];
                tmp[23] = -r_24[1];
                tmp[26] = -r_34[0];
                tmp[29] = -r_34[1];
                tmp[30] = -r_44;
            end
        endcase
        case ( operand[5] ) // S3_虛部
            1'b0: begin // 如果 S3_虛部是正的
               tmp[7]   = -r_13[1];
               tmp[8]   = r_13[0];
               tmp[17]  = -r_23[1];
               tmp[18]  = r_23[0];
               tmp[25]  = r_33;
            end
            default: begin //1'b1
               tmp[7]   = r_13[1];
               tmp[8]   = -r_13[0];
               tmp[17]  = r_23[1];
               tmp[18]  = -r_23[0];
               tmp[25]  = -r_33;
            end
        endcase
        case ( operand[4] ) // S3_實部
            1'b0: begin // 如果 S3_實部是正的
               tmp[6]   = r_13[0];
               tmp[9]   = r_13[1];
               tmp[16]  = r_23[0];
               tmp[19]  = r_23[1];
               tmp[24]  = r_33;
            end
            default: begin //1'b1
               tmp[6]   = -r_13[0];
               tmp[9]   = -r_13[1];
               tmp[16]  = -r_23[0];
               tmp[19]  = -r_23[1];
               tmp[24]  = -r_33;
            end
        endcase


        case ( operand[3] ) // S2_虛部
            1'b0: begin // 如果 S2_虛部是正的
               tmp[3]   = -r_12[1];
               tmp[4]   = r_12[0];
               tmp[15]  = r_22;
            end
            default: begin //1'b1
               tmp[3]   = r_12[1];
               tmp[4]   = -r_12[0];
               tmp[15]  = -r_22;
            end
        endcase
        case ( operand[2] ) // S2_實部
            1'b0: begin // 如果 S2_實部是正的
               tmp[2]   = r_12[0];
               tmp[5]   = r_12[1];
               tmp[14]  = r_22;
            end
            default: begin //1'b1
               tmp[2]   = -r_12[0];
               tmp[5]   = -r_12[1];
               tmp[14]  = -r_22;
            end
        endcase
        case ( operand[1] ) // S1_虛部
            // 如果 S1_虛部是正的
            1'b0:    tmp[1] =  r_11;
            default: tmp[1] = -r_11; //1/b1
        endcase
        case ( operand[0] ) // S1_實部
            // 如果 S1_實部是正的
            1'b0:    tmp[0] =  r_11;
            default: tmp[0] = -r_11; //1/b1
        endcase


        // 在初始版本中，先不進行位數捨棄優化，在第二版才進行
        // 7個 S3.16 數值計算起來最大是 S6.16
        // reg signed [22:0] Rs[7:0]; // Rs[0]、Rs[1] 對應第一列的實部與虛部
        Rs[0] = ( (tmp[0]  + tmp[2])  + (tmp[3]  + tmp[6]) )  + ( (tmp[7] + tmp[10]) + tmp[11] );
        Rs[1] = ( (tmp[1]  + tmp[4])  + (tmp[5]  + tmp[8]) )  + ( (tmp[9] + tmp[12]) + tmp[13] );
        Rs[2] =   (tmp[14] + tmp[16]) + (tmp[17] + tmp[20])   + tmp[21];
        Rs[3] =   (tmp[15] + tmp[18]) + (tmp[19] + tmp[22])   + tmp[23];
        Rs[4] =   (tmp[24] + tmp[26]) + tmp[27];
        Rs[5] =   (tmp[25] + tmp[28]) + tmp[29];
        Rs[6] = tmp[30];
        Rs[7] = tmp[31];

        // 經測試，中間媒介只要一個就好
        // 取 {S6.8} * {S0.8} = {S6.16} ( 23 bits )
        // reg signed [22:0] Rs_sqrt2;
        // reg signed [22:0] y_Rs[7:0]; of the form S6.16
        for (i=0 ; i<4 ; i=i+1 ) begin
            for (j=0; j<2 ; j=j+1) begin
                Rs_sqrt2    = $signed( Rs[2*i+j][ 22 -: 15 ] ) * 9'sb01011_0101;
                y_Rs[2*i+j] = y[i][j] - Rs_sqrt2;
            end
        end

        // [22:0]y_Rs[7:0] 的形式是  S6.16
        // S6.16 * S6.16 = S12.32 ，太長，故取 S6.5 * S6.5= S12.10
        // reg signed [22:0]   Squared[7:0];   // 本來是 22:0
        for (i=0 ; i<8 ; i=i+1) begin
            Squared[i] = $signed( y_Rs[i][22 -: 12] ) * $signed ( y_Rs[i][22 -: 12] ) ;
        end
        // 8個 S12.10 相加最多是 S15.10
        // reg signed [25:0] A; of the form S15.10
        A = ( (Squared[0] + Squared[1]) + (Squared[2] + Squared[3]) ) +
            ( (Squared[4] + Squared[5]) + (Squared[6] + Squared[7]) ) ;

        // Check Point
        // Check Point
        // 以上的計算已確認無誤
        // Check Point
        // Check Point

        // 計算完A之後讓A跟指定的 xkb0、xkb1 比較
        // reg signed [25:0] surrogate[3:0][3:0][1:0][1:0]; // (S15.10)
        // { Ccnt[5:0], 2'b00 }; // S0
        for (i=0 ; i<4 ; i=i+1 ) begin
            for (j=0 ; j<2 ; j=j+1 ) begin
                case ( operand[2*i+j] ) // 2*0+0對應[0][0]；2*0+1對應[0][1]
                    1'b0: begin
                        surrogate[0][i][j][0] = ( A < xkb[i][j][0] )? A : xkb[i][j][0];
                        surrogate[0][i][j][1] = xkb[i][j][1];
                    end
                    default: begin //1'b1
                        surrogate[0][i][j][0] = xkb[i][j][0];
                        surrogate[0][i][j][1] = ( A < xkb[i][j][1] )? A : xkb[i][j][1];
                    end
                endcase
            end
        end

        // ==================================================== //
        // ==================================================== //
        // =================== 以上計算完A0 =================== //
        // ==================================================== //
        // ==================================================== //


        // ==================================================== //
        // ==================================================== //
        // ==================== 以下計算A1 ==================== //
        // ==================================================== //
        // ==================================================== //
        operand     = { Ccnt[5:0], 2'b01 }; // A1
        case ( operand[7] ) // S4_虛部
            1'b0: begin // 如果 S4_虛部是正的
                tmp[11] = -r_14[1];
                tmp[12] = r_14[0];
                tmp[21] = -r_24[1];
                tmp[22] = r_24[0];
                tmp[27] = -r_34[1];
                tmp[28] = r_34[0];
                tmp[31] = r_44;
            end
            default: begin //1'b1 如果 S4_虛部是負的
                tmp[11] = r_14[1];
                tmp[12] = -r_14[0];
                tmp[21] = r_24[1];
                tmp[22] = -r_24[0];
                tmp[27] = r_34[1];
                tmp[28] = -r_34[0];
                tmp[31] = -r_44;
            end
        endcase
        case ( operand[6] ) // S4_實部
            1'b0: begin // 如果 S4_實部是正的
                tmp[10] = r_14[0];
                tmp[13] = r_14[1];
                tmp[20] = r_24[0];
                tmp[23] = r_24[1];
                tmp[26] = r_34[0];
                tmp[29] = r_34[1];
                tmp[30] = r_44;
            end
            default: begin //1'b1 如果 S4_實部是負的
                tmp[10] = -r_14[0];
                tmp[13] = -r_14[1];
                tmp[20] = -r_24[0];
                tmp[23] = -r_24[1];
                tmp[26] = -r_34[0];
                tmp[29] = -r_34[1];
                tmp[30] = -r_44;
            end
        endcase
        case ( operand[5] ) // S3_虛部
            1'b0: begin // 如果 S3_虛部是正的
               tmp[7]   = -r_13[1];
               tmp[8]   = r_13[0];
               tmp[17]  = -r_23[1];
               tmp[18]  = r_23[0];
               tmp[25]  = r_33;
            end
            default: begin //1'b1
               tmp[7]   = r_13[1];
               tmp[8]   = -r_13[0];
               tmp[17]  = r_23[1];
               tmp[18]  = -r_23[0];
               tmp[25]  = -r_33;
            end
        endcase
        case ( operand[4] ) // S3_實部
            1'b0: begin // 如果 S3_實部是正的
               tmp[6]   = r_13[0];
               tmp[9]   = r_13[1];
               tmp[16]  = r_23[0];
               tmp[19]  = r_23[1];
               tmp[24]  = r_33;
            end
            default: begin //1'b1
               tmp[6]   = -r_13[0];
               tmp[9]   = -r_13[1];
               tmp[16]  = -r_23[0];
               tmp[19]  = -r_23[1];
               tmp[24]  = -r_33;
            end
        endcase


        case ( operand[3] ) // S2_虛部
            1'b0: begin // 如果 S2_虛部是正的
               tmp[3]   = -r_12[1];
               tmp[4]   = r_12[0];
               tmp[15]  = r_22;
            end
            default: begin //1'b1
               tmp[3]   = r_12[1];
               tmp[4]   = -r_12[0];
               tmp[15]  = -r_22;
            end
        endcase
        case ( operand[2] ) // S2_實部
            1'b0: begin // 如果 S2_實部是正的
               tmp[2]   = r_12[0];
               tmp[5]   = r_12[1];
               tmp[14]  = r_22;
            end
            default: begin //1'b1
               tmp[2]   = -r_12[0];
               tmp[5]   = -r_12[1];
               tmp[14]  = -r_22;
            end
        endcase
        case ( operand[1] ) // S1_虛部
            // 如果 S1_虛部是正的
            1'b0:    tmp[1] =  r_11;
            default: tmp[1] = -r_11;
        endcase
        case ( operand[0] ) // S1_實部
            // 如果 S1_實部是正的
            1'b0:    tmp[0] =  r_11;
            default: tmp[0] = -r_11;
        endcase


        // 在初始版本中，先不進行位數捨棄優化，在第二版才進行
        // 7個 S3.16 數值計算起來最大是 S6.16
        // reg signed [22:0] Rs[7:0]; // Rs[0]、Rs[1] 對應第一列的實部與虛部
        Rs[0] = ( (tmp[0]  + tmp[2])  + (tmp[3]  + tmp[6]) )  + ( (tmp[7] + tmp[10]) + tmp[11] );
        Rs[1] = ( (tmp[1]  + tmp[4])  + (tmp[5]  + tmp[8]) )  + ( (tmp[9] + tmp[12]) + tmp[13] );
        Rs[2] =   (tmp[14] + tmp[16]) + (tmp[17] + tmp[20])   + tmp[21];
        Rs[3] =   (tmp[15] + tmp[18]) + (tmp[19] + tmp[22])   + tmp[23];
        Rs[4] =   (tmp[24] + tmp[26]) + tmp[27];
        Rs[5] =   (tmp[25] + tmp[28]) + tmp[29];
        Rs[6] = tmp[30];
        Rs[7] = tmp[31];

        for (i=0 ; i<4 ; i=i+1 ) begin
            for (j=0; j<2 ; j=j+1) begin
                Rs_sqrt2    = $signed( Rs[2*i+j][ 22 -: 15 ] ) * 9'sb01011_0101;
                y_Rs[2*i+j] = y[i][j] - Rs_sqrt2;
            end
        end

        for (i=0 ; i<8 ; i=i+1) begin
            Squared[i] = $signed( y_Rs[i][22 -: 12] ) * $signed ( y_Rs[i][22 -: 12] ) ;
        end

        A = ( (Squared[0] + Squared[1]) + (Squared[2] + Squared[3]) ) +
            ( (Squared[4] + Squared[5]) + (Squared[6] + Squared[7]) ) ;
           
        for (i=0 ; i<4 ; i=i+1 ) begin
            for (j=0 ; j<2 ; j=j+1 ) begin
                case ( operand[2*i+j] ) // 2*0+0對應[0][0]；2*0+1對應[0][1]
                    1'b0: begin
                        surrogate[1][i][j][0] = ( A < surrogate[0][i][j][0] )? A : surrogate[0][i][j][0];
                        surrogate[1][i][j][1] = surrogate[0][i][j][1];
                    end
                    default: begin //1'b1
                        surrogate[1][i][j][0] = surrogate[0][i][j][0];
                        surrogate[1][i][j][1] = ( A < surrogate[0][i][j][1] )? A : surrogate[0][i][j][1];
                    end
                endcase
            end
        end

        // ==================================================== //
        // ==================================================== //
        // =================== 以上計算完A1 =================== //
        // ==================================================== //
        // ==================================================== //


        // ==================================================== //
        // ==================================================== //
        // ==================== 以下計算A2 ==================== //
        // ==================================================== //
        // ==================================================== //
        operand     = { Ccnt[5:0], 2'b10 }; // A2
        case ( operand[7] ) // S4_虛部
            1'b0: begin // 如果 S4_虛部是正的
                tmp[11] = -r_14[1];
                tmp[12] = r_14[0];
                tmp[21] = -r_24[1];
                tmp[22] = r_24[0];
                tmp[27] = -r_34[1];
                tmp[28] = r_34[0];
                tmp[31] = r_44;
            end
            default: begin //1'b1 如果 S4_虛部是負的
                tmp[11] = r_14[1];
                tmp[12] = -r_14[0];
                tmp[21] = r_24[1];
                tmp[22] = -r_24[0];
                tmp[27] = r_34[1];
                tmp[28] = -r_34[0];
                tmp[31] = -r_44;
            end
        endcase
        case ( operand[6] ) // S4_實部
            1'b0: begin // 如果 S4_實部是正的
                tmp[10] = r_14[0];
                tmp[13] = r_14[1];
                tmp[20] = r_24[0];
                tmp[23] = r_24[1];
                tmp[26] = r_34[0];
                tmp[29] = r_34[1];
                tmp[30] = r_44;
            end
            default: begin //1'b1 如果 S4_實部是負的
                tmp[10] = -r_14[0];
                tmp[13] = -r_14[1];
                tmp[20] = -r_24[0];
                tmp[23] = -r_24[1];
                tmp[26] = -r_34[0];
                tmp[29] = -r_34[1];
                tmp[30] = -r_44;
            end
        endcase
        case ( operand[5] ) // S3_虛部
            1'b0: begin // 如果 S3_虛部是正的
               tmp[7]   = -r_13[1];
               tmp[8]   = r_13[0];
               tmp[17]  = -r_23[1];
               tmp[18]  = r_23[0];
               tmp[25]  = r_33;
            end
            default: begin //1'b1
               tmp[7]   = r_13[1];
               tmp[8]   = -r_13[0];
               tmp[17]  = r_23[1];
               tmp[18]  = -r_23[0];
               tmp[25]  = -r_33;
            end
        endcase
        case ( operand[4] ) // S3_實部
            1'b0: begin // 如果 S3_實部是正的
               tmp[6]   = r_13[0];
               tmp[9]   = r_13[1];
               tmp[16]  = r_23[0];
               tmp[19]  = r_23[1];
               tmp[24]  = r_33;
            end
            default: begin //1'b1
               tmp[6]   = -r_13[0];
               tmp[9]   = -r_13[1];
               tmp[16]  = -r_23[0];
               tmp[19]  = -r_23[1];
               tmp[24]  = -r_33;
            end
        endcase


        case ( operand[3] ) // S2_虛部
            1'b0: begin // 如果 S2_虛部是正的
               tmp[3]   = -r_12[1];
               tmp[4]   = r_12[0];
               tmp[15]  = r_22;
            end
            default: begin //1'b1
               tmp[3]   = r_12[1];
               tmp[4]   = -r_12[0];
               tmp[15]  = -r_22;
            end
        endcase
        case ( operand[2] ) // S2_實部
            1'b0: begin // 如果 S2_實部是正的
               tmp[2]   = r_12[0];
               tmp[5]   = r_12[1];
               tmp[14]  = r_22;
            end
            default: begin //1'b1
               tmp[2]   = -r_12[0];
               tmp[5]   = -r_12[1];
               tmp[14]  = -r_22;
            end
        endcase
        case ( operand[1] ) // S1_虛部
            // 如果 S1_虛部是正的
            1'b0:    tmp[1] =  r_11;
            default: tmp[1] = -r_11;
        endcase
        case ( operand[0] ) // S1_實部
            // 如果 S1_實部是正的
            1'b0:    tmp[0] =  r_11;
            default: tmp[0] = -r_11;
        endcase


        // 在初始版本中，先不進行位數捨棄優化，在第二版才進行
        // 7個 S3.16 數值計算起來最大是 S6.16
        // reg signed [22:0] Rs[7:0]; // Rs[0]、Rs[1] 對應第一列的實部與虛部
        Rs[0] = ( (tmp[0]  + tmp[2])  + (tmp[3]  + tmp[6]) )  + ( (tmp[7] + tmp[10]) + tmp[11] );
        Rs[1] = ( (tmp[1]  + tmp[4])  + (tmp[5]  + tmp[8]) )  + ( (tmp[9] + tmp[12]) + tmp[13] );
        Rs[2] =   (tmp[14] + tmp[16]) + (tmp[17] + tmp[20])   + tmp[21];
        Rs[3] =   (tmp[15] + tmp[18]) + (tmp[19] + tmp[22])   + tmp[23];
        Rs[4] =   (tmp[24] + tmp[26]) + tmp[27];
        Rs[5] =   (tmp[25] + tmp[28]) + tmp[29];
        Rs[6] = tmp[30];
        Rs[7] = tmp[31];

        for (i=0 ; i<4 ; i=i+1 ) begin
            for (j=0; j<2 ; j=j+1) begin
                Rs_sqrt2    = $signed( Rs[2*i+j][ 22 -: 15 ] ) * 9'sb01011_0101;
                y_Rs[2*i+j] = y[i][j] - Rs_sqrt2;
            end
        end
        for (i=0 ; i<8 ; i=i+1) begin
            Squared[i] = $signed( y_Rs[i][22 -: 12] ) * $signed ( y_Rs[i][22 -: 12] ) ;
        end
        A = ( (Squared[0] + Squared[1]) + (Squared[2] + Squared[3]) ) +
            ( (Squared[4] + Squared[5]) + (Squared[6] + Squared[7]) ) ;
           
        for (i=0 ; i<4 ; i=i+1 ) begin
            for (j=0 ; j<2 ; j=j+1 ) begin
                case ( operand[2*i+j] ) // 2*0+0對應[0][0]；2*0+1對應[0][1]
                    1'b0: begin
                        surrogate[2][i][j][0] = ( A < surrogate[1][i][j][0] )? A : surrogate[1][i][j][0];
                        surrogate[2][i][j][1] = surrogate[1][i][j][1];
                    end
                    default: begin //1'b1
                        surrogate[2][i][j][0] = surrogate[1][i][j][0];
                        surrogate[2][i][j][1] = ( A < surrogate[1][i][j][1] )? A : surrogate[1][i][j][1];
                    end
                endcase
            end
        end

        // ==================================================== //
        // ==================================================== //
        // =================== 以上計算完A2 =================== //
        // ==================================================== //
        // ==================================================== //


        // ==================================================== //
        // ==================================================== //
        // ==================== 以下計算A3 ==================== //
        // ==================================================== //
        // ==================================================== //
        operand     = { Ccnt[5:0], 2'b11 }; // A3
        case ( operand[7] ) // S4_虛部
            1'b0: begin // 如果 S4_虛部是正的
                tmp[11] = -r_14[1];
                tmp[12] = r_14[0];
                tmp[21] = -r_24[1];
                tmp[22] = r_24[0];
                tmp[27] = -r_34[1];
                tmp[28] = r_34[0];
                tmp[31] = r_44;
            end
            default: begin //1'b1 如果 S4_虛部是負的
                tmp[11] = r_14[1];
                tmp[12] = -r_14[0];
                tmp[21] = r_24[1];
                tmp[22] = -r_24[0];
                tmp[27] = r_34[1];
                tmp[28] = -r_34[0];
                tmp[31] = -r_44;
            end
        endcase
        case ( operand[6] ) // S4_實部
            1'b0: begin // 如果 S4_實部是正的
                tmp[10] = r_14[0];
                tmp[13] = r_14[1];
                tmp[20] = r_24[0];
                tmp[23] = r_24[1];
                tmp[26] = r_34[0];
                tmp[29] = r_34[1];
                tmp[30] = r_44;
            end
           default: begin //1'b1 如果 S4_實部是負的
                tmp[10] = -r_14[0];
                tmp[13] = -r_14[1];
                tmp[20] = -r_24[0];
                tmp[23] = -r_24[1];
                tmp[26] = -r_34[0];
                tmp[29] = -r_34[1];
                tmp[30] = -r_44;
            end
        endcase
        case ( operand[5] ) // S3_虛部
            1'b0: begin // 如果 S3_虛部是正的
               tmp[7]   = -r_13[1];
               tmp[8]   = r_13[0];
               tmp[17]  = -r_23[1];
               tmp[18]  = r_23[0];
               tmp[25]  = r_33;
            end
            default: begin //1'b1
               tmp[7]   = r_13[1];
               tmp[8]   = -r_13[0];
               tmp[17]  = r_23[1];
               tmp[18]  = -r_23[0];
               tmp[25]  = -r_33;
            end
        endcase
        case ( operand[4] ) // S3_實部
            1'b0: begin // 如果 S3_實部是正的
               tmp[6]   = r_13[0];
               tmp[9]   = r_13[1];
               tmp[16]  = r_23[0];
               tmp[19]  = r_23[1];
               tmp[24]  = r_33;
            end
            default: begin //1'b1
               tmp[6]   = -r_13[0];
               tmp[9]   = -r_13[1];
               tmp[16]  = -r_23[0];
               tmp[19]  = -r_23[1];
               tmp[24]  = -r_33;
            end
        endcase


        case ( operand[3] ) // S2_虛部
            1'b0: begin // 如果 S2_虛部是正的
               tmp[3]   = -r_12[1];
               tmp[4]   = r_12[0];
               tmp[15]  = r_22;
            end
            default: begin //1'b1
               tmp[3]   = r_12[1];
               tmp[4]   = -r_12[0];
               tmp[15]  = -r_22;
            end
        endcase
        case ( operand[2] ) // S2_實部
            1'b0: begin // 如果 S2_實部是正的
               tmp[2]   = r_12[0];
               tmp[5]   = r_12[1];
               tmp[14]  = r_22;
            end
            default: begin //1'b1
               tmp[2]   = -r_12[0];
               tmp[5]   = -r_12[1];
               tmp[14]  = -r_22;
            end
        endcase
        case ( operand[1] ) // S1_虛部
            // 如果 S1_虛部是正的
            1'b0:    tmp[1] =  r_11;
            default: tmp[1] = -r_11;
        endcase
        case ( operand[0] ) // S1_實部
            // 如果 S1_實部是正的
            1'b0:    tmp[0] =  r_11;
            default: tmp[0] = -r_11;
        endcase

        Rs[0] = ( (tmp[0]  + tmp[2])  + (tmp[3]  + tmp[6]) )  + ( (tmp[7] + tmp[10]) + tmp[11] );
        Rs[1] = ( (tmp[1]  + tmp[4])  + (tmp[5]  + tmp[8]) )  + ( (tmp[9] + tmp[12]) + tmp[13] );
        Rs[2] =   (tmp[14] + tmp[16]) + (tmp[17] + tmp[20])   + tmp[21];
        Rs[3] =   (tmp[15] + tmp[18]) + (tmp[19] + tmp[22])   + tmp[23];
        Rs[4] =   (tmp[24] + tmp[26]) + tmp[27];
        Rs[5] =   (tmp[25] + tmp[28]) + tmp[29];
        Rs[6] = tmp[30];
        Rs[7] = tmp[31];

        for (i=0 ; i<4 ; i=i+1 ) begin
            for (j=0; j<2 ; j=j+1) begin
                Rs_sqrt2    = $signed( Rs[2*i+j][ 22 -: 15 ] ) * 9'sb01011_0101;
                y_Rs[2*i+j] = y[i][j] - Rs_sqrt2;
            end
        end

        for (i=0 ; i<8 ; i=i+1) begin
            Squared[i] = $signed( y_Rs[i][22 -: 12] ) * $signed ( y_Rs[i][22 -: 12] ) ;
        end

        A = ( (Squared[0] + Squared[1]) + (Squared[2] + Squared[3]) ) +
            ( (Squared[4] + Squared[5]) + (Squared[6] + Squared[7]) ) ;
           

        for (i=0 ; i<4 ; i=i+1 ) begin
            for (j=0 ; j<2 ; j=j+1 ) begin
                case ( operand[2*i+j] ) // 2*0+0對應[0][0]；2*0+1對應[0][1]
                    1'b0: begin
                        surrogate[3][i][j][0] = ( A < surrogate[2][i][j][0] )? A : surrogate[2][i][j][0];
                        surrogate[3][i][j][1] = surrogate[2][i][j][1];
                    end
                    default: begin //1'b1
                        surrogate[3][i][j][0] = surrogate[2][i][j][0];
                        surrogate[3][i][j][1] = ( A < surrogate[2][i][j][1] )? A : surrogate[2][i][j][1];
                    end
                endcase
            end
        end

        // ==================================================== //
        // ==================================================== //
        // =================== 以上計算完A3 =================== //
        // ==================================================== //
        // ==================================================== //


        // ==================================================== //
        // ==================================================== //
        // ==================== FinalStage ==================== //
        // ==================================================== //
        // ==================================================== //
        // 最後階段，依據是 A252~A255、還是 A0~A3, A4~A7 之類的來決定要更新誰。
        // Latch-elimination
        for (i=0 ; i<4 ; i=i+1 ) begin
            for (j=0 ; j<2 ; j=j+1 ) begin
                XKB_n[i][j]             = 'd0;
            end    
        end
        for (i=0 ; i<16 ; i=i+1 ) begin
            EN_LLR_pool[i]      = 1'b0;
        end

        // 一般狀況下， xkb0_min 與 xkb1_min 會利用 surrogate[3]系列 全面更新
        // 但當 cyc=63 時， surrogate[3] 系列會計算 xkb，而 xkb1_min 與 xkb0_min 會重置
        if ( &Ccnt[5:0] ) begin // cyc=63 時
        // if ( Ccnt == 7'b1_000_000 ) begin // cyc=64 時
        // reg signed [25:0] surrogate[3:0][3:0][1:0][1:0]; (S15.10)
            for (i=0 ; i<4 ; i=i+1 ) begin
                for (j=0 ; j<2 ; j=j+1 ) begin
                    XKB_n[i][j] = (surrogate[3][i][j][1] - surrogate[3][i][j][0]) >>> 6 ;
                end
            end
            EN_LLR_pool[write_pter]     = 1'b1;
            for (i=0 ; i<4 ; i=i+1 ) begin
                for (j=0 ; j<2 ; j=j+1 ) begin
                    xkb_n[i][j][0] = {1'b0, {25{1'b1}}};
                    xkb_n[i][j][1] = {1'b0, {25{1'b1}}};
                end    
            end
        end else begin
            for (i=0 ; i<4 ; i=i+1 ) begin
                for (j=0 ; j<2 ; j=j+1 ) begin
                    xkb_n[i][j][0] = surrogate[3][i][j][0];
                    xkb_n[i][j][1] = surrogate[3][i][j][1];
                end    
            end
        end
    end


    always @(posedge i_clk or posedge i_reset ) begin
        if ( i_reset ) begin
            Ccnt            <= 'd0;
            working         <= 1'b0;
            // 關於 xkb0_min 與 xkb1_min
            for (i=0 ; i<4 ; i=i+1 ) begin
                for (j=0 ; j<2 ; j=j+1 ) begin
                    xkb[i][j][0] <= {1'b0, {25{1'b1}}};
                    xkb[i][j][1] <= {1'b0, {25{1'b1}}};
                end    
            end
            // 關於 LLR_pool
            for (i=0; i<128 ; i=i+1 ) begin
                LLR_pool[i] <= 'd0;
            end
            write_pter      <= 'd0;
            read_pter       <= 'd0;
            y[0][0]         <= 'd0;
            y[0][1]         <= 'd0;
            y[1][0]         <= 'd0;
            y[1][1]         <= 'd0;
            y[2][0]         <= 'd0;
            y[2][1]         <= 'd0;
            y[3][0]         <= 'd0;
            y[3][1]         <= 'd0;
            r_11            <= 'd0;
            r_12[0]         <= 'd0;
            r_12[1]         <= 'd0;
            r_22            <= 'd0;
            r_13[0]         <= 'd0;
            r_13[1]         <= 'd0;
            r_23[0]         <= 'd0;
            r_23[1]         <= 'd0;
            r_33            <= 'd0;
            r_14[0]         <= 'd0;
            r_14[1]         <= 'd0;
            r_24[0]         <= 'd0;
            r_24[1]         <= 'd0;
            r_34[0]         <= 'd0;
            r_34[1]         <= 'd0;
            r_44            <= 'd0;

        end else begin
            Ccnt            <= Ncnt;
            working         <= working_n;

            if ( Ccnt != 'd0 ) begin
            // if ( xkb_update ) begin  // 只有在第一個cyc開始，xkb 才可以被更新
                for (i=0 ; i<4 ; i=i+1 ) begin
                    for (j=0 ; j<2 ; j=j+1 ) begin
                        xkb[i][j][0] <= xkb_n[i][j][0];
                        xkb[i][j][1] <= xkb_n[i][j][1];
                    end    
                end
            end
            for (i=0; i<16 ; i=i+1 ) begin
                if ( EN_LLR_pool[i] ) begin // 假如 EN_LLR_pool[5]=1，則更新 5,3'd0~5,3'd7 
                    LLR_pool[ { i, 3'd0} ]   <= XKB_n[0][0];
                    LLR_pool[ { i, 3'd1} ]   <= XKB_n[0][1];
                    LLR_pool[ { i, 3'd2} ]   <= XKB_n[1][0];
                    LLR_pool[ { i, 3'd3} ]   <= XKB_n[1][1];
                    LLR_pool[ { i, 3'd4} ]   <= XKB_n[2][0];
                    LLR_pool[ { i, 3'd5} ]   <= XKB_n[2][1];
                    LLR_pool[ { i, 3'd6} ]   <= XKB_n[3][0];
                    LLR_pool[ { i, 3'd7} ]   <= XKB_n[3][1];
                end
            end
            if (EN_write_pter)  write_pter  <= write_pter + 1;
            if (EN_read_pter)   read_pter   <= read_pter + 1;
            if (i_trig) begin
                y[0][0]     <= i_y_hat[0+:20];
                y[0][1]     <= i_y_hat[20+:20];
                y[1][0]     <= i_y_hat[40+:20];
                y[1][1]     <= i_y_hat[60+:20];
                y[2][0]     <= i_y_hat[80+:20];
                y[2][1]     <= i_y_hat[100+:20];
                y[3][0]     <= i_y_hat[120+:20];
                y[3][1]     <= i_y_hat[140+:20];
                r_11        <= i_r[0+:20];
                r_12[0]     <= i_r[20+:20];
                r_12[1]     <= i_r[40+:20];
                r_22        <= i_r[60+:20];
                r_13[0]     <= i_r[80+:20];
                r_13[1]     <= i_r[100+:20];
                r_23[0]     <= i_r[120+:20];
                r_23[1]     <= i_r[140+:20];
                r_33        <= i_r[160+:20];
                r_14[0]     <= i_r[180+:20];
                r_14[1]     <= i_r[200+:20];
                r_24[0]     <= i_r[220+:20];
                r_24[1]     <= i_r[240+:20];
                r_34[0]     <= i_r[260+:20];
                r_34[1]     <= i_r[280+:20];
                r_44        <= i_r[300+:20];
            end
        end
    end


   
endmodule

