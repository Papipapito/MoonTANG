// ============================================================================
// moontang_av.sv — salida por el HDMI de la Tang Nano 20K: sonido + vumetro.
//                                                                 (MoonTANG)
// Lo comparten las dos placas: en la MSXhdmi_tn20k_smd es la UNICA salida de
// sonido; en la WonderTANG va en paralelo con el audio que entra al MSX.
//
// Hace cuatro cosas:
//   1. Relojes del HDMI: pixel = el cristal de 27 MHz (por BUFG) y x5 = 135 MHz
//      de un rPLL, como en los diseños probados para esta FPGA.
//   2. De esos 135 MHz saca tambien el reloj del MOTOR PCM (135 / 3,5 =
//      38,571 MHz): el GW2AR-18 solo tiene dos PLL y el segundo es para el
//      sistema, asi que con HDMI el motor no puede tener PLL propio. Su CE
//      fraccionario es entonces 2744/3125 (33,8688 MHz de media).
//   3. Audio: 48 kHz exactos = 54 MHz / 1125. clk_audio esta alto la primera
//      mitad del periodo; el transmisor toma la muestra en su flanco de SUBIDA
//      y aqui se cambia en el de BAJADA (10 us de margen, sin dato en transito).
//   4. Vumetro: vu_meter mide en clk_54m y vu_screen pinta en el reloj de pixel.
//
// El transmisor es hdl-util/hdmi con la misma configuracion que suena en el
// MSXnano, salvo los 48 kHz. 720x480p a 59,94 Hz, marcado 16:9.
// ============================================================================

`default_nettype none

module moontang_av #(
    parameter [8*10-1:0] BUILD = "2026-10-05",   // 10 caracteres, pie de pantalla
    // 1 = clk_audio (48 kHz, una treintena de registros) por una red global.
    // 0 = por rutado normal: para cuando las 8 redes globales ya estan ocupadas.
    parameter AUDIO_BUFG = 1,
    // 1 = septima barra "MSX-AUDIO" (mono) en el vumetro, con y8950_vu: solo la
    // variante con Y8950 y HDMI. 0 = la pantalla de siempre (y8950_vu sin usar).
    parameter Y8950 = 0
) (
    input  wire        clk,             // 27 MHz del cristal (pin 4)
    input  wire        clk_54m,         // reloj de sistema (audio y medidores)
    input  wire        sys_locked,      // el PLL de sistema ha enganchado

    output wire        clk_eng,         // 38,571 MHz para el motor PCM
    output wire        lock,            // el PLL del HDMI ha enganchado

    // ---- audio, en clk_54m ----
    input  wire signed [15:0] fm_l,
    input  wire signed [15:0] fm_r,
    input  wire signed [15:0] wave_l,
    input  wire signed [15:0] wave_r,
    input  wire signed [15:0] mix_l,    // lo que va al HDMI
    input  wire signed [15:0] mix_r,
    input  wire signed [15:0] y8950_vu, // aporte del MSX-Audio (solo con Y8950 = 1)

    // ---- estado (casi estatico) ----
    input  wire        wl_done,
    input  wire        wl_error,
    input  wire        wl_badimg,       // la imagen copiada no es la YRW801
    input  wire        clk_alive,
    // marca de agua alta de la RAM OPL4, Gray y originada en clk_eng.
    input  wire [21:0] sample_used_gray,

    // ---- HDMI de la Tang ----
    output wire        tmds_clk_p,
    output wire        tmds_clk_n,
    output wire [2:0]  tmds_data_p,
    output wire [2:0]  tmds_data_n
);

    // ------------------------------------------------------------------
    //  Relojes
    // ------------------------------------------------------------------
    wire clk_pix;
    BUFG u_bufg_pix (.O(clk_pix), .I(clk));

    wire clk_135, clk_135m;
    pll_hdmi u_pll_hdmi (.clkout(clk_135), .lock(lock), .reset(1'b0), .clkin(clk));
    BUFG u_bufg_135 (.O(clk_135m), .I(clk_135));

    // clk_eng para el motor PCM: 135/3,5 = 38,571 MHz. El motor solo usa el
    // flanco de subida, asi que el ciclo de trabajo del divisor no importa.
    CLKDIV u_diveng (.CLKOUT(clk_eng), .HCLKIN(clk_135), .RESETN(lock), .CALIB(1'b0));
    defparam u_diveng.DIV_MODE = "3.5";
    defparam u_diveng.GSREN    = "false";

    wire pll_locked = sys_locked & lock;

    // ------------------------------------------------------------------
    //  Audio para el HDMI: 48 kHz exactos = 54 MHz / 1125
    // ------------------------------------------------------------------
    reg [10:0] aud_cnt   = 11'd0;
    reg        clk_audio = 1'b0;
    reg signed [15:0] aud_l = 16'sd0, aud_r = 16'sd0;
    always @(posedge clk_54m) begin
        aud_cnt   <= (aud_cnt == 11'd1124) ? 11'd0 : aud_cnt + 11'd1;
        clk_audio <= (aud_cnt < 11'd562);
        if (aud_cnt == 11'd562) begin
            aud_l <= mix_l;
            aud_r <= mix_r;
        end
    end
    wire clk_audio_w;
    generate
        if (AUDIO_BUFG) begin : g_abuf
            BUFG u_bufg_aud (.O(clk_audio_w), .I(clk_audio));
        end
        else begin : g_anobuf
            assign clk_audio_w = clk_audio;
        end
    endgenerate

    // ------------------------------------------------------------------
    //  Video: reset del dominio de pixel
    // ------------------------------------------------------------------
    reg [15:0] rst_ctr_pix = 16'd0;
    reg        rst_n_pix   = 1'b0;
    always @(posedge clk_pix) begin
        if (!pll_locked) begin
            rst_ctr_pix <= 16'd0;
            rst_n_pix   <= 1'b0;
        end
        else if (rst_ctr_pix != 16'hFFFF) rst_ctr_pix <= rst_ctr_pix + 16'd1;
        else                              rst_n_pix   <= 1'b1;
    end

    // ------------------------------------------------------------------
    //  Vumetro
    // ------------------------------------------------------------------
    localparam NUM_CHANNELS = 3;
    wire [9:0]  cx, cy;
    wire [23:0] rgb;

    // un cambio por cuadro, al empezar el borrado vertical
    reg frame_tog = 1'b0;
    always @(posedge clk_pix)
        if (cx == 10'd0 && cy == 10'd480) frame_tog <= ~frame_tog;

    localparam integer NBAR = Y8950 ? 7 : 6;
    wire [NBAR*5-1:0] vu_level, vu_peak;
    generate
        if (Y8950) begin : g_vu7
            vu_meter #(.NCH(7)) u_vu (
                .clk(clk_54m), .frame_tog(frame_tog),
                .samples({y8950_vu, mix_r, mix_l, wave_r, wave_l, fm_r, fm_l}),
                .level(vu_level), .peak(vu_peak)
            );
        end
        else begin : g_vu6
            vu_meter #(.NCH(6)) u_vu (
                .clk(clk_54m), .frame_tog(frame_tog),
                .samples({mix_r, mix_l, wave_r, wave_l, fm_r, fm_l}),
                .level(vu_level), .peak(vu_peak)
            );
        end
    endgenerate

    // estado, al dominio de pixel (casi estatico)
    reg [1:0] st_rom_s0 = 2'd0, st_rom_s1 = 2'd0;
    reg       st_msx_s0 = 1'b0, st_msx_s1 = 1'b0;
    reg [4:0] sample_level_s0 = 5'd0, sample_level_s1 = 5'd0;
    reg [21:0] sample_gray_s0 = 22'd0, sample_gray_s1 = 22'd0;
    always @(posedge clk_pix) begin
        st_rom_s0 <= wl_error ? 2'd2 : (!wl_done ? 2'd0 : (wl_badimg ? 2'd3 : 2'd1));
        st_rom_s1 <= st_rom_s0;
        st_msx_s0 <= clk_alive;
        st_msx_s1 <= st_msx_s0;
        sample_level_s0 <= sample_level;
        sample_level_s1 <= sample_level_s0;
    end

    // CDC de una cantidad monotona: Gray evita que el video vea un valor
    // intermedio al cruzar la marca de agua del motor PCM.
    always @(posedge clk_54m) begin
        if (!sys_locked) begin
            sample_gray_s0 <= 22'd0;
            sample_gray_s1 <= 22'd0;
        end
        else begin
            sample_gray_s0 <= sample_used_gray;
            sample_gray_s1 <= sample_gray_s0;
        end
    end
    function [21:0] gray2bin;
        input [21:0] gray;
        integer n;
        begin
            gray2bin[21] = gray[21];
            for (n = 20; n >= 0; n = n - 1)
                gray2bin[n] = gray2bin[n + 1] ^ gray[n];
        end
    endfunction
    wire [21:0] sample_used_bin = gray2bin(sample_gray_s1);
    // 28/2MiB = 1/64 - 1/512.  Se incluye el bit 21: 2 MiB exactos son
    // 32 - 4 = 28 segmentos, no una vuelta a cero al llegar al ultimo byte.
    wire [4:0] sample_level = sample_used_bin[21:16] - sample_used_bin[21:19];

    vu_screen #(.BUILD(BUILD), .Y8950(Y8950)) u_screen (
        .clk(clk_pix), .rst_n(rst_n_pix),
        .cx(cx), .cy(cy), .rgb(rgb),
        .level(vu_level), .peak(vu_peak),
        .st_rom(st_rom_s1), .st_msx(st_msx_s1), .sample_level(sample_level_s1)
    );

    // ------------------------------------------------------------------
    //  HDMI (hdl-util/hdmi, la misma configuracion que suena en el MSXnano)
    // ------------------------------------------------------------------
    logic [15:0] audio_sample_word [1:0];
    assign audio_sample_word[0] = aud_l;
    assign audio_sample_word[1] = aud_r;

    logic [9:0] tmds_internal [NUM_CHANNELS-1:0];
    logic [2:0] tmds;

    hdmi #(
        .VIDEO_ID_CODE(2),                  // 720x480p (con aspect_16_9 = VIC 3)
        .DVI_OUTPUT(0),                     // HDMI de verdad: lleva audio
        .VIDEO_REFRESH_RATE(59.94),
        .IT_CONTENT(1),
        .AUDIO_RATE(48000),
        .AUDIO_BIT_WIDTH(16),
        .VENDOR_NAME({"MoonTANG"}),
        .PRODUCT_DESCRIPTION({"MoonSound OPL4", 16'd0}),
        .SOURCE_DEVICE_INFORMATION(8'h00),
        .START_X(0),
        .START_Y(0),
        .NUM_CHANNELS(NUM_CHANNELS)
    ) u_hdmi (
        .clk_pixel_x5(clk_135m),
        .clk_pixel   (clk_pix),
        .clk_audio   (clk_audio_w),
        .rgb         (rgb),
        .reset       (~rst_n_pix),
        .audio_sample_word(audio_sample_word),
        .aspect_16_9 (1'b1),
        .cx          (cx),
        .cy          (cy),
        .tmds_internal(tmds_internal)
    );

    serializer #(.NUM_CHANNELS(NUM_CHANNELS), .VIDEO_RATE(0)) u_ser (
        .clk_pixel(clk_pix), .clk_pixel_x5(clk_135m), .reset(~rst_n_pix),
        .tmds_internal(tmds_internal), .tmds(tmds)
    );

    ELVDS_OBUF tmds_bufds [3:0] (
        .I ({clk_pix, tmds}),
        .O ({tmds_clk_p, tmds_data_p}),
        .OB({tmds_clk_n, tmds_data_n})
    );

endmodule

`default_nettype wire
