// ============================================================================
// tb_vu_hdmi.v - vu_screen conectado al modulo hdmi DE VERDAD.     (MoonTANG)
//
// tb_vu_screen.v da por buena la cadencia "rgb un ciclo despues de cx/cy".
// Este banco no supone nada: monta fpga/hdmi/hdmi.sv (pasado por sv2v) con los
// mismos parametros que el top, deja que sea el quien genere cx/cy, y recoge
// la imagen DESPUES de hdmi, tal como entra en los codificadores TMDS:
// `video_data` en los ciclos en que `mode` = 1 (periodo de video). El primer
// pixel de cada tramo de video es la columna 0, igual que lo veria la tele.
//
// hdmi sale del reset en la linea 520 (START_Y; el top usa 0) para que el
// cuadro que se captura, el primero entero, llegue tras cinco lineas de
// borrado y no haya que simular un cuadro de mas. Se vuelca a vu_hdmi.ppm y
// vu_check.py lo compara pixel a pixel con el modelo. Si la pantalla saliera
// desplazada un solo pixel, o una capa respecto de otra, la comparacion
// fallaria.
// ============================================================================
`timescale 1ns/1ps
`default_nettype none

`ifndef VU_BUILD
`define VU_BUILD "2026-10-04"
`endif

module tb_vu_hdmi;

    localparam integer HA = 720, VA = 480;

    reg clk = 1'b0;
    always #18.5 clk = ~clk;                // 27 MHz
    reg clk_audio = 1'b0;
    always #10416 clk_audio = ~clk_audio;   // ~48 kHz
    reg rst_n = 1'b0;

    // los niveles del cuadro "b" de tb_vu_screen
    wire [29:0] level  = {5'd17, 5'd21, 5'd8,  5'd12, 5'd19, 5'd23};
    wire [29:0] peak   = {5'd20, 5'd25, 5'd13, 5'd16, 5'd22, 5'd26};
    wire [1:0]  st_rom = 2'd1;
    wire        st_msx = 1'b1;
    wire [4:0]  sample_level = 5'd14;

    wire [9:0]  cx, cy;
    wire [23:0] rgb;
    wire [29:0] tmds_internal;

    vu_screen #(.BUILD(`VU_BUILD)) u_screen (
        .clk   (clk),
        .rst_n (rst_n),
        .cx    (cx),
        .cy    (cy),
        .rgb   (rgb),
        .level (level),
        .peak  (peak),
        .st_rom(st_rom),
        .st_msx(st_msx),
        .sample_level(sample_level)
    );

    // como en moontang_smd_top.sv
    hdmi #(
        .VIDEO_ID_CODE     (2),
        .DVI_OUTPUT        (0),
        .VIDEO_REFRESH_RATE(59.94),
        .IT_CONTENT        (1),
        .AUDIO_RATE        (48000),
        .AUDIO_BIT_WIDTH   (16),
        .START_X           (0),
        .START_Y           (520),           // el top usa 0; ver la cabecera
        .NUM_CHANNELS      (3)
    ) u_hdmi (
        .clk_pixel_x5     (1'b0),
        .clk_pixel        (clk),
        .clk_audio        (clk_audio),
        .reset            (~rst_n),
        .rgb              (rgb),
        .audio_sample_word(32'd0),          // sv2v aplana el array [1:0] de 16 bits
        .aspect_16_9      (1'b1),
        .cx               (cx),
        .cy               (cy),
        .frame_width      (),
        .frame_height     (),
        .screen_width     (),
        .screen_height    (),
        .tmds_internal    (tmds_internal)
    );

    // ------------------------------------------------------------------
    // Captura a la salida de hdmi
    // ------------------------------------------------------------------
    reg [23:0] fb [0:HA*VA-1];
    integer    x      = 0;                  // pixel dentro del tramo de video
    integer    nline  = 0;                  // tramos de video vistos
    integer    errors = 0;
    integer    fd, i;
    reg [23:0] c;

    always @(posedge clk) begin
        if (rst_n) begin
            if (u_hdmi.mode == 3'd1) begin
                if (nline < VA && x < HA)
                    fb[nline*HA + x] = u_hdmi.video_data;
                x = x + 1;
            end
            else if (x != 0) begin
                if (x != HA) begin
                    errors = errors + 1;
                    if (errors <= 10) $display("  ERROR: tramo de video %0d con %0d pixeles", nline, x);
                end
                x     = 0;
                nline = nline + 1;
            end
        end
    end

    initial begin
        repeat (8) @(posedge clk);
        #1 rst_n = 1'b1;
        wait (nline == VA);
        fd = $fopen("vu_hdmi.ppm", "wb");
        $fwrite(fd, "P6\n%0d %0d\n255\n", HA, VA);
        for (i = 0; i < HA*VA; i = i + 1) begin
            c = fb[i];
            if (^c === 1'bx) errors = errors + 1;
            $fwrite(fd, "%c%c%c", c[23:16], c[15:8], c[7:0]);
        end
        $fclose(fd);
        fd = $fopen("frames_hdmi.txt", "w");
        $fdisplay(fd, "vu_hdmi.ppm %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d %0d",
                  level[4:0], level[9:5], level[14:10], level[19:15], level[24:20], level[29:25],
                  peak[4:0],  peak[9:5],  peak[14:10],  peak[19:15],  peak[24:20],  peak[29:25],
                  st_rom, st_msx, sample_level);
        $fclose(fd);
        $display("HDMI: %0d tramos de video de %0d pixeles a la salida de hdmi.sv; volcado vu_hdmi.ppm",
                 nline, HA);
        if (errors == 0) $display("RESULTADO HDMI: PASS");
        else             $display("RESULTADO HDMI: FAIL (%0d errores)", errors);
        $finish;
    end

    initial begin
        #(37.0 * 858 * 525 * 3);
        $display("RESULTADO HDMI: FAIL (tiempo agotado)");
        $finish;
    end

endmodule

`default_nettype wire
