/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ct4111_buzzer (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);
    wire song_sel = ui_in[0]; // 0 = Imperial March, 1 = NGGYP
    wire pause    = ui_in[1];

    assign uio_out = 8'b0;
    assign uio_oe  = 8'b0;
    assign uo_out[7:1] = 7'b0;

    // ── Prescaler: 50 MHz ÷ 100 → 500 kHz tick ──────────────────────────────
    reg [6:0] prescaler;
    wire tick;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) prescaler <= 7'd0;
        else        prescaler <= (prescaler == 7'd99) ? 7'd0 : prescaler + 7'd1;
    end
    assign tick = (prescaler == 7'd0);

    // ── Frequency LUT: half-period in 500 kHz ticks ──────────────────────────
    // half_period = 500000 / (2 * freq_Hz)
    reg [10:0] freq_lut [0:15];
    initial begin
        freq_lut[ 0] = 11'd0;    // REST
        freq_lut[ 1] = 11'd716;  // F4   349 Hz
        freq_lut[ 2] = 11'd602;  // GS4  415 Hz
        freq_lut[ 3] = 11'd568;  // A4   440 Hz
        freq_lut[ 4] = 11'd506;  // B4   494 Hz
        freq_lut[ 5] = 11'd478;  // C5   523 Hz
        freq_lut[ 6] = 11'd451;  // CS5  554 Hz
        freq_lut[ 7] = 11'd402;  // DS5  622 Hz
        freq_lut[ 8] = 11'd426;  // D5   587 Hz
        freq_lut[ 9] = 11'd379;  // E5   659 Hz
        freq_lut[10] = 11'd358;  // F5   698 Hz
        freq_lut[11] = 11'd338;  // FS5  740 Hz
        freq_lut[12] = 11'd319;  // G5   784 Hz
        freq_lut[13] = 11'd301;  // GS5  831 Hz
        freq_lut[14] = 11'd284;  // A5   880 Hz
        freq_lut[15] = 11'd0;    // unused (LOOP marker)
    end

    // ── Duration LUTs: ticks at 500 kHz ──────────────────────────────────────
    // wholenote ticks = 500000 * (60/tempo) * 4
    reg [20:0] dur_s0 [0:7]; // Song 0 – Imperial March, tempo = 120 BPM
    reg [20:0] dur_s1 [0:7]; // Song 1 – NGGYP,          tempo = 114 BPM
    initial begin
        // Song 0 (tempo 120): wholenote = 1 000 000 ticks
        dur_s0[0] = 21'd0;        // loop/end
        dur_s0[1] = 21'd1000000;  // whole
        dur_s0[2] = 21'd500000;   // half
        dur_s0[3] = 21'd375000;   // dotted quarter
        dur_s0[4] = 21'd250000;   // quarter
        dur_s0[5] = 21'd187500;   // dotted eighth
        dur_s0[6] = 21'd125000;   // eighth
        dur_s0[7] = 21'd62500;    // sixteenth

        // Song 1 (tempo 114): wholenote ≈ 1 052 632 ticks
        dur_s1[0] = 21'd0;
        dur_s1[1] = 21'd1052632;
        dur_s1[2] = 21'd526316;
        dur_s1[3] = 21'd394737;
        dur_s1[4] = 21'd263158;
        dur_s1[5] = 21'd197368;
        dur_s1[6] = 21'd131579;
        dur_s1[7] = 21'd65789;
    end

    // ── Song ROMs (64 entries each, byte = {note[3:0], 1'b0, dur[2:0]}) ──────
    reg [7:0] song0 [0:63];
    reg [7:0] song1 [0:63];

    initial begin
        // ════ Imperial March – extended (measures 1‑6 + 7‑10) ════════════════
        // Measures 1‑2:  A4 dot‑qtr ×2, A4 16th ×4, F4 8th, REST 8th (repeat)
        song0[ 0] = 8'h33; song0[ 1] = 8'h33;                   // A4(-4) A4(-4)
        song0[ 2] = 8'h37; song0[ 3] = 8'h37;                   // A4(16) A4(16)
        song0[ 4] = 8'h37; song0[ 5] = 8'h37;                   // A4(16) A4(16)
        song0[ 6] = 8'h16; song0[ 7] = 8'h06;                   // F4(8)  REST(8)
        song0[ 8] = 8'h33; song0[ 9] = 8'h33;                   // repeat
        song0[10] = 8'h37; song0[11] = 8'h37;
        song0[12] = 8'h37; song0[13] = 8'h37;
        song0[14] = 8'h16; song0[15] = 8'h06;
        // Measure 3:  A4(4) A4(4) A4(4)  F4(-8)  C5(16)
        song0[16] = 8'h34; song0[17] = 8'h34; song0[18] = 8'h34; // A4(4)×3
        song0[19] = 8'h15; song0[20] = 8'h57;                     // F4(-8) C5(16)
        // Measure 4:  A4(4)  F4(-8)  C5(16)  A4(2)
        song0[21] = 8'h34; song0[22] = 8'h15;                    // A4(4) F4(-8)
        song0[23] = 8'h57; song0[24] = 8'h32;                    // C5(16) A4(2)
        // Measure 5:  E5(4) E5(4) E5(4)  F5(-8)  C5(16)
        song0[25] = 8'h94; song0[26] = 8'h94; song0[27] = 8'h94; // E5(4)×3
        song0[28] = 8'hA5; song0[29] = 8'h57;                     // F5(-8) C5(16)
        // Measure 6:  A4(4)  F4(-8)  C5(16)  A4(2)
        song0[30] = 8'h34; song0[31] = 8'h15;
        song0[32] = 8'h57; song0[33] = 8'h32;
        // Measure 7 (first part): A5(4) A4(-8) A4(16) A5(4) GS5(-8) G5(16)
        song0[34] = 8'hE4; song0[35] = 8'h35; song0[36] = 8'h37; // A5(4) A4(-8) A4(16)
        song0[37] = 8'hE4; song0[38] = 8'hD5; song0[39] = 8'hC7; // A5(4) GS5(-8) G5(16)
        // Measure 7 (continued): DS5(16) D5(16) DS5(8) REST(8) A4(8) DS5(4) D5(-8) CS5(16)
        song0[40] = 8'h77; song0[41] = 8'h87; song0[42] = 8'h76; // DS5(16) D5(16) DS5(8)
        song0[43] = 8'h06; song0[44] = 8'h36; song0[45] = 8'h74; // REST(8) A4(8) DS5(4)
        song0[46] = 8'h85; song0[47] = 8'h67;                     // D5(-8) CS5(16)
        // Measure 9: C5(16) B4(16) C5(16) REST(8) F4(8) GS4(4) F4(-8) A4(16)
        song0[48] = 8'h57; song0[49] = 8'h47; song0[50] = 8'h57; // C5(16) B4(16) C5(16)
        song0[51] = 8'h06; song0[52] = 8'h16; song0[53] = 8'h24; // REST(8) F4(8) GS4(4)
        song0[54] = 8'h15; song0[55] = 8'h37;                     // F4(-8) A4(16)
        // Measure 10: C5(4) A4(-8) C5(16) E5(2)
        song0[56] = 8'h54; song0[57] = 8'h35; song0[58] = 8'h57; // C5(4) A4(-8) C5(16)
        song0[59] = 8'h92;                                        // E5(2)
        // Loop marker
        song0[60] = 8'hF0;
        begin : fill_s0
            integer i;
            for (i = 61; i < 64; i = i+1) song0[i] = 8'hF0;
        end
    end

    initial begin
        // ════ Never Gonna Give You Up – main chorus, 8 measures ═════════════
        // (unchanged)
        song1[ 0] = 8'hB5; song1[ 1] = 8'hB5;                    // FS5(-8) FS5(-8)
        song1[ 2] = 8'h93;                                         // E5(-4)
        song1[ 3] = 8'h37; song1[ 4] = 8'h47;                    // A4(16) B4(16)
        song1[ 5] = 8'h87; song1[ 6] = 8'h47;                    // D5(16) B4(16)
        song1[ 7] = 8'h95; song1[ 8] = 8'h95;                    // E5(-8) E5(-8)
        song1[ 9] = 8'h85; song1[10] = 8'h67;                    // D5(-8) CS5(16)
        song1[11] = 8'h45;                                         // B4(-8)
        song1[12] = 8'h37; song1[13] = 8'h47;                    // A4(16) B4(16)
        song1[14] = 8'h87; song1[15] = 8'h47;                    // D5(16) B4(16)
        song1[16] = 8'h84; song1[17] = 8'h96;                    // D5(4) E5(8)
        song1[18] = 8'h65; song1[19] = 8'h47;                    // CS5(-8) B4(16)
        song1[20] = 8'h36; song1[21] = 8'h36; song1[22] = 8'h36; // A4(8)×3
        song1[23] = 8'h94; song1[24] = 8'h82;                    // E5(4) D5(2)
        song1[25] = 8'h37; song1[26] = 8'h47;                    // A4(16) B4(16)
        song1[27] = 8'h87; song1[28] = 8'h47;                    // D5(16) B4(16)
        song1[29] = 8'hB5; song1[30] = 8'hB5;                    // FS5(-8) FS5(-8)
        song1[31] = 8'h93;                                         // E5(-4)
        song1[32] = 8'h37; song1[33] = 8'h47;                    // A4(16) B4(16)
        song1[34] = 8'h87; song1[35] = 8'h47;                    // D5(16) B4(16)
        song1[36] = 8'hE4; song1[37] = 8'h66;                    // A5(4) CS5(8)
        song1[38] = 8'h85; song1[39] = 8'h67;                    // D5(-8) CS5(16)
        song1[40] = 8'h46;                                         // B4(8)
        song1[41] = 8'h37; song1[42] = 8'h47;                    // A4(16) B4(16)
        song1[43] = 8'h87; song1[44] = 8'h47;                    // D5(16) B4(16)
        song1[45] = 8'h84; song1[46] = 8'h96;                    // D5(4) E5(8)
        song1[47] = 8'h65; song1[48] = 8'h47;                    // CS5(-8) B4(16)
        song1[49] = 8'h34; song1[50] = 8'h36;                    // A4(4) A4(8)
        song1[51] = 8'h94; song1[52] = 8'h82; song1[53] = 8'h04; // E5(4) D5(2) REST(4)
        song1[54] = 8'hF0;                                        // Loop marker
        begin : fill_s1
            integer i;
            for (i = 55; i < 64; i = i+1) song1[i] = 8'hF0;
        end
    end

    // ── Sequencer ─────────────────────────────────────────────────────────────
    reg [5:0]  note_ptr;      // current position in ROM (0-63)
    reg [20:0] dur_cnt;       // remaining ticks for current note
    reg [10:0] half_cnt;      // remaining ticks until next audio edge
    reg        audio_out;
    reg        playing;       // 0 = LOAD phase, 1 = PLAY phase
    reg        prev_song_sel;

    // Combinational reads from ROM and LUTs
    wire [7:0]  cur_entry    = song_sel ? song1[note_ptr] : song0[note_ptr];
    wire [3:0]  cur_note     = cur_entry[7:4];
    wire [2:0]  cur_dur_type = cur_entry[2:0];
    wire        is_loop      = (cur_note == 4'd15);
    wire [20:0] cur_dur      = song_sel ? dur_s1[cur_dur_type] : dur_s0[cur_dur_type];
    wire [10:0] cur_half     = freq_lut[cur_note];

    wire song_changed = (song_sel != prev_song_sel);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_ptr      <= 6'd0;
            dur_cnt       <= 21'd0;
            half_cnt      <= 11'd0;
            audio_out     <= 1'b0;
            playing       <= 1'b0;
            prev_song_sel <= 1'b0;
        end else begin
            prev_song_sel <= song_sel;

            if (song_changed) begin
                // Song switched – restart from top
                note_ptr  <= 6'd0;
                dur_cnt   <= 21'd0;
                half_cnt  <= 11'd0;
                audio_out <= 1'b0;
                playing   <= 1'b0;

            end else if (tick && !pause) begin

                if (!playing) begin
                    // ── LOAD phase ───────────────────────────────────────────
                    // Read the note at note_ptr and either loop or start playing
                    if (is_loop) begin
                        note_ptr <= 6'd0;       // next tick re-enters LOAD with ptr=0
                    end else begin
                        dur_cnt  <= cur_dur;    // load full note duration
                        half_cnt <= cur_half;   // load half-period for tone
                        if (cur_note == 4'd0) audio_out <= 1'b0; // silence REST
                        playing  <= 1'b1;
                    end

                end else begin
                    // ── PLAY phase ───────────────────────────────────────────
                    if (dur_cnt <= 21'd1) begin
                        // Note finished – advance pointer, brief inter-note silence
                        note_ptr  <= note_ptr + 6'd1;
                        playing   <= 1'b0;
                        dur_cnt   <= 21'd0;
                        audio_out <= 1'b0;
                    end else begin
                        dur_cnt <= dur_cnt - 21'd1;
                        // Square-wave generation
                        if (cur_note == 4'd0) begin
                            audio_out <= 1'b0;              // REST
                        end else if (half_cnt == 11'd0) begin
                            audio_out <= ~audio_out;        // toggle
                            half_cnt  <= cur_half;          // reload
                        end else begin
                            half_cnt  <= half_cnt - 11'd1;
                        end
                    end
                end
            end
        end
    end

    assign uo_out[0] = audio_out;

    // Suppress unused-input warnings
    wire _unused = &{ena, uio_in, ui_in[7:2], 1'b0};

endmodule
