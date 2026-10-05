// ============================================================================
// tb_hdmi.v -- el transmisor HDMI del repo (fpga/hdmi, hdl-util/hdmi) contra un
// receptor independiente (hdmi_rx_check.v).
//
// Que se simula: el modulo hdmi tal como lo instanciara el diseno (VIC 2,
// 720x480p a 59,94 Hz, reloj de pixel de 27 MHz, audio de 48 kHz y 16 bits,
// aspect_16_9 = 1), con un reloj de audio de 48 kHz EXACTOS sacado de 54 MHz
// entre 1125 (cuenta 0..1124, alto en la primera mitad) y las muestras
// cambiando en el flanco de BAJADA de clk_audio. Los simbolos TMDS de 10 bits
// (hdmi.tmds_internal, antes del serializador) van al receptor.
//
// Que comprueba, solo, y con que acaba en "RESULTADO: PASS" o "RESULTADO: FAIL":
//   - geometria CEA-861 de 720x480p: 858x525, 720x480 activos, hsync de 62 px
//     con porche delantero de 16, vsync de 6 lineas con porche delantero de 9,
//     polaridades negativas;
//   - que cada pixel recibido es f_rgb(x, y);
//   - ACR con N = 6144 y CTS = 27000;
//   - que las muestras de audio recibidas son, una a una y en su canal, la
//     secuencia enviada (izquierdo = audio_sample_word[0]), ~800,8 por cuadro,
//     y que el estado de canal dice 48 kHz / 16 bits / PCM;
//   - AVI InfoFrame con VIC 3 y aspecto 16:9, Audio InfoFrame presente;
//   - BCH, checksums, paridades, preambulos, bandas de guarda y codigos TMDS de
//     TODO lo recibido (eso lo hace el receptor: rx.n_err_total).
//
// LATENCIA cx/cy -> rgb que espera hdmi.sv: UN registro. En el ciclo en que
// cx,cy valen (x,y) se calcula el color y se registra; hdmi.sv lo muestrea en
// el flanco siguiente (video_data <= rgb), a la vez que carga "mode" con el
// video_data_period de ese mismo (x,y). Es decir:
//     always @(posedge clk_pixel) rgb <= color(cx, cy);
// Con rgb combinacional la imagen sale un pixel a la izquierda (+neg_rgb_comb).
//
// Controles negativos (run_hdmi.sh negativos): cada uno estropea una cosa y el
// resultado TIENE que ser FAIL. Si pasaran, el banco no valdria nada.
//   +neg_tmds=P            invierte un bit de un simbolo TMDS cada P ciclos
//   +neg_flip_cx=X +neg_flip_cy=Y [+neg_flip_canal=C] [+neg_flip_bit=B]
//                          invierte UN bit de UN simbolo (posicion del contador
//                          del transmisor, en su cuadro 2)
//   +neg_terc4_cx=X +neg_terc4_cy=Y [+neg_terc4_canal=C] [+neg_terc4_xor=V]
//                          cambia UN simbolo TERC4 por el de otro valor (dato
//                          ^ V): simbolo valido, dato falso; lo caza el BCH
//   +neg_dato_tipo=HH [+neg_dato_sub=S] [+neg_dato_bit=B]
//                          cambia un bit del primer paquete de tipo HH (hex) del
//                          cuadro 2 y RECALCULA su BCH: el paquete llega sano y
//                          solo lo cazan las comprobaciones de contenido
//                          (checksum, paridad de audio, ACR repetido, marca B).
//                          S = subpaquete 0..3 (B de 16 a 55) o 4 = cabecera
//                          (B de 8 a 23)
//   +neg_cruce_tmds        cruza los canales TMDS 1 y 2
//   +neg_audio_salto=K     el estimulo se salta la muestra K
//   +neg_audio_repite=K    el estimulo repite la muestra K
//   +neg_audio_pulso=K     el transmisor pierde el pulso K de clk_audio
//   +neg_canales           izquierdo y derecho cambiados en el estimulo
//   +neg_rgb_comb          rgb combinacional (un ciclo adelantado)
//   +neg_pixel             un bit de un pixel cambiado en el estimulo
//   +neg_aspecto           aspect_16_9 = 0 (se anuncia VIC 2, 4:3)
//   +audio_div=N           divisor del reloj de audio (1125 = 48 kHz)
//   -Ptb_hdmi.VIC=17       otro formato (576p): la geometria no casa
//   -Ptb_hdmi.AUDIO_RATE=44100   el transmisor cree que el audio es de 44,1 kHz
// Otras opciones: +cuadros=N (por defecto 3), +ppm=fichero (ultimo cuadro en
// PPM de texto), -Ptb_hdmi.VERBOSE=2, y para ACEPTAR A SABIENDAS desviaciones
// conocidas del transmisor: +tolerante (las dos desviaciones de protocolo que
// el receptor llama "desviaciones del estandar" pasan de error a aviso),
// +hfp=N y +vfp=N (porches delanteros esperados en vez de 16 y 9).
// ============================================================================
`timescale 1ps/1ps

module tb_hdmi;
    parameter integer VIC        = 2;
    parameter integer AUDIO_RATE = 48000;
    parameter integer ESTRICTO   = 1;
    parameter integer VERBOSE    = 1;

    localparam integer BW = (VIC < 4) ? 10 : ((VIC == 4) ? 11 : 12);
    localparam integer BH = (VIC == 16) ? 11 : 10;

    // secuencias de audio: izquierdo sube de uno en uno, derecho baja de tres en tres
    localparam [15:0] L0 = 16'h1000;
    localparam [15:0] R0 = 16'hE000;

    // ------------------------------------------------------------------
    //  Opciones
    // ------------------------------------------------------------------
    integer cuadros          = 3;
    integer hfp_esp          = 16;      // porche delantero de hsync esperado (CEA-861: 16)
    integer vfp_esp          = 9;       // porche delantero de vsync esperado (CEA-861: 9)
    integer audio_div        = 1125;
    integer neg_tmds         = 0;
    integer neg_flip_cx      = -1;
    integer neg_flip_cy      = -1;
    integer neg_flip_canal   = 0;
    integer neg_flip_bit     = 0;
    integer neg_terc4_cx     = -1;
    integer neg_terc4_cy     = -1;
    integer neg_terc4_canal  = 1;
    integer neg_terc4_xor    = 1;
    integer neg_dato_tipo    = -1;
    integer neg_dato_sub     = 0;
    integer neg_dato_bit     = 20;
    integer neg_audio_salto  = -1;
    integer neg_audio_repite = -1;
    integer neg_audio_pulso  = -1;
    reg     neg_cruce_tmds   = 1'b0;
    reg     neg_canales      = 1'b0;
    reg     neg_rgb_comb     = 1'b0;
    reg     neg_pixel        = 1'b0;
    reg     neg_aspecto      = 1'b0;
    reg [8*256-1:0] ppm_nombre;
    reg     ppm_pedido       = 1'b0;

    initial begin
        if ($value$plusargs("cuadros=%d", cuadros)) ;
        if ($value$plusargs("hfp=%d", hfp_esp)) ;
        if ($value$plusargs("vfp=%d", vfp_esp)) ;
        if ($test$plusargs("tolerante")) begin
            #1 rx.estricto = 0;
        end
        if ($value$plusargs("audio_div=%d", audio_div)) ;
        if ($value$plusargs("neg_tmds=%d", neg_tmds)) ;
        if ($value$plusargs("neg_flip_cx=%d", neg_flip_cx)) ;
        if ($value$plusargs("neg_flip_cy=%d", neg_flip_cy)) ;
        if ($value$plusargs("neg_flip_canal=%d", neg_flip_canal)) ;
        if ($value$plusargs("neg_flip_bit=%d", neg_flip_bit)) ;
        if ($value$plusargs("neg_terc4_cx=%d", neg_terc4_cx)) ;
        if ($value$plusargs("neg_terc4_cy=%d", neg_terc4_cy)) ;
        if ($value$plusargs("neg_terc4_canal=%d", neg_terc4_canal)) ;
        if ($value$plusargs("neg_terc4_xor=%d", neg_terc4_xor)) ;
        if ($value$plusargs("neg_dato_tipo=%h", neg_dato_tipo)) ;
        if ($value$plusargs("neg_dato_sub=%d", neg_dato_sub)) ;
        if ($value$plusargs("neg_dato_bit=%d", neg_dato_bit)) ;
        if ($value$plusargs("neg_audio_salto=%d", neg_audio_salto)) ;
        if ($value$plusargs("neg_audio_repite=%d", neg_audio_repite)) ;
        if ($value$plusargs("neg_audio_pulso=%d", neg_audio_pulso)) ;
        if ($test$plusargs("neg_cruce_tmds")) neg_cruce_tmds = 1'b1;
        if ($test$plusargs("neg_canales"))    neg_canales    = 1'b1;
        if ($test$plusargs("neg_rgb_comb"))   neg_rgb_comb   = 1'b1;
        if ($test$plusargs("neg_pixel"))      neg_pixel      = 1'b1;
        if ($test$plusargs("neg_aspecto"))    neg_aspecto    = 1'b1;
        if ($value$plusargs("ppm=%s", ppm_nombre)) ppm_pedido = 1'b1;
    end

    // ------------------------------------------------------------------
    //  Relojes: 54 MHz -> pixel de 27 MHz y audio de 48 kHz (54 MHz / 1125)
    // ------------------------------------------------------------------
    reg clk54 = 1'b0;
    always #9259 clk54 = ~clk54;                // 54 MHz (periodo de 18518 ps)

    reg clk_pixel = 1'b0;
    always @(posedge clk54) clk_pixel <= ~clk_pixel;

    integer acnt = 0;
    reg     clk_audio = 1'b0;
    always @(posedge clk54) begin
        if (acnt == audio_div - 1) acnt = 0; else acnt = acnt + 1;
        clk_audio <= (acnt < audio_div / 2);    // alto en la primera mitad de la cuenta
    end

    reg reset = 1'b1;
    initial begin
        repeat (8) @(posedge clk_pixel);
        reset <= 1'b0;
    end

    // ------------------------------------------------------------------
    //  Estimulos de audio: cambian en el flanco de BAJADA de clk_audio
    // ------------------------------------------------------------------
    function [15:0] seq_l;
        input integer n;
        begin seq_l = L0 + n; end
    endfunction
    function [15:0] seq_r;
        input integer n;
        begin seq_r = R0 - 3 * n; end
    endfunction

    integer    n_gen    = 0;                    // indice de la muestra presentada
    reg        repetida = 1'b0;
    reg [15:0] smp_l    = L0;
    reg [15:0] smp_r    = R0;
    always @(negedge clk_audio) begin
        if (n_gen + 1 == neg_audio_salto) n_gen = n_gen + 2;                    // se salta una
        else if ((n_gen == neg_audio_repite) && !repetida) repetida = 1'b1;     // repite una
        else n_gen = n_gen + 1;
        smp_l <= neg_canales ? seq_r(n_gen) : seq_l(n_gen);
        smp_r <= neg_canales ? seq_l(n_gen) : seq_r(n_gen);
    end

    // el transmisor pierde un pulso de clk_audio (control negativo)
    integer n_pulso = 0;                        // flancos de subida de clk_audio ya dados
    reg     traga   = 1'b0;
    always @(posedge clk_audio) n_pulso = n_pulso + 1;
    always @(negedge clk_audio) traga <= (n_pulso == neg_audio_pulso);
    wire    clk_audio_dut = clk_audio & ~traga;

    integer n_lat = 0;                          // muestras que el transmisor ha capturado
    always @(posedge clk_audio_dut) n_lat = n_lat + 1;

    // ------------------------------------------------------------------
    //  Estimulo de video: una funcion conocida de (x, y)
    // ------------------------------------------------------------------
    function [23:0] f_rgb;
        input [11:0] x;
        input [11:0] y;
        reg [7:0] r, g, b;
        begin
            // cuatro bandas planas: balance de continua con el dato fijo
            if ((y >= 100) && (y < 108))      f_rgb = 24'hFFFFFF;
            else if ((y >= 108) && (y < 116)) f_rgb = 24'h000000;
            else if ((y >= 116) && (y < 124)) f_rgb = 24'h10EF80;
            else if ((y >= 124) && (y < 132)) f_rgb = x[0] ? 24'hFF0055 : 24'h00FFAA;
            else begin
                r = x[7:0] ^ y[7:0];
                g = x[9:2] + y[8:1];
                b = x * 7 + y * 13;
                f_rgb = {r, g, b};
            end
        end
    endfunction

    wire [BW-1:0] cx;
    wire [BH-1:0] cy;
    integer       cuadro_dut = 0;               // cuadros del contador del transmisor
    always @(posedge clk_pixel) if (!reset && (cx == 0) && (cy == 0)) cuadro_dut = cuadro_dut + 1;

    wire [11:0] cx12 = cx;
    wire [11:0] cy12 = cy;
    wire [23:0] rgb_ahora = f_rgb(cx12, cy12)
                          ^ ((neg_pixel && (cx == 300) && (cy == 200) && (cuadro_dut == 2)) ? 24'h000100 : 24'h000000);
    reg  [23:0] rgb_reg = 24'd0;
    always @(posedge clk_pixel) rgb_reg <= rgb_ahora;       // la latencia que espera hdmi.sv
    wire [23:0] rgb_dut = neg_rgb_comb ? rgb_ahora : rgb_reg;

    // ------------------------------------------------------------------
    //  El transmisor
    // ------------------------------------------------------------------
    wire [9:0] tx0, tx1, tx2;
`ifdef HDMI_SIN_APLANAR
    // transmisor en SystemVerilog sin pasar por sv2v: matrices desempaquetadas
    wire [15:0] asw [1:0];
    assign asw[0] = smp_l;                      // [0] = izquierdo
    assign asw[1] = smp_r;
    wire [9:0] tmds_tx [2:0];
    assign tx0 = tmds_tx[0];
    assign tx1 = tmds_tx[1];
    assign tx2 = tmds_tx[2];
`else
    // con sv2v quedan aplanados: [0] en los bits bajos
    wire [31:0] asw = {smp_r, smp_l};           // [0] = izquierdo
    wire [29:0] tmds_tx;
    assign tx0 = tmds_tx[9:0];
    assign tx1 = tmds_tx[19:10];
    assign tx2 = tmds_tx[29:20];
`endif

    hdmi #(
        .VIDEO_ID_CODE      (VIC),
        .DVI_OUTPUT         (1'b0),
        .VIDEO_REFRESH_RATE (59.94),
        .IT_CONTENT         (1'b1),
        .AUDIO_RATE         (AUDIO_RATE),
        .AUDIO_BIT_WIDTH    (16)
    ) dut (
        .clk_pixel_x5      (1'b0),
        .clk_pixel         (clk_pixel),
        .clk_audio         (clk_audio_dut),
        .reset             (reset),
        .rgb               (rgb_dut),
        .audio_sample_word (asw),
        .aspect_16_9       (!neg_aspecto),
        .cx                (cx),
        .cy                (cy),
        .frame_width       (),
        .frame_height      (),
        .screen_width      (),
        .screen_height     (),
        .tmds_internal     (tmds_tx)
    );

    // ------------------------------------------------------------------
    //  El "cable": aqui se estropea algo en los controles negativos
    // ------------------------------------------------------------------
    reg  [29:0] mascara  = 30'd0;        // bits que se invierten en este caracter
    integer     ciclo    = 0;
    integer     n_inyec  = 0;
    // sustitucion de simbolos TERC4 por los de otro dato (simbolo valido, dato falso)
    reg  [3:0]  xo0, xo1, xo2;          // mascara sobre el dato de cada canal en este caracter
    reg         on0 = 1'b0, on1 = 1'b0, on2 = 1'b0;
    reg  [9:0]  sust0 = 10'd0, sust1 = 10'd0, sust2 = 10'd0;
    reg  [4:0]  dec;
    // alteracion de un bit de un paquete RECALCULANDO su BCH (+neg_dato_tipo)
    reg         dato_activo = 1'b0, dato_hecho = 1'b0;
    reg  [7:0]  dato_par;
    reg  [63:0] dato_e64;
    reg  [31:0] dato_e32;
    integer     dk;

    always @(negedge clk_pixel) begin
        ciclo   = ciclo + 1;
        mascara = 30'd0;
        xo0 = 4'd0; xo1 = 4'd0; xo2 = 4'd0;
        on0 = 1'b0; on1 = 1'b0; on2 = 1'b0;

        // un bit TMDS cada neg_tmds ciclos
        if (!reset && (neg_tmds > 0) && ((ciclo % neg_tmds) == 0)) begin
            mascara[(n_inyec * 7) % 30] = 1'b1;
            n_inyec = n_inyec + 1;
        end
        // un unico bit TMDS
        if (!reset && (neg_flip_cx >= 0) && (cx == neg_flip_cx) && (cy == neg_flip_cy) && (cuadro_dut == 2)) begin
            mascara[neg_flip_canal * 10 + neg_flip_bit] = 1'b1;
            n_inyec = n_inyec + 1;
        end
        // un dato TERC4 cambiado por otro (el BCH del paquete deja de casar)
        if (!reset && (neg_terc4_cx >= 0) && (cx == neg_terc4_cx) && (cy == neg_terc4_cy) && (cuadro_dut == 2)) begin
            case (neg_terc4_canal)
                0:       xo0 = neg_terc4_xor[3:0];
                1:       xo1 = neg_terc4_xor[3:0];
                default: xo2 = neg_terc4_xor[3:0];
            endcase
            n_inyec = n_inyec + 1;
        end
        // Un bit de un paquete cambiado Y su BCH recalculado: el paquete llega
        // "sano" al receptor y solo pueden cazarlo las comprobaciones de
        // contenido (checksum de InfoFrame, paridad IEC 60958, ACR repetido,
        // marca B). El codigo es lineal: invertir el bit i equivale a sumar
        // x^(n-1-i), y la paridad cambia en el resto de dividirlo entre G(x).
        // rx.estado/isla_k dicen que caracter va a muestrear el receptor en el
        // flanco que viene; con ocho caracteres ya se conoce el tipo (HB0).
        if (!reset && (neg_dato_tipo >= 0) && !dato_hecho && (cuadro_dut >= 2) && (rx.estado == rx.S_ISLA)) begin
            dk = rx.isla_k;
            if (!dato_activo && (dk == 8) && (rx.bch_h[7:0] == neg_dato_tipo[7:0])) begin
                dato_activo = 1'b1;
                if (neg_dato_sub == 4) begin
                    dato_e32 = 32'd0; dato_e32[neg_dato_bit] = 1'b1;
                    dato_par = rx.f_sind32(dato_e32);
                end
                else begin
                    dato_e64 = 64'd0; dato_e64[neg_dato_bit] = 1'b1;
                    dato_par = rx.f_sind64(dato_e64);
                end
            end
            if (dato_activo) begin
                if (neg_dato_sub == 4) begin
                    // cabecera: bit 2 del canal 0, un bit por caracter; paridad en 24..31
                    if (dk == neg_dato_bit) xo0[2] = 1'b1;
                    if ((dk >= 24) && dato_par[31 - dk]) xo0[2] = 1'b1;
                end
                else begin
                    // subpaquete: bit par en el canal 1, impar en el 2; paridad en 28..31
                    if (dk == neg_dato_bit / 2) begin
                        if ((neg_dato_bit % 2) == 0) xo1[neg_dato_sub] = 1'b1;
                        else                         xo2[neg_dato_sub] = 1'b1;
                    end
                    if (dk >= 28) begin
                        if (dato_par[7 - 2 * (dk - 28)]) xo1[neg_dato_sub] = 1'b1;
                        if (dato_par[6 - 2 * (dk - 28)]) xo2[neg_dato_sub] = 1'b1;
                    end
                end
                if (dk == 31) begin
                    dato_activo = 1'b0; dato_hecho = 1'b1;
                    n_inyec = n_inyec + 1;
                    $display("[tb] paquete de tipo %02h alterado con BCH coherente (bloque %0d, bit %0d)", neg_dato_tipo[7:0], neg_dato_sub, neg_dato_bit);
                end
            end
        end

        if (xo0 != 4'd0) begin
            dec = rx.f_terc4(tx0);
            if (dec[4]) begin sust0 = rx.tab_terc4[dec[3:0] ^ xo0]; on0 = 1'b1; end
            else $display("[tb] aviso: el simbolo que habia que cambiar en el canal 0 no es TERC4");
        end
        if (xo1 != 4'd0) begin
            dec = rx.f_terc4(tx1);
            if (dec[4]) begin sust1 = rx.tab_terc4[dec[3:0] ^ xo1]; on1 = 1'b1; end
            else $display("[tb] aviso: el simbolo que habia que cambiar en el canal 1 no es TERC4");
        end
        if (xo2 != 4'd0) begin
            dec = rx.f_terc4(tx2);
            if (dec[4]) begin sust2 = rx.tab_terc4[dec[3:0] ^ xo2]; on2 = 1'b1; end
            else $display("[tb] aviso: el simbolo que habia que cambiar en el canal 2 no es TERC4");
        end
    end

    wire [9:0] rx0 = on0 ? sust0 : (tx0 ^ mascara[9:0]);
    wire [9:0] rx1 = on1 ? sust1 : ((neg_cruce_tmds ? tx2 : tx1) ^ mascara[19:10]);
    wire [9:0] rx2 = on2 ? sust2 : ((neg_cruce_tmds ? tx1 : tx2) ^ mascara[29:20]);

    // ------------------------------------------------------------------
    //  El receptor
    // ------------------------------------------------------------------
    wire        rx_hsync, rx_vsync, rx_de, rx_en_cuadro, rx_nuevo_cuadro, rx_aud_valid;
    wire [3:0]  rx_ctl;
    wire [23:0] rx_rgb, rx_aud_l, rx_aud_r;
    wire [15:0] rx_px, rx_py;

    hdmi_rx_check #(.VERBOSE(VERBOSE), .ESTRICTO(ESTRICTO)) rx (
        .clk_pixel (clk_pixel), .rst (reset),
        .tmds0 (rx0), .tmds1 (rx1), .tmds2 (rx2),
        .hsync (rx_hsync), .vsync (rx_vsync), .ctl (rx_ctl),
        .de (rx_de), .rgb (rx_rgb), .px (rx_px), .py (rx_py), .en_cuadro (rx_en_cuadro),
        .nuevo_cuadro (rx_nuevo_cuadro),
        .aud_valid (rx_aud_valid), .aud_l (rx_aud_l), .aud_r (rx_aud_r)
    );

    // ------------------------------------------------------------------
    //  Comprobacion de pixeles
    // ------------------------------------------------------------------
    integer    fallos_tb = 0;
    integer    n_pix_ok  = 0;
    integer    n_pix_mal = 0;
    reg [23:0] esp_rgb;
    always @(posedge clk_pixel) if (rx_de && rx_en_cuadro) begin
        esp_rgb = f_rgb(rx_px[11:0], rx_py[11:0]);
        if (rx_rgb !== esp_rgb) begin
            n_pix_mal = n_pix_mal + 1;
            if (n_pix_mal <= 8)
                $display("[tb] PIXEL MAL en (%0d,%0d): recibido %06h, esperado %06h", rx_px, rx_py, rx_rgb, esp_rgb);
        end
        else n_pix_ok = n_pix_ok + 1;
    end

    // ------------------------------------------------------------------
    //  Comprobacion de audio: la muestra i recibida debe ser la k0+i enviada
    // ------------------------------------------------------------------
    integer    n_aud_rx  = 0;
    integer    n_aud_mal = 0;
    integer    k0        = -1;
    reg [23:0] esp_l, esp_r;
    always @(posedge clk_pixel) if (rx_aud_valid) begin
        if (n_aud_rx == 0) k0 = (rx_aud_l[23:8] - L0) & 16'hFFFF;
        esp_l = {seq_l(k0 + n_aud_rx), 8'h00};
        esp_r = {seq_r(k0 + n_aud_rx), 8'h00};
        if ((rx_aud_l !== esp_l) || (rx_aud_r !== esp_r)) begin
            n_aud_mal = n_aud_mal + 1;
            if (n_aud_mal <= 8)
                $display("[tb] AUDIO MAL en la muestra %0d: recibido L=%06h R=%06h, esperado L=%06h R=%06h",
                         n_aud_rx, rx_aud_l, rx_aud_r, esp_l, esp_r);
        end
        n_aud_rx = n_aud_rx + 1;
    end

    // ------------------------------------------------------------------
    //  Final
    // ------------------------------------------------------------------
    task tb_chk;
        input [8*60-1:0] nombre;
        input            ok;
        begin
            if (ok) $display("  [ ok  ] %0s", nombre);
            else begin
                $display("  [FALLO] %0s", nombre);
                fallos_tb = fallos_tb + 1;
            end
        end
    endtask

    integer fd, en_vuelo, total;
    reg     fin = 1'b0;
    integer media_x1000;

    task veredicto;
        begin
            $display("");
            rx.informe;
            $display("");
            rx.comprobar_geometria(858, 525, 720, 480, hfp_esp, 62, vfp_esp, 6, 1, 1);
            $display("Pixeles (latencia cx/cy -> rgb de un registro):");
            $display("          %0d pixeles comparados con f_rgb(x,y): %0d bien, %0d mal", n_pix_ok + n_pix_mal, n_pix_ok, n_pix_mal);
            tb_chk("todos los pixeles recibidos son f_rgb(x,y)", (n_pix_mal == 0) && (n_pix_ok > 0));
            tb_chk("numero de pixeles = cuadros x 720 x 480", (n_pix_ok + n_pix_mal) == rx.n_cuadros * 720 * 480);
            rx.comprobar_acr(6144, 27000, 0);
            $display("Audio (izquierdo = audio_sample_word[0], derecho = audio_sample_word[1]):");
            en_vuelo = n_lat - (k0 + n_aud_rx);
            $display("          enviadas %0d, recibidas %0d, la primera recibida es la numero %0d, en camino %0d, distintas %0d",
                     n_lat, n_aud_rx, k0, en_vuelo, n_aud_mal);
            tb_chk("se han recibido muestras", n_aud_rx > 0);
            tb_chk("la primera muestra recibida es de las 16 primeras enviadas", (k0 >= 0) && (k0 < 16));
            tb_chk("la secuencia recibida es exactamente la enviada (L y R)", (n_aud_mal == 0) && (n_aud_rx > 0));
            tb_chk("ninguna muestra se queda atras (0..12 en camino)", (en_vuelo >= 0) && (en_vuelo <= 12));
            tb_chk("la salida serie del receptor ha dado todas las muestras", (rx.aud_total - n_aud_rx >= 0) && (rx.aud_total - n_aud_rx <= 4));
            if (rx.g_n[rx.M_AUD] > 0) begin
                media_x1000 = (rx.g_sum[rx.M_AUD] * 1000) / rx.g_n[rx.M_AUD];
                $display("          muestras por cuadro: %0d..%0d, media %0d.%03d (ideal 48000 / 59,94 = 800,8)",
                         rx.g_min[rx.M_AUD], rx.g_max[rx.M_AUD], media_x1000 / 1000, media_x1000 % 1000);
                tb_chk("cada cuadro lleva 800,8 +/- 4 muestras", (rx.g_min[rx.M_AUD] >= 797) && (rx.g_max[rx.M_AUD] <= 804));
                // las muestras viajan de cuatro en cuatro: la media de n cuadros puede desviarse 4/n
                tb_chk("media de muestras por cuadro = 800,8 +/- 4/n",
                       ((media_x1000 - 800800) * rx.g_n[rx.M_AUD] <= 4000) && ((800800 - media_x1000) * rx.g_n[rx.M_AUD] <= 4000));
            end
            else tb_chk("hay medida de muestras por cuadro", 1'b0);
            rx.comprobar_estado_canal(48000, 16);
            rx.comprobar_avi(3, 2);
            rx.comprobar_aif;
            rx.comprobar_presencia;
            $display("Protocolo (BCH, checksums, paridades, preambulos, guardas, codigos TMDS):");
            tb_chk("ningun error de protocolo en el receptor", rx.n_err_total == 0);
            tb_chk("ningun paquete roto", (rx.n_pk_malos == 0) && (rx.n_pk_total > 0));
            tb_chk("cuadros completos recibidos", rx.n_cuadros >= cuadros);
            total = rx.n_err_total + rx.n_fallos_chk + fallos_tb;
            $display("");
            if (n_inyec > 0) $display("(control negativo: %0d simbolos TMDS alterados en el cable)", n_inyec);
            $display("RESUMEN: %0d cuadros completos; %0d errores de protocolo, %0d comprobaciones de formato falladas, %0d del banco",
                     rx.n_cuadros, rx.n_err_total, rx.n_fallos_chk, fallos_tb);
            if (total == 0) $display("RESULTADO: PASS");
            else            $display("RESULTADO: FAIL (%0d)", total);
        end
    endtask

    always @(negedge clk_pixel) if (!fin) begin
        if (rx.n_cuadros >= cuadros) begin
            fin = 1'b1;
            if (ppm_pedido) begin
                fd = $fopen(ppm_nombre, "w");
                rx.escribir_ppm(fd);
                $fclose(fd);
                $display("[tb] ultimo cuadro escrito en %0s", ppm_nombre);
            end
            repeat (8) @(negedge clk_pixel);
            veredicto;
            $finish;
        end
        else if (ciclo > (cuadros + 2) * 600000) begin
            fin = 1'b1;
            $display("[tb] TIEMPO AGOTADO: %0d cuadros completos de %0d tras %0d ciclos de pixel", rx.n_cuadros, cuadros, ciclo);
            fallos_tb = fallos_tb + 1;
            veredicto;
            $finish;
        end
    end

endmodule
