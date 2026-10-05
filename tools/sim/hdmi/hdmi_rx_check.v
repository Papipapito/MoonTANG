// ============================================================================
// hdmi_rx_check.v -- RECEPTOR HDMI DE VERIFICACION (solo simulacion)
//
// Que es: un sumidero HDMI escrito desde la especificacion (HDMI 1.4 cap. 5,
// DVI 1.0 cap. 3, CEA-861-D, IEC 60958-1/-3), SIN reutilizar nada del
// transmisor. Recibe los tres simbolos TMDS de 10 bits (uno por ciclo de
// pixel, antes del serializador), reconstruye sincronismos, video, islas de
// datos, paquetes y audio, comprueba todo lo que el estandar permite comprobar
// sin conocer el formato, y MIDE la geometria. El banco decide luego si lo
// medido es lo que esperaba (tareas comprobar_*).
//
// ---------------------------------------------------------------------------
// INTERFAZ
//   clk_pixel         reloj de pixel; se muestrea en el flanco de subida
//   rst               1 = receptor parado y a cero (tenerlo a 1 mientras dure
//                     el reset del transmisor)
//   tmds0/1/2 [9:0]   simbolo de cada canal TMDS. Bit 0 = el primero que sale
//                     por el cable; bit 9 = el ultimo (q_out[9:0] del estandar).
//                     Canal 0 = azul + HSYNC/VSYNC, 1 = verde + CTL0/1,
//                     2 = rojo + CTL2/3.
//   Salidas (registradas, validas el ciclo siguiente al del simbolo):
//   hsync, vsync      niveles tal como viajan (sin normalizar la polaridad)
//   ctl[3:0]          CTL3..CTL0 del ultimo caracter de control
//   de                1 = rgb/px/py llevan un pixel de video
//   rgb[23:0]         {R = canal 2, G = canal 1, B = canal 0}
//   px, py            columna dentro del periodo de video y numero de linea
//                     activa dentro del cuadro (0 = primera tras el vsync)
//   en_cuadro         1 = el pixel pertenece a un cuadro abierto en un flanco
//                     de entrada de vsync (los pixeles previos al primer vsync
//                     no tienen py fiable)
//   nuevo_cuadro      pulso de un ciclo en cada flanco de entrada de vsync
//   aud_valid, aud_l, aud_r   muestras de audio en orden, una por ciclo
//                     (24 bits, justificadas a la izquierda: 16 bits = [23:8])
//
// PARAMETROS
//   VERBOSE   0 = solo errores; 1 = + una linea por cuadro; 2 = + cada paquete
//             que no sea nulo ni de audio; 3 = + todos los paquetes
//   MAX_MSG   mensajes que se imprimen de CADA clase de error o aviso (los
//             contadores siguen contando)
//   ESTRICTO  1 = las dos desviaciones del estandar que un televisor suele
//             tolerar cuentan como ERROR; 0 = solo como AVISO (el banco puede
//             cambiarlo en marcha con "rx.estricto = 0;" tras el instante 0):
//               - periodo de control de menos de 12 caracteres (HDMI 1.4
//                 5.2.1.1 / tabla 5-3, tS,min)
//               - preambulo + banda de guarda de video sin pixeles detras
//   AUD_LOG2  la cola de audio guarda 2^AUD_LOG2 muestras (circular)
//   FB_LOG2   pixeles del framebuffer para escribir_ppm (2^FB_LOG2)
//
// COMO CONECTARLO A UN DISENO ENTERO (referencia jerarquica)
//   Con sv2v el puerto "logic [9:0] tmds_internal [2:0]" queda aplanado en un
//   vector de 30 bits, canal i en [i*10 +: 10]:
//     hdmi_rx_check rx (.clk_pixel(tb.dut.clk_pixel), .rst(tb.dut.hdmi_reset),
//         .tmds0(tb.dut.u_hdmi.tmds_internal[ 9: 0]),
//         .tmds1(tb.dut.u_hdmi.tmds_internal[19:10]),
//         .tmds2(tb.dut.u_hdmi.tmds_internal[29:20]), ...salidas sin conectar);
//   Sin aplanar (SystemVerilog directo): tmds_internal[0], [1] y [2].
//   Y en el banco, cuando haya pasado lo que se quiera mirar:
//     wait (rx.n_cuadros >= 2);            // cuadros completos (vsync a vsync)
//     rx.informe;
//     rx.comprobar_geometria(858, 525, 720, 480, 16, 62, 9, 6, 1, 1);
//     rx.comprobar_acr(6144, 27000, 1);    // +/-1 si los relojes no van atados
//     rx.comprobar_estado_canal(48000, 16);
//     rx.comprobar_avi(3, 2);  rx.comprobar_aif;  rx.comprobar_presencia;
//     fallos = rx.n_err_total + rx.n_fallos_chk;
//   Las muestras salen por aud_valid/aud_l/aud_r (o se leen de rx.q_l[i],
//   rx.q_r[i] con i < rx.aud_total) y los pixeles por de/rgb/px/py.
//   Ojo 1: el transmisor hdl-util lleva 8'dX en las cabeceras de los paquetes
//   nulos y ACR salvo que se compile con MODEL_TECH definido (sv2v
//   -DMODEL_TECH); en un simulador de 4 estados esas X llegan aqui y cuentan
//   en n_err_x.
//   Ojo 2: el primer ACR tras el arranque lleva un CTS corto (el transmisor
//   mide desde el instante 0); cae antes del primer cuadro completo y por eso
//   no entra en M_CTS, pero si en acr_cts_primero / acr_cts_min.
//
// LO QUE COMPRUEBA EL SOLO (contadores n_err_*; n_err_total los suma)
//   n_err_x          simbolos con X o Z
//   n_err_sim        simbolo que no pertenece al periodo en curso (ni control,
//                    ni banda de guarda) o canales en desacuerdo
//   n_err_preamb     banda de guarda sin su preambulo de 8 caracteres exactos,
//                    o preambulo que no acaba en banda de guarda
//   n_err_guarda     banda de guarda de longitud distinta de 2
//   n_err_vcod       codigo TMDS de video imposible (bit 8 no casa con la
//                    regla de minimizacion de transiciones, DVI 1.0 fig. 3-5)
//   n_err_vdc        bit 9 distinto del que exige la disparidad acumulada
//   n_err_terc4      simbolo no TERC4 dentro de una isla
//   n_err_isla       isla sin paquetes, de mas de 18, o cortada a medio paquete
//   n_err_bch_cab    BCH(32,24) de la cabecera
//   n_err_bch_sub    BCH(64,56) de un subpaquete
//   n_err_chk_if     checksum de InfoFrame
//   n_err_par        paridad IEC 60958 de una muestra de audio
//   n_err_acr        subpaquetes de un ACR distintos entre si
//   n_err_ctrl_ext   cuadro sin ningun periodo de control extendido (>= 32)
//   n_err_ctl        CTL3..0 distinto de 0000 y de los dos preambulos (sin HDCP
//                    el transmisor no debe enviar otra cosa)
//   n_ctrl_corto, n_video_vacio   (error si ESTRICTO, aviso si no)
//   Avisos (no suman en n_err_total; comprobar_estado_canal exige que los dos
//   de audio valgan 0): n_av_pk_desc (tipo de paquete desconocido),
//   n_av_bloque (bloque IEC 60958 que no mide 192 tramas), n_av_cs_cambia
//   (estado de canal distinto entre bloques), n_av_if (version o longitud de
//   InfoFrame inesperadas), n_av_asp (cabecera de paquete de audio rara).
//   Informativo: n_d3_primero_0/1 = islas cuyo primer caracter lleva el bit 3
//   del canal 0 a 0 / a 1. Hay transmisores que lo ponen a 0 solo en ese
//   primer caracter y a 1 en el resto; no he podido contrastarlo con el texto
//   de la norma y por eso ni suma ni avisa.
//
// LO QUE MIDE (matrices g_min[], g_max[], g_n[], g_sum[], indice M_*)
//   Solo acumula dentro de CUADROS COMPLETOS: de flanco de entrada de vsync a
//   flanco de entrada de vsync. n_cuadros = cuadros completos acumulados.
//   Unidades: ciclos de pixel en horizontal, lineas en vertical. Definiciones
//   (CEA-861-D, la linea empieza en el flanco de entrada de hsync):
//     M_HTOT  periodo de hsync        M_HSW  anchura del pulso de hsync
//     M_HFP   del fin del video al flanco de entrada de hsync
//     M_HBP   del flanco de salida de hsync al primer pixel
//     M_HACT  pixeles por linea activa
//     M_VTOT  lineas por cuadro       M_VACT lineas con video
//     M_VSW   anchura de vsync        M_VFP  lineas enteras entre el hsync que
//             sigue a la ultima linea activa y el flanco de entrada de vsync
//     M_VBP   lineas enteras entre el flanco de salida de vsync y el hsync que
//             abre la primera linea activa
//     M_VSW_R, M_VFP_R, M_VBP_R   restos en pixeles de las tres anteriores
//     M_VS_OFF  pixeles del flanco de entrada de vsync al de hsync (0 = juntos)
//     M_FCLK  ciclos de pixel por cuadro
//     M_AUD   muestras de audio por cuadro      M_CTS, M_N  de cada ACR
//     M_CTRL  longitud de cada periodo de control
//     M_ISLA  paquetes por isla       M_ISLAS  islas por cuadro
//     M_PK_*  paquetes por cuadro de cada tipo
//   Polaridad: hs_neg / vs_neg (1 = pulso a nivel bajo), hs_fijada/vs_fijada.
//   Desde la sincronizacion, sin esperar a cuadros completos: n_pk_* (paquetes
//   por tipo), n_acr, acr_n, acr_cts, acr_cts_primero, acr_cts_min/max,
//   aud_total y la cola q_l[], q_r[], q_f[] (indice = numero de muestra modulo
//   2^AUD_LOG2; q_f = {B, PR,CR,UR,VR, PL,CL,UL,VL}), cs_l_ult/cs_r_ult
//   (192 bits de estado de canal del ultimo bloque completo), n_bloques_cs,
//   avi_*, aif_*, spd_*, ult_pk[] (ultimo paquete de cada tipo: 3 bytes de
//   cabecera + 28 de cuerpo en ult_pk[tipo*32 + i]) y n_tipo[].
//
// TAREAS PARA EL BANCO (suman en n_fallos_chk e imprimen [ ok ] / [FALLO])
//   informe;                                     resumen de todo lo medido
//   comprobar_geometria(htot, vtot, hact, vact, hfp, hsw, vfp, vsw,
//                       hs_negativa, vs_negativa);
//   comprobar_acr(n, cts, tolerancia_cts);
//   comprobar_estado_canal(fs_hz, bits);   (y validez, muestra plana, layout)
//   comprobar_avi(vic, aspecto);     aspecto: 1 = 4:3, 2 = 16:9 (campo M)
//   comprobar_aif;                   Audio InfoFrame presente y coherente
//   comprobar_presencia;             AVI, Audio IF, ACR y audio en todos los
//                                    cuadros, y ningun Set_AVMUTE
//   escribir_ppm(fd);                ultimo cuadro completo en PPM de texto
//                                    (llamar cuando n_cuadros acaba de subir,
//                                    antes de la primera linea activa del
//                                    cuadro siguiente; ppm2png.py lo pasa a PNG)
//
// LIMITES: solo audio de 2 canales (layout 0); no corrige errores con el BCH,
// solo los detecta; no mira DDC/EDID/HPD ni nada electrico; no deserializa (se
// conecta antes del serializador).
// ============================================================================
`timescale 1ns/1ps

module hdmi_rx_check #(
    parameter integer VERBOSE  = 1,
    parameter integer MAX_MSG  = 4,
    parameter integer ESTRICTO = 1,
    parameter integer AUD_LOG2 = 16,
    parameter integer FB_LOG2  = 20
) (
    input  wire        clk_pixel,
    input  wire        rst,
    input  wire [9:0]  tmds0,
    input  wire [9:0]  tmds1,
    input  wire [9:0]  tmds2,
    output reg         hsync,
    output reg         vsync,
    output reg  [3:0]  ctl,
    output reg         de,
    output reg  [23:0] rgb,
    output reg  [15:0] px,
    output reg  [15:0] py,
    output reg         en_cuadro,
    output reg         nuevo_cuadro,
    output reg         aud_valid,
    output reg  [23:0] aud_l,
    output reg  [23:0] aud_r
);

    // ------------------------------------------------------------------
    //  Simbolos del estandar
    // ------------------------------------------------------------------
    // HDMI 1.4 5.4.2: periodo de control, {D1,D0} -> simbolo
    localparam [9:0] SIM_CTRL_00 = 10'b1101010100;
    localparam [9:0] SIM_CTRL_01 = 10'b0010101011;
    localparam [9:0] SIM_CTRL_10 = 10'b0101010100;
    localparam [9:0] SIM_CTRL_11 = 10'b1010101011;
    // HDMI 1.4 5.2.2.1: banda de guarda de video (canales 0 y 2 / canal 1)
    localparam [9:0] GB_VIDEO_C02 = 10'b1011001100;
    localparam [9:0] GB_VIDEO_C1  = 10'b0100110011;
    // HDMI 1.4 5.2.3.3: banda de guarda de isla en los canales 1 y 2 (el
    // canal 0 lleva TERC4 de {1,1,VSYNC,HSYNC})
    localparam [9:0] GB_ISLA_C12  = 10'b0100110011;

    // estados del receptor
    localparam integer S_BUSCA = 0;   // sin sincronizar: espera un caracter de control
    localparam integer S_CTRL  = 1;   // periodo de control
    localparam integer S_VGB   = 2;   // banda de guarda de video
    localparam integer S_VIDEO = 3;   // periodo de datos de video
    localparam integer S_DGB_I = 4;   // banda de guarda inicial de isla
    localparam integer S_ISLA  = 5;   // paquetes
    localparam integer S_DGB_F = 6;   // banda de guarda final de isla

    // indices de las medidas
    localparam integer M_HTOT    = 0;
    localparam integer M_HSW     = 1;
    localparam integer M_HFP     = 2;
    localparam integer M_HBP     = 3;
    localparam integer M_HACT    = 4;
    localparam integer M_VTOT    = 5;
    localparam integer M_VACT    = 6;
    localparam integer M_VSW     = 7;
    localparam integer M_VSW_R   = 8;
    localparam integer M_VFP     = 9;
    localparam integer M_VFP_R   = 10;
    localparam integer M_VBP     = 11;
    localparam integer M_VBP_R   = 12;
    localparam integer M_VS_OFF  = 13;
    localparam integer M_FCLK    = 14;
    localparam integer M_AUD     = 15;
    localparam integer M_CTS     = 16;
    localparam integer M_N       = 17;
    localparam integer M_CTRL    = 18;
    localparam integer M_ISLA    = 19;
    localparam integer M_ISLAS   = 20;
    localparam integer M_PK_TOT  = 21;
    localparam integer M_PK_NULO = 22;
    localparam integer M_PK_ACR  = 23;
    localparam integer M_PK_ASP  = 24;
    localparam integer M_PK_AVI  = 25;
    localparam integer M_PK_AIF  = 26;
    localparam integer M_PK_SPD  = 27;
    localparam integer M_PK_OTRO = 28;
    localparam integer NM        = 29;

    localparam integer AUD_N = (1 << AUD_LOG2);
    localparam integer FB_N  = (1 << FB_LOG2);

    // ------------------------------------------------------------------
    //  Decodificadores (funciones puras)
    // ------------------------------------------------------------------
    // caracter de control -> {valido, D1, D0}
    function [2:0] f_ctrl;
        input [9:0] s;
        begin
            case (s)
                SIM_CTRL_00: f_ctrl = 3'b100;
                SIM_CTRL_01: f_ctrl = 3'b101;
                SIM_CTRL_10: f_ctrl = 3'b110;
                SIM_CTRL_11: f_ctrl = 3'b111;
                default:     f_ctrl = 3'b000;
            endcase
        end
    endfunction

    // TERC4 (HDMI 1.4 5.4.3) -> {valido, D3..D0}
    function [4:0] f_terc4;
        input [9:0] s;
        begin
            case (s)
                10'b1010011100: f_terc4 = 5'h10;
                10'b1001100011: f_terc4 = 5'h11;
                10'b1011100100: f_terc4 = 5'h12;
                10'b1011100010: f_terc4 = 5'h13;
                10'b0101110001: f_terc4 = 5'h14;
                10'b0100011110: f_terc4 = 5'h15;
                10'b0110001110: f_terc4 = 5'h16;
                10'b0100111100: f_terc4 = 5'h17;
                10'b1011001100: f_terc4 = 5'h18;
                10'b0100111001: f_terc4 = 5'h19;
                10'b0110011100: f_terc4 = 5'h1A;
                10'b1011000110: f_terc4 = 5'h1B;
                10'b1010001110: f_terc4 = 5'h1C;
                10'b1001110001: f_terc4 = 5'h1D;
                10'b0101100011: f_terc4 = 5'h1E;
                10'b1011000011: f_terc4 = 5'h1F;
                default:        f_terc4 = 5'h00;
            endcase
        end
    endfunction

    function integer f_unos8;
        input [7:0] v;
        integer i;
        begin
            f_unos8 = 0;
            for (i = 0; i < 8; i = i + 1) if (v[i]) f_unos8 = f_unos8 + 1;
        end
    endfunction

    function integer f_unos10;
        input [9:0] v;
        integer i;
        begin
            f_unos10 = 0;
            for (i = 0; i < 10; i = i + 1) if (v[i]) f_unos10 = f_unos10 + 1;
        end
    endfunction

    // Sindrome BCH (HDMI 1.4 5.2.3.5): resto de dividir la palabra recibida
    // entre G(x) = x^8 + x^7 + x^6 + 1. c[0] es el primer bit recibido y por
    // tanto el coeficiente de mayor grado. Palabra valida <=> resto 0.
    function [7:0] f_sind64;
        input [63:0] c;
        integer i;
        reg [8:0] r;
        begin
            r = 9'd0;
            for (i = 0; i < 64; i = i + 1) begin
                r = {r[7:0], c[i]};
                if (r[8]) r = r ^ 9'h1C1;
            end
            f_sind64 = r[7:0];
        end
    endfunction

    function [7:0] f_sind32;
        input [31:0] c;
        integer i;
        reg [8:0] r;
        begin
            r = 9'd0;
            for (i = 0; i < 32; i = i + 1) begin
                r = {r[7:0], c[i]};
                if (r[8]) r = r ^ 9'h1C1;
            end
            f_sind32 = r[7:0];
        end
    endfunction

    // bits de palabra de audio segun el estado de canal (IEC 60958-3, bits 32..35)
    function integer f_bits_cs;
        input [3:0] c;      // {bit35, bit34, bit33, bit32}
        begin
            case (c)
                4'b0010: f_bits_cs = 16;
                4'b0100: f_bits_cs = 18;
                4'b1000: f_bits_cs = 19;
                4'b1010: f_bits_cs = 20;
                4'b1100: f_bits_cs = 17;
                4'b0011: f_bits_cs = 20;
                4'b0101: f_bits_cs = 22;
                4'b1001: f_bits_cs = 23;
                4'b1011: f_bits_cs = 24;
                4'b1101: f_bits_cs = 21;
                default: f_bits_cs = 0;      // no indicado
            endcase
        end
    endfunction

    // frecuencia de muestreo segun el estado de canal (bits 24..27)
    function integer f_fs_cs;
        input [3:0] c;      // {bit27, bit26, bit25, bit24}
        begin
            case (c)
                4'b0000: f_fs_cs = 44100;
                4'b0010: f_fs_cs = 48000;
                4'b0011: f_fs_cs = 32000;
                4'b1000: f_fs_cs = 88200;
                4'b1010: f_fs_cs = 96000;
                4'b1100: f_fs_cs = 176400;
                4'b1110: f_fs_cs = 192000;
                default: f_fs_cs = 0;
            endcase
        end
    endfunction

    // ------------------------------------------------------------------
    //  Estado
    // ------------------------------------------------------------------
    integer estado;
    integer t;                      // indice del caracter en curso
    reg     en_reset;
    reg     sincronizado;

    // contadores de errores y avisos
    integer n_err_total, n_err_x, n_err_sim, n_err_preamb, n_err_guarda;
    integer n_err_vcod, n_err_vdc, n_err_terc4, n_err_isla;
    integer n_err_bch_cab, n_err_bch_sub, n_err_chk_if, n_err_par, n_err_acr;
    integer n_err_ctrl_ext, n_err_ctl;
    integer n_ctrl_corto, n_video_vacio;
    integer n_av_pk_desc, n_av_bloque, n_av_cs_cambia, n_av_if, n_av_asp;
    integer n_d3_primero_0, n_d3_primero_1, n_d3_resto_0;
    integer n_msg;
    reg     ver;
    integer n_fallos_chk;
    integer estricto;               // copia de ESTRICTO que el banco puede cambiar (rx.estricto = 0)

    // periodo de control
    integer ctrl_len, pre_v, pre_d;
    reg     ctrl_len_valida;
    integer gb_cnt;

    // video
    integer vid_n;
    integer disp0, disp1, disp2;
    integer n_pix_total;

    // isla
    integer isla_k, isla_pk;
    reg [31:0] bch_h;
    reg [63:0] bch_s0, bch_s1, bch_s2, bch_s3;

    // sincronismos
    reg     sy_valido, hs_lvl, vs_lvl;
    integer p_n  [0:1];
    integer p_t  [0:1];
    integer p_d  [0:1];
    integer p_lb [0:1];
    reg     p_fij [0:1];
    reg     p_act [0:1];
    reg     e_lead, e_trail, e_malo;
    reg     hs_fijada, vs_fijada, hs_neg, vs_neg;

    integer t_hs_lead, t_hs_trail, h_per;
    integer t_de_fin;
    reg     pend_hfp, hbp_listo, lin_video;
    integer lin_cnt;
    integer t_vs_lead, t_vs_trail, t_vfp0;
    reg     pend_vbp;
    reg     cuadro_abierto, cuadro_valido;
    integer n_cuadros;              // cuadros completos acumulados
    integer n_vs;                   // flancos de entrada de vsync vistos
    integer f_vact, f_aud, f_islas;
    integer f_pk [0:7];             // paquetes del cuadro: 0 total, 1 nulo, 2 ACR, 3 audio, 4 AVI, 5 AIF, 6 SPD, 7 otros

    // medidas
    integer f_min [0:NM-1], f_max [0:NM-1], f_n [0:NM-1], f_sum [0:NM-1];
    integer g_min [0:NM-1], g_max [0:NM-1], g_n [0:NM-1], g_sum [0:NM-1];
    integer u_min [0:NM-1], u_max [0:NM-1], u_n [0:NM-1];

    // paquetes
    integer n_pk_total, n_pk_malos, n_pk_nulo, n_pk_acr, n_pk_asp, n_pk_avi, n_pk_aif, n_pk_spd, n_pk_gcp, n_pk_otro;
    integer n_islas;
    integer n_tipo [0:255];
    reg [7:0] ult_pk [0:256*32-1];
    reg [7:0] hb0, hb1, hb2;
    reg [7:0] pb [0:27];

    // ACR
    integer n_acr, acr_n, acr_cts, acr_cts_primero, acr_cts_min, acr_cts_max;

    // audio
    integer aud_total, aud_rd;
    reg [23:0] q_l [0:AUD_N-1];
    reg [23:0] q_r [0:AUD_N-1];
    reg [8:0]  q_f [0:AUD_N-1];
    integer n_aud_v1, n_aud_u1, n_aud_plano, n_asp_incompleto;
    integer cs_idx, n_bloques_cs;
    reg [191:0] cs_l, cs_r, cs_l_ult, cs_r_ult;

    // InfoFrames
    integer avi_n, avi_ver, avi_len, avi_vic, avi_m, avi_y, avi_a, avi_r, avi_itc, avi_q, avi_pr, avi_c, avi_s;
    integer aif_n, aif_ver, aif_len, aif_ct, aif_cc, aif_sf, aif_ss, aif_ca, aif_lsv, aif_dm;
    integer spd_n, spd_sdi;
    reg [63:0]  spd_vendor;
    reg [127:0] spd_producto;
    integer gcp_avmute_set, gcp_avmute_clr;

    // framebuffer
    reg [23:0] fb [0:FB_N-1];
    integer fb_idx, fb_n_ult, fb_w_ult;

    // temporales del proceso principal
    reg [9:0] s0, s1, s2;
    reg [2:0] c0, c1, c2;
    reg [4:0] q0, q1, q2;
    reg       es_x, todo_ctrl, algun_ctrl, es_gb_video, es_gb_isla, repetir;
    reg [3:0] ctl_v;
    reg [7:0] d0, d1, d2;
    reg       ec0, ec1, ec2, ed0, ed1, ed2;

    // ------------------------------------------------------------------
    //  Mensajes
    // ------------------------------------------------------------------
    task pos;
        begin
            $write("[hdmi_rx] t=%0d cuadro=%0d linea=%0d col=%0d: ", t, n_vs, lin_cnt,
                   (t_hs_lead >= 0) ? (t - t_hs_lead) : -1);
        end
    endtask

    task limite;        // decide si este mensaje se imprime: MAX_MSG por clase de error
        input integer n;    // veces que ha ocurrido ya (contando esta)
        begin
            ver = (n <= MAX_MSG);
            n_msg = n_msg + 1;
        end
    endtask

    task e_cnt;         // error
        input integer n;
        begin
            n_err_total = n_err_total + 1;
            limite(n);
            if (ver) begin
                pos;
                if (n == MAX_MSG) $write("ERROR (y no se avisa mas de esta clase): ");
                else              $write("ERROR: ");
            end
        end
    endtask

    task a_cnt;         // aviso
        input integer n;
        begin
            limite(n);
            if (ver) begin
                pos;
                if (n == MAX_MSG) $write("aviso (y no se avisa mas de esta clase): ");
                else              $write("aviso: ");
            end
        end
    endtask

    task ea_cnt;        // error en modo estricto, aviso si no
        input integer n;
        begin
            if (estricto != 0) e_cnt(n); else a_cnt(n);
        end
    endtask

    // ------------------------------------------------------------------
    //  Medidas
    // ------------------------------------------------------------------
    task facum;
        input integer i;
        input integer v;
        begin
            if (f_n[i] == 0) begin f_min[i] = v; f_max[i] = v; end
            else begin
                if (v < f_min[i]) f_min[i] = v;
                if (v > f_max[i]) f_max[i] = v;
            end
            f_n[i]   = f_n[i] + 1;
            f_sum[i] = f_sum[i] + v;
        end
    endtask

    task f_borra;
        integer i;
        begin
            for (i = 0; i < NM; i = i + 1) begin f_min[i] = 0; f_max[i] = 0; f_n[i] = 0; f_sum[i] = 0; end
            for (i = 0; i < 8; i = i + 1) f_pk[i] = 0;
            f_vact = 0; f_aud = 0; f_islas = 0;
        end
    endtask

    task f_vuelca;      // el cuadro que se cierra pasa a las medidas globales
        integer i;
        begin
            for (i = 0; i < NM; i = i + 1) begin
                u_min[i] = f_min[i]; u_max[i] = f_max[i]; u_n[i] = f_n[i];
                if (f_n[i] != 0) begin
                    if (g_n[i] == 0) begin g_min[i] = f_min[i]; g_max[i] = f_max[i]; end
                    else begin
                        if (f_min[i] < g_min[i]) g_min[i] = f_min[i];
                        if (f_max[i] > g_max[i]) g_max[i] = f_max[i];
                    end
                    g_n[i]   = g_n[i] + f_n[i];
                    g_sum[i] = g_sum[i] + f_sum[i];
                end
            end
        end
    endtask

    // ------------------------------------------------------------------
    //  Puesta a cero
    // ------------------------------------------------------------------
    task reinicia;
        integer i;
        begin
            estado = S_BUSCA; t = 0; sincronizado = 1'b0;
            n_err_total = 0; n_err_x = 0; n_err_sim = 0; n_err_preamb = 0; n_err_guarda = 0;
            n_err_vcod = 0; n_err_vdc = 0; n_err_terc4 = 0; n_err_isla = 0;
            n_err_bch_cab = 0; n_err_bch_sub = 0; n_err_chk_if = 0; n_err_par = 0; n_err_acr = 0;
            n_err_ctrl_ext = 0; n_err_ctl = 0; n_ctrl_corto = 0; n_video_vacio = 0;
            n_av_pk_desc = 0; n_av_bloque = 0; n_av_cs_cambia = 0; n_av_if = 0; n_av_asp = 0;
            n_d3_primero_0 = 0; n_d3_primero_1 = 0; n_d3_resto_0 = 0;
            n_msg = 0; ver = 1'b0; n_fallos_chk = 0;
            ctrl_len = 0; pre_v = 0; pre_d = 0; ctrl_len_valida = 1'b0; gb_cnt = 0;
            vid_n = 0; disp0 = 0; disp1 = 0; disp2 = 0; n_pix_total = 0;
            isla_k = 0; isla_pk = 0; bch_h = 32'd0; bch_s0 = 64'd0; bch_s1 = 64'd0; bch_s2 = 64'd0; bch_s3 = 64'd0;
            sy_valido = 1'b0; hs_lvl = 1'b0; vs_lvl = 1'b0;
            for (i = 0; i < 2; i = i + 1) begin
                p_n[i] = 0; p_t[i] = 0; p_d[i] = 0; p_lb[i] = 0; p_fij[i] = 1'b0; p_act[i] = 1'b0;
            end
            e_lead = 1'b0; e_trail = 1'b0; e_malo = 1'b0;
            hs_fijada = 1'b0; vs_fijada = 1'b0; hs_neg = 1'b0; vs_neg = 1'b0;
            t_hs_lead = -1; t_hs_trail = -1; h_per = 0; t_de_fin = -1;
            pend_hfp = 1'b0; hbp_listo = 1'b0; lin_video = 1'b0; lin_cnt = 0;
            t_vs_lead = -1; t_vs_trail = -1; t_vfp0 = -1; pend_vbp = 1'b0;
            cuadro_abierto = 1'b0; cuadro_valido = 1'b0; n_cuadros = 0; n_vs = 0;
            f_borra;
            for (i = 0; i < NM; i = i + 1) begin
                g_min[i] = 0; g_max[i] = 0; g_n[i] = 0; g_sum[i] = 0;
                u_min[i] = 0; u_max[i] = 0; u_n[i] = 0;
            end
            n_pk_total = 0; n_pk_malos = 0; n_pk_nulo = 0; n_pk_acr = 0; n_pk_asp = 0; n_pk_avi = 0;
            n_pk_aif = 0; n_pk_spd = 0; n_pk_gcp = 0; n_pk_otro = 0; n_islas = 0;
            for (i = 0; i < 256; i = i + 1) n_tipo[i] = 0;
            n_acr = 0; acr_n = -1; acr_cts = -1; acr_cts_primero = -1; acr_cts_min = 0; acr_cts_max = 0;
            aud_total = 0; aud_rd = 0;
            n_aud_v1 = 0; n_aud_u1 = 0; n_aud_plano = 0; n_asp_incompleto = 0;
            cs_idx = -1; n_bloques_cs = 0; cs_l = 192'd0; cs_r = 192'd0; cs_l_ult = 192'd0; cs_r_ult = 192'd0;
            avi_n = 0; avi_ver = -1; avi_len = -1; avi_vic = -1; avi_m = -1; avi_y = -1; avi_a = -1; avi_r = -1;
            avi_itc = -1; avi_q = -1; avi_pr = -1; avi_c = -1; avi_s = -1;
            aif_n = 0; aif_ver = -1; aif_len = -1; aif_ct = -1; aif_cc = -1; aif_sf = -1; aif_ss = -1;
            aif_ca = -1; aif_lsv = -1; aif_dm = -1;
            spd_n = 0; spd_sdi = -1; spd_vendor = 64'd0; spd_producto = 128'd0;
            gcp_avmute_set = 0; gcp_avmute_clr = 0;
            fb_idx = 0; fb_n_ult = 0; fb_w_ult = 0;
        end
    endtask

    // ------------------------------------------------------------------
    //  Video: decodificacion TMDS 8b/10b y comprobacion de la palabra
    //  (DVI 1.0 3.3.3 y fig. 3-5 / 3-6; HDMI 1.4 5.4.4)
    // ------------------------------------------------------------------
    task dec_video;
        input  [9:0]   s;
        input  integer disp;        // disparidad acumulada antes de este caracter
        output [7:0]   d;
        output integer disp_n;
        output         e_cod;
        output         e_dc;
        reg [7:0] q;                // q_m[7:0]
        reg [6:0] x;
        reg [7:0] dd;
        reg       esp8, esp9;
        integer   n1d, n1q, n1s;
        begin
            q   = s[9] ? ~s[7:0] : s[7:0];
            // D[0] = q[0]; D[i] = q[i] XOR q[i-1] si el bit 8 vale 1, XNOR si vale 0
            x   = q[7:1] ^ q[6:0];
            dd  = {s[8] ? x : ~x, q[0]};
            n1d = dd[0] + dd[1] + dd[2] + dd[3] + dd[4] + dd[5] + dd[6] + dd[7];
            n1q = q[0] + q[1] + q[2] + q[3] + q[4] + q[5] + q[6] + q[7];
            n1s = n1q + (s[9] ? 8 - 2 * n1q : 0) + s[8] + s[9];     // unos de los diez bits
            // etapa 1: se codifica con XNOR (bit 8 = 0) si el dato tiene mas de
            // cuatro unos, o exactamente cuatro y el bit 0 a cero
            esp8  = !((n1d > 4) || ((n1d == 4) && (dd[0] == 1'b0)));
            e_cod = (s[8] !== esp8);
            // etapa 2: el bit 9 (inversion) depende de la disparidad acumulada
            if ((disp == 0) || (n1q == 4))                           esp9 = ~s[8];
            else if (((disp > 0) && (n1q > 4)) || ((disp < 0) && (n1q < 4))) esp9 = 1'b1;
            else                                                     esp9 = 1'b0;
            e_dc   = (s[9] !== esp9);
            // la disparidad acumulada es, sin mas, unos menos ceros de lo enviado
            disp_n = disp + 2 * n1s - 10;
            d      = dd;
        end
    endtask

    // ------------------------------------------------------------------
    //  Sincronismos: polaridad, flancos y geometria
    // ------------------------------------------------------------------
    // Polaridad: el pulso es la fase corta. Se fija en el 2o flanco si la fase
    // que acaba es mas corta que lo observado antes del 1o, y si no en el 3o.
    // Hasta entonces los flancos impares se toman, provisionalmente, por
    // flancos de entrada; e_malo avisa de que la suposicion era falsa.
    task pol;
        input integer i;
        input         nl;           // nivel nuevo
        integer d;
        reg     tent;
        begin
            d = t - p_t[i];
            e_malo = 1'b0;
            if (!p_fij[i]) begin
                tent = ((p_n[i] % 2) == 0);
                if (p_n[i] == 0) p_lb[i] = d;
                else if (p_n[i] == 1) begin
                    if (d < p_lb[i]) begin p_fij[i] = 1'b1; p_act[i] = !nl; end
                end
                else begin
                    p_fij[i] = 1'b1;
                    p_act[i] = (d < p_d[i]) ? !nl : nl;
                end
                if (p_fij[i]) begin
                    e_lead = (nl == p_act[i]);
                    if (e_lead != tent) e_malo = 1'b1;
                end
                else e_lead = tent;
            end
            else e_lead = (nl == p_act[i]);
            e_trail = !e_lead;
            p_d[i] = d; p_n[i] = p_n[i] + 1; p_t[i] = t;
        end
    endtask

    task flanco_h;
        input nl;
        begin
            pol(0, nl);
            hs_fijada = p_fij[0]; hs_neg = !p_act[0];
            if (p_fij[0]) begin
                if (e_lead) begin
                    if (t_hs_lead >= 0) begin h_per = t - t_hs_lead; facum(M_HTOT, h_per); end
                    if (pend_hfp) begin facum(M_HFP, t - t_de_fin); pend_hfp = 1'b0; end
                    if (lin_video) t_vfp0 = t;
                    lin_video = 1'b0;
                    lin_cnt   = lin_cnt + 1;
                    t_hs_lead = t;
                end
                else begin
                    if (t_hs_lead >= 0) begin facum(M_HSW, t - t_hs_lead); hbp_listo = 1'b1; end
                    t_hs_trail = t;
                end
            end
        end
    endtask

    task cierra_cuadro;
        integer lin;
        begin
            lin = lin_cnt - ((t_hs_lead == t) ? 1 : 0);
            facum(M_VTOT, lin);
            facum(M_FCLK, t - t_vs_lead);
            facum(M_VACT, f_vact);
            facum(M_VS_OFF, (t_hs_lead >= 0) ? (t - t_hs_lead) : -1);
            if ((h_per > 0) && (t_vfp0 >= 0)) begin
                facum(M_VFP,   (t - t_vfp0) / h_per);
                facum(M_VFP_R, (t - t_vfp0) % h_per);
            end
            facum(M_AUD, f_aud);
            facum(M_ISLAS, f_islas);
            facum(M_PK_TOT,  f_pk[0]); facum(M_PK_NULO, f_pk[1]); facum(M_PK_ACR, f_pk[2]);
            facum(M_PK_ASP,  f_pk[3]); facum(M_PK_AVI,  f_pk[4]); facum(M_PK_AIF, f_pk[5]);
            facum(M_PK_SPD,  f_pk[6]); facum(M_PK_OTRO, f_pk[7]);
            if (cuadro_valido && p_fij[1]) begin
                // HDMI 1.4 5.2.1.2 / tabla 5-4: periodo de control extendido
                // (>= 32 caracteres) al menos una vez cada 50 ms
                if ((f_n[M_CTRL] == 0) || (f_max[M_CTRL] < 32)) begin
                    n_err_ctrl_ext = n_err_ctrl_ext + 1; e_cnt(n_err_ctrl_ext);
                    if (ver) $display("cuadro sin periodo de control extendido (el mayor mide %0d caracteres)", f_max[M_CTRL]);
                end
                f_vuelca;
                n_cuadros = n_cuadros + 1;
                fb_n_ult  = fb_idx;
                fb_w_ult  = f_max[M_HACT];
                if (VERBOSE >= 1)
                    $display("[hdmi_rx] cuadro %0d: %0dx%0d total, %0dx%0d activa; hs fp/ancho/bp %0d/%0d/%0d; vs fp/ancho/bp %0d/%0d/%0d lineas; %0d muestras de audio; paquetes ACR %0d audio %0d AVI %0d AudioIF %0d SPD %0d nulos %0d otros %0d",
                             n_cuadros, f_max[M_HTOT], lin, f_max[M_HACT], f_vact,
                             f_max[M_HFP], f_max[M_HSW], f_max[M_HBP],
                             f_max[M_VFP], f_max[M_VSW], f_max[M_VBP],
                             f_aud, f_pk[2], f_pk[3], f_pk[4], f_pk[5], f_pk[6], f_pk[1], f_pk[7]);
            end
        end
    endtask

    task flanco_v;
        input nl;
        begin
            pol(1, nl);
            vs_fijada = p_fij[1]; vs_neg = !p_act[1];
            if (e_malo) begin cuadro_abierto = 1'b0; cuadro_valido = 1'b0; end
            if (e_lead) begin
                if (cuadro_abierto) cierra_cuadro;
                n_vs           = n_vs + 1;
                cuadro_abierto = 1'b1;
                cuadro_valido  = p_fij[0];
                f_borra;
                lin_cnt   = (t_hs_lead == t) ? 1 : 0;
                fb_idx    = 0;
                t_vs_lead = t; t_vfp0 = -1; pend_vbp = 1'b0;
                nuevo_cuadro <= 1'b1;
            end
            else if (cuadro_abierto) begin
                if (h_per > 0) begin
                    facum(M_VSW,   (t - t_vs_lead) / h_per);
                    facum(M_VSW_R, (t - t_vs_lead) % h_per);
                end
                t_vs_trail = t; pend_vbp = 1'b1;
            end
        end
    endtask

    task sync_muestra;
        input hs;
        input vs;
        begin
            if (!sy_valido) begin
                sy_valido = 1'b1; hs_lvl = hs; vs_lvl = vs;
                p_t[0] = t; p_t[1] = t;
            end
            else begin
                if (hs !== hs_lvl) begin hs_lvl = hs; flanco_h(hs); end
                if (vs !== vs_lvl) begin vs_lvl = vs; flanco_v(vs); end
            end
            hsync <= hs; vsync <= vs;
        end
    endtask

    // ------------------------------------------------------------------
    //  Periodos
    // ------------------------------------------------------------------
    task entra_ctrl;        // empieza un periodo de control en un limite conocido
        begin
            estado = S_CTRL; ctrl_len = 0; pre_v = 0; pre_d = 0; ctrl_len_valida = 1'b1;
        end
    endtask

    task fin_ctrl;          // el periodo de control acaba en una banda de guarda
        begin
            if (ctrl_len_valida) begin
                facum(M_CTRL, ctrl_len);
                if (ctrl_len < 12) begin
                    n_ctrl_corto = n_ctrl_corto + 1; ea_cnt(n_ctrl_corto);
                    if (ver) $display("periodo de control de %0d caracteres (minimo 12, HDMI 1.4 tabla 5-3)", ctrl_len);
                end
            end
        end
    endtask

    task fin_video;         // t = primer caracter que ya no es de video
        begin
            if (vid_n == 0) begin
                n_video_vacio = n_video_vacio + 1; ea_cnt(n_video_vacio);
                if (ver) $display("preambulo y banda de guarda de video sin ningun pixel detras");
            end
            else begin
                facum(M_HACT, vid_n);
                t_de_fin = t; pend_hfp = 1'b1; lin_video = 1'b1;
                f_vact = f_vact + 1;
            end
        end
    endtask

    task pixel;
        begin
            if (vid_n == 0) begin
                if (hbp_listo) begin facum(M_HBP, t - t_hs_trail); hbp_listo = 1'b0; end
                if (pend_vbp && (t_hs_lead >= 0) && (h_per > 0)) begin
                    facum(M_VBP,   (t_hs_lead - t_vs_trail) / h_per);
                    facum(M_VBP_R, (t_hs_lead - t_vs_trail) % h_per);
                    pend_vbp = 1'b0;
                end
            end
            dec_video(s0, disp0, d0, disp0, ec0, ed0);
            dec_video(s1, disp1, d1, disp1, ec1, ed1);
            dec_video(s2, disp2, d2, disp2, ec2, ed2);
            if (ec0 || ec1 || ec2) begin
                n_err_vcod = n_err_vcod + 1; e_cnt(n_err_vcod);
                if (ver) $display("codigo TMDS de video imposible (pixel %0d): %b %b %b", vid_n, s0, s1, s2);
            end
            else if (ed0 || ed1 || ed2) begin
                n_err_vdc = n_err_vdc + 1; e_cnt(n_err_vdc);
                if (ver) $display("balance de continua: bit 9 inesperado (pixel %0d, canales %b)", vid_n, {ed2, ed1, ed0});
            end
            de  <= 1'b1;
            rgb <= {d2, d1, d0};
            px  <= vid_n[15:0];
            py  <= f_vact[15:0];
            en_cuadro <= cuadro_abierto;
            if (fb_idx < FB_N) fb[fb_idx] = {d2, d1, d0};
            fb_idx = fb_idx + 1;
            vid_n  = vid_n + 1;
            n_pix_total = n_pix_total + 1;
        end
    endtask

    // ------------------------------------------------------------------
    //  Audio
    // ------------------------------------------------------------------
    task muestra;
        input [23:0] l;
        input [23:0] r;
        input [7:0]  st;        // {PR, CR, UR, VR, PL, CL, UL, VL}
        input        b;         // primera trama de un bloque IEC 60958
        begin
            if ((^{l, st[3:0]}) !== 1'b0) begin
                n_err_par = n_err_par + 1; e_cnt(n_err_par);
                if (ver) $display("paridad IEC 60958 incorrecta, canal izquierdo, muestra %0d", aud_total);
            end
            if ((^{r, st[7:4]}) !== 1'b0) begin
                n_err_par = n_err_par + 1; e_cnt(n_err_par);
                if (ver) $display("paridad IEC 60958 incorrecta, canal derecho, muestra %0d", aud_total);
            end
            if (st[0] || st[4]) n_aud_v1 = n_aud_v1 + 1;
            if (st[1] || st[5]) n_aud_u1 = n_aud_u1 + 1;
            // bloque de estado de canal: 192 tramas, la primera marcada con B
            if (cs_idx == 192) begin
                if (!b) begin
                    n_av_bloque = n_av_bloque + 1; a_cnt(n_av_bloque);
                    if (ver) $display("falta la marca B tras 192 tramas de audio");
                end
                cs_idx = 0;
            end
            else if (b) begin
                if (cs_idx > 0) begin
                    n_av_bloque = n_av_bloque + 1; a_cnt(n_av_bloque);
                    if (ver) $display("marca B tras %0d tramas (el bloque IEC 60958 mide 192)", cs_idx);
                end
                cs_idx = 0;
            end
            if (cs_idx >= 0) begin
                cs_l[cs_idx] = st[2];
                cs_r[cs_idx] = st[6];
                cs_idx = cs_idx + 1;
                if (cs_idx == 192) begin
                    if ((n_bloques_cs > 0) && ((cs_l !== cs_l_ult) || (cs_r !== cs_r_ult))) begin
                        n_av_cs_cambia = n_av_cs_cambia + 1; a_cnt(n_av_cs_cambia);
                        if (ver) $display("el estado de canal cambia de un bloque al siguiente");
                    end
                    cs_l_ult = cs_l; cs_r_ult = cs_r;
                    n_bloques_cs = n_bloques_cs + 1;
                end
            end
            q_l[aud_total % AUD_N] = l;
            q_r[aud_total % AUD_N] = r;
            q_f[aud_total % AUD_N] = {b, st};
            aud_total = aud_total + 1;
            f_aud     = f_aud + 1;
        end
    endtask

    // ------------------------------------------------------------------
    //  Paquetes (HDMI 1.4 5.2.3.4, 5.3; CEA-861-D cap. 6)
    // ------------------------------------------------------------------
    task infoframe_suma;    // checksum: cabecera + PB0..PBn suman 0 modulo 256
        output mal;
        reg [7:0] s;
        integer   i, n;
        begin
            n = hb2[4:0];
            s = hb0 + hb1 + hb2;
            for (i = 0; (i <= n) && (i < 28); i = i + 1) s = s + pb[i];
            mal = (s !== 8'h00);
        end
    endtask

    task paquete;
        reg       mal_h, mal_s0, mal_s1, mal_s2, mal_s3, mal_chk;
        integer   i, j, tipo;
        reg [3:0] sp, bb;
        begin
            hb0 = bch_h[7:0]; hb1 = bch_h[15:8]; hb2 = bch_h[23:16];
            for (j = 0; j < 7; j = j + 1) begin
                pb[j]      = bch_s0[j*8 +: 8];
                pb[7 + j]  = bch_s1[j*8 +: 8];
                pb[14 + j] = bch_s2[j*8 +: 8];
                pb[21 + j] = bch_s3[j*8 +: 8];
            end
            mal_h  = (f_sind32(bch_h)  !== 8'h00);
            mal_s0 = (f_sind64(bch_s0) !== 8'h00);
            mal_s1 = (f_sind64(bch_s1) !== 8'h00);
            mal_s2 = (f_sind64(bch_s2) !== 8'h00);
            mal_s3 = (f_sind64(bch_s3) !== 8'h00);
            n_pk_total = n_pk_total + 1;
            f_pk[0]    = f_pk[0] + 1;
            if (mal_h) begin
                n_err_bch_cab = n_err_bch_cab + 1; e_cnt(n_err_bch_cab);
                if (ver) $display("BCH de cabecera incorrecto (HB0..2 = %02h %02h %02h, paridad %02h)", hb0, hb1, hb2, bch_h[31:24]);
            end
            if (mal_s0 || mal_s1 || mal_s2 || mal_s3) begin
                n_err_bch_sub = n_err_bch_sub + mal_s0 + mal_s1 + mal_s2 + mal_s3; e_cnt(n_pk_malos + 1);
                if (ver) $display("BCH de subpaquete incorrecto (tipo %02h, subpaquetes malos %b)", hb0, {mal_s3, mal_s2, mal_s1, mal_s0});
            end
            if (mal_h || mal_s0 || mal_s1 || mal_s2 || mal_s3) begin
                n_pk_malos = n_pk_malos + 1;        // un paquete roto no se interpreta
            end
            else begin
                tipo = hb0;
                n_tipo[tipo] = n_tipo[tipo] + 1;
                ult_pk[tipo*32 + 0] = hb0; ult_pk[tipo*32 + 1] = hb1; ult_pk[tipo*32 + 2] = hb2;
                for (i = 0; i < 28; i = i + 1) ult_pk[tipo*32 + 3 + i] = pb[i];
                if ((VERBOSE >= 3) || ((VERBOSE >= 2) && (tipo != 0) && (tipo != 2))) begin
                    pos;
                    $write("paquete %02h %02h %02h :", hb0, hb1, hb2);
                    for (i = 0; i < 28; i = i + 1) $write(" %02h", pb[i]);
                    $write("\n");
                end
                case (hb0)
                    8'h00: begin                    // nulo
                        n_pk_nulo = n_pk_nulo + 1; f_pk[1] = f_pk[1] + 1;
                    end
                    8'h01: begin                    // Audio Clock Regeneration (5.3.3)
                        n_pk_acr = n_pk_acr + 1; f_pk[2] = f_pk[2] + 1;
                        if ((bch_s0[55:0] !== bch_s1[55:0]) || (bch_s0[55:0] !== bch_s2[55:0]) || (bch_s0[55:0] !== bch_s3[55:0])) begin
                            n_err_acr = n_err_acr + 1; e_cnt(n_err_acr);
                            if (ver) $display("los cuatro subpaquetes del ACR no son iguales");
                        end
                        acr_cts = {pb[1][3:0], pb[2], pb[3]};
                        acr_n   = {pb[4][3:0], pb[5], pb[6]};
                        if (n_acr == 0) begin acr_cts_primero = acr_cts; acr_cts_min = acr_cts; acr_cts_max = acr_cts; end
                        else begin
                            if (acr_cts < acr_cts_min) acr_cts_min = acr_cts;
                            if (acr_cts > acr_cts_max) acr_cts_max = acr_cts;
                        end
                        n_acr = n_acr + 1;
                        facum(M_CTS, acr_cts);
                        facum(M_N, acr_n);
                    end
                    8'h02: begin                    // Audio Sample (5.3.4)
                        n_pk_asp = n_pk_asp + 1; f_pk[3] = f_pk[3] + 1;
                        sp = hb1[3:0]; bb = hb2[7:4];
                        if (hb1[7:4] !== 4'b0000) begin
                            n_av_asp = n_av_asp + 1; a_cnt(n_av_asp);
                            if (ver) $display("paquete de audio con HB1 = %02h (layout 1 o bits reservados): solo se entiende estereo", hb1);
                        end
                        if (hb2[3:0] !== 4'b0000) n_aud_plano = n_aud_plano + 1;
                        if (sp !== 4'b1111) n_asp_incompleto = n_asp_incompleto + 1;
                        for (i = 0; i < 4; i = i + 1)
                            if (sp[i])
                                muestra({pb[i*7 + 2], pb[i*7 + 1], pb[i*7 + 0]},
                                        {pb[i*7 + 5], pb[i*7 + 4], pb[i*7 + 3]},
                                        pb[i*7 + 6], bb[i]);
                    end
                    8'h03: begin                    // General Control
                        n_pk_gcp = n_pk_gcp + 1; f_pk[7] = f_pk[7] + 1;
                        if (pb[0][0]) gcp_avmute_set = gcp_avmute_set + 1;
                        if (pb[0][4]) gcp_avmute_clr = gcp_avmute_clr + 1;
                    end
                    8'h82: begin                    // AVI InfoFrame (CEA-861-D 6.4)
                        n_pk_avi = n_pk_avi + 1; f_pk[4] = f_pk[4] + 1;
                        infoframe_suma(mal_chk);
                        if (mal_chk) begin
                            n_err_chk_if = n_err_chk_if + 1; e_cnt(n_err_chk_if);
                            if (ver) $display("checksum del AVI InfoFrame incorrecto");
                        end
                        else begin
                            avi_n = avi_n + 1; avi_ver = hb1; avi_len = hb2[4:0];
                            avi_y = pb[1][6:5]; avi_a = pb[1][4]; avi_s = pb[1][1:0];
                            avi_c = pb[2][7:6]; avi_m = pb[2][5:4]; avi_r = pb[2][3:0];
                            avi_itc = pb[3][7]; avi_q = pb[3][3:2];
                            avi_vic = pb[4][6:0]; avi_pr = pb[5][3:0];
                            if ((hb1 !== 8'd2) || (hb2 !== 8'd13)) begin
                                n_av_if = n_av_if + 1; a_cnt(n_av_if);
                                if (ver) $display("AVI InfoFrame version %0d longitud %0d (HDMI 1.4 usa version 2, longitud 13)", hb1, hb2);
                            end
                        end
                    end
                    8'h83: begin                    // Source Product Description (CEA-861-D 6.5)
                        n_pk_spd = n_pk_spd + 1; f_pk[6] = f_pk[6] + 1;
                        infoframe_suma(mal_chk);
                        if (mal_chk) begin
                            n_err_chk_if = n_err_chk_if + 1; e_cnt(n_err_chk_if);
                            if (ver) $display("checksum del SPD InfoFrame incorrecto");
                        end
                        else begin
                            spd_n = spd_n + 1;
                            spd_vendor   = {pb[1], pb[2], pb[3], pb[4], pb[5], pb[6], pb[7], pb[8]};
                            spd_producto = {pb[9], pb[10], pb[11], pb[12], pb[13], pb[14], pb[15], pb[16],
                                            pb[17], pb[18], pb[19], pb[20], pb[21], pb[22], pb[23], pb[24]};
                            spd_sdi = pb[25];
                            if ((hb1 !== 8'd1) || (hb2 !== 8'd25)) begin
                                n_av_if = n_av_if + 1; a_cnt(n_av_if);
                                if (ver) $display("SPD InfoFrame version %0d longitud %0d (se espera 1 y 25)", hb1, hb2);
                            end
                        end
                    end
                    8'h84: begin                    // Audio InfoFrame (CEA-861-D 6.6)
                        n_pk_aif = n_pk_aif + 1; f_pk[5] = f_pk[5] + 1;
                        infoframe_suma(mal_chk);
                        if (mal_chk) begin
                            n_err_chk_if = n_err_chk_if + 1; e_cnt(n_err_chk_if);
                            if (ver) $display("checksum del Audio InfoFrame incorrecto");
                        end
                        else begin
                            aif_n = aif_n + 1; aif_ver = hb1; aif_len = hb2[4:0];
                            aif_ct = pb[1][7:4]; aif_cc = pb[1][2:0];
                            aif_sf = pb[2][4:2]; aif_ss = pb[2][1:0];
                            aif_ca = pb[4]; aif_dm = pb[5][7]; aif_lsv = pb[5][6:3];
                            if ((hb1 !== 8'd1) || (hb2 !== 8'd10)) begin
                                n_av_if = n_av_if + 1; a_cnt(n_av_if);
                                if (ver) $display("Audio InfoFrame version %0d longitud %0d (se espera 1 y 10)", hb1, hb2);
                            end
                        end
                    end
                    default: begin
                        n_pk_otro = n_pk_otro + 1; f_pk[7] = f_pk[7] + 1;
                        if (hb0[7]) begin           // otro InfoFrame: al menos su checksum
                            infoframe_suma(mal_chk);
                            if (mal_chk) begin
                                n_err_chk_if = n_err_chk_if + 1; e_cnt(n_err_chk_if);
                                if (ver) $display("checksum de InfoFrame tipo %02h incorrecto", hb0);
                            end
                        end
                        else begin
                            n_av_pk_desc = n_av_pk_desc + 1; a_cnt(n_av_pk_desc);
                            if (ver) $display("paquete de tipo %02h no interpretado", hb0);
                        end
                    end
                endcase
            end
        end
    endtask

    // ------------------------------------------------------------------
    //  Proceso principal: un caracter por flanco
    // ------------------------------------------------------------------
    initial begin
        estricto = ESTRICTO;
        reinicia;
        en_reset = 1'b1;
        hsync = 1'b0; vsync = 1'b0; ctl = 4'd0; de = 1'b0; rgb = 24'd0; px = 16'd0; py = 16'd0;
        en_cuadro = 1'b0; nuevo_cuadro = 1'b0; aud_valid = 1'b0; aud_l = 24'd0; aud_r = 24'd0;
    end

    always @(posedge clk_pixel) begin
        de           <= 1'b0;
        nuevo_cuadro <= 1'b0;
        aud_valid    <= 1'b0;
        if (rst) begin
            if (!en_reset) begin reinicia; en_reset = 1'b1; end
        end
        else begin
            en_reset = 1'b0;
            t  = t + 1;
            s0 = tmds0; s1 = tmds1; s2 = tmds2;
            c0 = f_ctrl(s0);  c1 = f_ctrl(s1);  c2 = f_ctrl(s2);
            es_x        = ((^{s0, s1, s2}) === 1'bx);
            todo_ctrl   = c0[2] && c1[2] && c2[2];
            algun_ctrl  = c0[2] || c1[2] || c2[2];
            if (todo_ctrl || (estado == S_VIDEO) || (estado == S_BUSCA)) begin
                // ni TERC4 ni bandas de guarda hacen falta aqui (simulacion mas rapida)
                q0 = 5'd0; q1 = 5'd0; q2 = 5'd0; es_gb_video = 1'b0; es_gb_isla = 1'b0;
            end
            else begin
                q0 = f_terc4(s0); q1 = f_terc4(s1); q2 = f_terc4(s2);
                es_gb_video = (s0 == GB_VIDEO_C02) && (s1 == GB_VIDEO_C1) && (s2 == GB_VIDEO_C02);
                es_gb_isla  = (s1 == GB_ISLA_C12) && (s2 == GB_ISLA_C12) && q0[4] && (q0[3:2] == 2'b11);
            end

            if (es_x) begin
                if (sincronizado) begin
                    n_err_x = n_err_x + 1; e_cnt(n_err_x);
                    if (ver) $display("simbolo con X/Z: %b %b %b (falta MODEL_TECH al compilar el transmisor?)", s0, s1, s2);
                end
            end
            else begin
                repetir = 1'b1;
                while (repetir) begin
                    repetir = 1'b0;
                    case (estado)
                        // ---------------------------------------------
                        S_BUSCA: begin
                            if (todo_ctrl) begin
                                sincronizado = 1'b1;
                                entra_ctrl;
                                ctrl_len_valida = 1'b0;     // este primer periodo esta incompleto
                                repetir = 1'b1;
                            end
                        end
                        // ---------------------------------------------
                        S_CTRL: begin
                            if (todo_ctrl) begin
                                ctrl_len = ctrl_len + 1;
                                sync_muestra(c0[0], c0[1]);
                                ctl_v = {c2[1], c2[0], c1[1], c1[0]};       // CTL3..CTL0
                                ctl <= ctl_v;
                                case (ctl_v)
                                    4'b0001: begin          // preambulo de video (tabla 5-2)
                                        if (pre_d != 0) begin
                                            n_err_preamb = n_err_preamb + 1; e_cnt(n_err_preamb);
                                            if (ver) $display("preambulo de isla de %0d caracteres interrumpido", pre_d);
                                        end
                                        pre_d = 0; pre_v = pre_v + 1;
                                    end
                                    4'b0101: begin          // preambulo de isla de datos
                                        if (pre_v != 0) begin
                                            n_err_preamb = n_err_preamb + 1; e_cnt(n_err_preamb);
                                            if (ver) $display("preambulo de video de %0d caracteres interrumpido", pre_v);
                                        end
                                        pre_v = 0; pre_d = pre_d + 1;
                                    end
                                    4'b0000: begin
                                        if ((pre_v != 0) || (pre_d != 0)) begin
                                            n_err_preamb = n_err_preamb + 1; e_cnt(n_err_preamb);
                                            if (ver) $display("preambulo de %0d caracteres que no acaba en banda de guarda", pre_v + pre_d);
                                        end
                                        pre_v = 0; pre_d = 0;
                                    end
                                    default: begin          // ni reposo ni preambulo (sin HDCP no debe verse)
                                        n_err_ctl = n_err_ctl + 1; e_cnt(n_err_ctl);
                                        if (ver) $display("valor reservado de CTL3..0 = %b", ctl_v);
                                        pre_v = 0; pre_d = 0;
                                    end
                                endcase
                            end
                            else if (es_gb_video) begin
                                if (pre_v != 8) begin
                                    n_err_preamb = n_err_preamb + 1; e_cnt(n_err_preamb);
                                    if (ver) $display("banda de guarda de video tras un preambulo de %0d caracteres (deben ser 8)", pre_v);
                                end
                                fin_ctrl;
                                estado = S_VGB; gb_cnt = 1;
                            end
                            else if (es_gb_isla) begin
                                if (pre_d != 8) begin
                                    n_err_preamb = n_err_preamb + 1; e_cnt(n_err_preamb);
                                    if (ver) $display("banda de guarda de isla tras un preambulo de %0d caracteres (deben ser 8)", pre_d);
                                end
                                fin_ctrl;
                                sync_muestra(q0[0], q0[1]);
                                estado = S_DGB_I; gb_cnt = 1;
                            end
                            else begin
                                n_err_sim = n_err_sim + 1; e_cnt(n_err_sim);
                                if (ver) $display("simbolo no valido en periodo de control: %b %b %b", s0, s1, s2);
                                ctrl_len = ctrl_len + 1; pre_v = 0; pre_d = 0;
                            end
                        end
                        // ---------------------------------------------
                        S_VGB: begin
                            if (es_gb_video) begin
                                gb_cnt = gb_cnt + 1;
                                estado = S_VIDEO; vid_n = 0; disp0 = 0; disp1 = 0; disp2 = 0;
                            end
                            else begin
                                n_err_guarda = n_err_guarda + 1; e_cnt(n_err_guarda);
                                if (ver) $display("banda de guarda de video de %0d caracter (deben ser 2)", gb_cnt);
                                estado = S_VIDEO; vid_n = 0; disp0 = 0; disp1 = 0; disp2 = 0;
                                repetir = 1'b1;
                            end
                        end
                        // ---------------------------------------------
                        S_VIDEO: begin
                            if (todo_ctrl) begin
                                fin_video;
                                entra_ctrl;
                                repetir = 1'b1;
                            end
                            else begin
                                if (algun_ctrl) begin
                                    n_err_sim = n_err_sim + 1; e_cnt(n_err_sim);
                                    if (ver) $display("canales en desacuerdo en periodo de video: %b %b %b", s0, s1, s2);
                                end
                                pixel;
                            end
                        end
                        // ---------------------------------------------
                        S_DGB_I: begin
                            if (es_gb_isla) begin
                                sync_muestra(q0[0], q0[1]);
                                gb_cnt = gb_cnt + 1;
                                estado = S_ISLA; isla_k = 0; isla_pk = 0;
                            end
                            else begin
                                n_err_guarda = n_err_guarda + 1; e_cnt(n_err_guarda);
                                if (ver) $display("banda de guarda inicial de isla de %0d caracter (deben ser 2)", gb_cnt);
                                estado = S_ISLA; isla_k = 0; isla_pk = 0;
                                repetir = 1'b1;
                            end
                        end
                        // ---------------------------------------------
                        S_ISLA: begin
                            if ((s1 == GB_ISLA_C12) && (s2 == GB_ISLA_C12)) begin
                                // banda de guarda final
                                if (es_gb_isla) sync_muestra(q0[0], q0[1]);
                                else begin
                                    n_err_guarda = n_err_guarda + 1; e_cnt(n_err_guarda);
                                    if (ver) $display("banda de guarda final de isla: el canal 0 no lleva TERC4 11xx (%b)", s0);
                                end
                                if (isla_k != 0) begin
                                    n_err_isla = n_err_isla + 1; e_cnt(n_err_isla);
                                    if (ver) $display("isla cortada en el caracter %0d de un paquete", isla_k);
                                end
                                if ((isla_pk == 0) || (isla_pk > 18)) begin
                                    n_err_isla = n_err_isla + 1; e_cnt(n_err_isla);
                                    if (ver) $display("isla de %0d paquetes (de 1 a 18)", isla_pk);
                                end
                                facum(M_ISLA, isla_pk);
                                n_islas = n_islas + 1; f_islas = f_islas + 1;
                                estado = S_DGB_F; gb_cnt = 1;
                            end
                            else if (todo_ctrl) begin
                                n_err_isla = n_err_isla + 1; e_cnt(n_err_isla);
                                if (ver) $display("isla sin banda de guarda final (paquete %0d, caracter %0d)", isla_pk, isla_k);
                                entra_ctrl;
                                repetir = 1'b1;
                            end
                            else begin
                                if (!(q0[4] && q1[4] && q2[4])) begin
                                    n_err_terc4 = n_err_terc4 + 1; e_cnt(n_err_terc4);
                                    if (ver) $display("simbolo no TERC4 en isla (paquete %0d, caracter %0d): %b %b %b", isla_pk, isla_k, s0, s1, s2);
                                end
                                if (q0[4]) begin
                                    sync_muestra(q0[0], q0[1]);
                                    if ((isla_pk == 0) && (isla_k == 0)) begin
                                        if (q0[3]) n_d3_primero_1 = n_d3_primero_1 + 1;
                                        else       n_d3_primero_0 = n_d3_primero_0 + 1;
                                    end
                                    else if (!q0[3]) n_d3_resto_0 = n_d3_resto_0 + 1;
                                end
                                // canal 0 bit 2: cabecera; canales 1 y 2: bits pares
                                // e impares de los cuatro subpaquetes (fig. 5-4)
                                bch_h[isla_k]          = q0[2];
                                bch_s0[2*isla_k]       = q1[0];
                                bch_s0[2*isla_k + 1]   = q2[0];
                                bch_s1[2*isla_k]       = q1[1];
                                bch_s1[2*isla_k + 1]   = q2[1];
                                bch_s2[2*isla_k]       = q1[2];
                                bch_s2[2*isla_k + 1]   = q2[2];
                                bch_s3[2*isla_k]       = q1[3];
                                bch_s3[2*isla_k + 1]   = q2[3];
                                isla_k = isla_k + 1;
                                if (isla_k == 32) begin
                                    paquete;
                                    isla_k = 0; isla_pk = isla_pk + 1;
                                end
                            end
                        end
                        // ---------------------------------------------
                        S_DGB_F: begin
                            if (gb_cnt == 1) begin
                                if (es_gb_isla) begin
                                    sync_muestra(q0[0], q0[1]);
                                    gb_cnt = 2;
                                end
                                else begin
                                    n_err_guarda = n_err_guarda + 1; e_cnt(n_err_guarda);
                                    if (ver) $display("banda de guarda final de isla de 1 caracter (deben ser 2)");
                                    entra_ctrl;
                                    repetir = 1'b1;
                                end
                            end
                            else begin
                                entra_ctrl;
                                repetir = 1'b1;
                            end
                        end
                        default: estado = S_BUSCA;
                    endcase
                end
            end

            // salida serie de la cola de audio: una muestra por ciclo
            if (aud_rd < aud_total) begin
                aud_valid <= 1'b1;
                aud_l     <= q_l[aud_rd % AUD_N];
                aud_r     <= q_r[aud_rd % AUD_N];
                aud_rd    = aud_rd + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    //  Autocomprobacion de las tablas (una errata aqui invalidaria todo)
    // ------------------------------------------------------------------
    integer ti, tj;
    reg [9:0] tab_terc4 [0:15];
    reg [9:0] sim_i;
    initial begin
        // reconstruye la tabla TERC4 inversa y comprueba que es una biyeccion de
        // 16 simbolos de cinco unos, ninguno de control ni banda de guarda de isla
        for (ti = 0; ti < 16; ti = ti + 1) tab_terc4[ti] = 10'd0;
        tj = 0;
        for (ti = 0; ti < 1024; ti = ti + 1) begin
            sim_i = ti[9:0];
            if (f_terc4(sim_i) & 5'h10) begin
                tab_terc4[f_terc4(sim_i) & 5'h0F] = sim_i;
                tj = tj + 1;
                if (f_unos10(sim_i) != 5) $display("[hdmi_rx] ERROR INTERNO: TERC4 %b sin cinco unos", sim_i);
                if (f_ctrl(sim_i) & 3'b100) $display("[hdmi_rx] ERROR INTERNO: TERC4 %b es un simbolo de control", sim_i);
            end
        end
        if (tj != 16) $display("[hdmi_rx] ERROR INTERNO: la tabla TERC4 tiene %0d simbolos", tj);
        for (ti = 0; ti < 16; ti = ti + 1)
            if (tab_terc4[ti] == 10'd0) $display("[hdmi_rx] ERROR INTERNO: falta el TERC4 de %0d", ti);
        if (f_terc4(GB_ISLA_C12) & 5'h10) $display("[hdmi_rx] ERROR INTERNO: la banda de guarda de isla es un TERC4");
    end

    // ------------------------------------------------------------------
    //  Tareas para el banco
    // ------------------------------------------------------------------
    task chk;               // la medida idx debe valer siempre "esperado"
        input [8*48-1:0] nombre;
        input integer    idx;
        input integer    esperado;
        begin
            if (g_n[idx] == 0) begin
                $display("  [FALLO] %0s: sin medidas", nombre);
                n_fallos_chk = n_fallos_chk + 1;
            end
            else if ((g_min[idx] != esperado) || (g_max[idx] != esperado)) begin
                $display("  [FALLO] %0s: medido %0d..%0d, esperado %0d (%0d medidas)", nombre, g_min[idx], g_max[idx], esperado, g_n[idx]);
                n_fallos_chk = n_fallos_chk + 1;
            end
            else $display("  [ ok  ] %0s = %0d (%0d medidas)", nombre, esperado, g_n[idx]);
        end
    endtask

    task chk_valor;         // comparacion suelta
        input [8*48-1:0] nombre;
        input integer    medido;
        input integer    esperado;
        begin
            if (medido != esperado) begin
                $display("  [FALLO] %0s: medido %0d, esperado %0d", nombre, medido, esperado);
                n_fallos_chk = n_fallos_chk + 1;
            end
            else $display("  [ ok  ] %0s = %0d", nombre, esperado);
        end
    endtask

    task comprobar_geometria;
        input integer htot, vtot, hact, vact, hfp, hsw, vfp, vsw;
        input integer hs_negativa, vs_negativa;
        begin
            $display("Geometria (CEA-861-D), %0d cuadros completos:", n_cuadros);
            if (n_cuadros == 0) begin
                $display("  [FALLO] ningun cuadro completo");
                n_fallos_chk = n_fallos_chk + 1;
            end
            chk("columnas totales",                        M_HTOT,   htot);
            chk("lineas totales",                          M_VTOT,   vtot);
            chk("ciclos de pixel por cuadro",              M_FCLK,   htot * vtot);
            chk("columnas activas",                        M_HACT,   hact);
            chk("lineas activas",                          M_VACT,   vact);
            chk("hsync: porche delantero (px)",            M_HFP,    hfp);
            chk("hsync: anchura (px)",                     M_HSW,    hsw);
            chk("hsync: porche trasero (px)",              M_HBP,    htot - hact - hfp - hsw);
            chk("vsync: porche delantero (lineas)",        M_VFP,    vfp);
            chk("vsync: anchura (lineas)",                 M_VSW,    vsw);
            chk("vsync: porche trasero (lineas)",          M_VBP,    vtot - vact - vfp - vsw);
            chk("vsync: resto del porche delantero (px)",  M_VFP_R,  0);
            chk("vsync: resto de la anchura (px)",         M_VSW_R,  0);
            chk("vsync: resto del porche trasero (px)",    M_VBP_R,  0);
            chk("vsync alineado con hsync (px)",           M_VS_OFF, 0);
            if (!hs_fijada || !vs_fijada) begin
                $display("  [FALLO] polaridad de sincronismos sin determinar");
                n_fallos_chk = n_fallos_chk + 1;
            end
            else begin
                chk_valor("hsync de polaridad negativa (1 = si)", hs_neg, hs_negativa);
                chk_valor("vsync de polaridad negativa (1 = si)", vs_neg, vs_negativa);
            end
        end
    endtask

    task comprobar_acr;
        input integer n_esp, cts_esp, cts_tol;
        begin
            $display("Audio Clock Regeneration (HDMI 1.4 7.2):");
            if (g_n[M_N] == 0) begin
                $display("  [FALLO] ningun paquete ACR en los cuadros completos");
                n_fallos_chk = n_fallos_chk + 1;
            end
            else begin
                chk("N", M_N, n_esp);
                if ((g_min[M_CTS] < cts_esp - cts_tol) || (g_max[M_CTS] > cts_esp + cts_tol)) begin
                    $display("  [FALLO] CTS: medido %0d..%0d, esperado %0d +/- %0d (%0d paquetes)", g_min[M_CTS], g_max[M_CTS], cts_esp, cts_tol, g_n[M_CTS]);
                    n_fallos_chk = n_fallos_chk + 1;
                end
                else $display("  [ ok  ] CTS = %0d..%0d, esperado %0d +/- %0d (%0d paquetes)", g_min[M_CTS], g_max[M_CTS], cts_esp, cts_tol, g_n[M_CTS]);
                $display("          (desde el arranque: %0d ACR, primer CTS %0d, min %0d, max %0d)", n_acr, acr_cts_primero, acr_cts_min, acr_cts_max);
            end
        end
    endtask

    task comprobar_estado_canal;
        input integer fs_hz, bits;
        begin
            $display("Estado de canal IEC 60958-3 (%0d bloques completos de 192 tramas):", n_bloques_cs);
            if (n_bloques_cs == 0) begin
                $display("  [FALLO] ningun bloque completo");
                n_fallos_chk = n_fallos_chk + 1;
            end
            else begin
                chk_valor("uso de consumo (bit 0 = 0), izq.",          cs_l_ult[0], 0);
                chk_valor("uso de consumo (bit 0 = 0), der.",          cs_r_ult[0], 0);
                chk_valor("PCM lineal (bit 1 = 0), izq.",              cs_l_ult[1], 0);
                chk_valor("PCM lineal (bit 1 = 0), der.",              cs_r_ult[1], 0);
                chk_valor("frecuencia de muestreo (Hz), izq.",         f_fs_cs(cs_l_ult[27:24]), fs_hz);
                chk_valor("frecuencia de muestreo (Hz), der.",         f_fs_cs(cs_r_ult[27:24]), fs_hz);
                chk_valor("bits por muestra, izq.",                    f_bits_cs(cs_l_ult[35:32]), bits);
                chk_valor("bits por muestra, der.",                    f_bits_cs(cs_r_ult[35:32]), bits);
                chk_valor("numero de canal, izq. (1)",                 cs_l_ult[23:20], 1);
                chk_valor("numero de canal, der. (2)",                 cs_r_ult[23:20], 2);
                chk_valor("bloques de longitud distinta de 192",       n_av_bloque, 0);
                chk_valor("cambios del estado de canal entre bloques", n_av_cs_cambia, 0);
                chk_valor("muestras con el bit de validez a 1",        n_aud_v1, 0);
                // un sumidero calla el audio si ve cualquiera de estas dos cosas
                chk_valor("paquetes de audio marcados como muestra plana", n_aud_plano, 0);
                chk_valor("paquetes de audio con cabecera no estereo",  n_av_asp, 0);
                $display("          (copia permitida: %0d, preenfasis: %0d, categoria: %02h, precision de reloj: %0d)",
                         cs_l_ult[2], cs_l_ult[5:3], cs_l_ult[15:8], cs_l_ult[29:28]);
            end
        end
    endtask

    task comprobar_avi;
        input integer vic, aspecto;
        begin
            $display("AVI InfoFrame (CEA-861-D 6.4):");
            if (avi_n == 0) begin
                $display("  [FALLO] no se ha recibido ninguno valido");
                n_fallos_chk = n_fallos_chk + 1;
            end
            else begin
                chk_valor("VIC",                                  avi_vic, vic);
                chk_valor("relacion de aspecto M (1=4:3, 2=16:9)", avi_m,  aspecto);
                chk_valor("formato de color Y (0 = RGB)",         avi_y,   0);
                chk_valor("repeticion de pixel",                  avi_pr,  0);
                $display("          (version %0d, longitud %0d, ITC %0d, Q %0d, colorimetria %0d, barrido %0d, R %0d)",
                         avi_ver, avi_len, avi_itc, avi_q, avi_c, avi_s, avi_r);
            end
        end
    endtask

    task comprobar_aif;
        begin
            $display("Audio InfoFrame (CEA-861-D 6.6, HDMI 1.4 8.2.2):");
            if (aif_n == 0) begin
                $display("  [FALLO] no se ha recibido ninguno valido");
                n_fallos_chk = n_fallos_chk + 1;
            end
            else begin
                chk_valor("tipo de codificacion CT (0 = ver cabecera)", aif_ct, 0);
                chk_valor("tamano de muestra SS (0 = ver cabecera)",    aif_ss, 0);
                chk_valor("frecuencia SF (0 = ver cabecera)",           aif_sf, 0);
                chk_valor("numero de canales CC (1 = dos canales)",     aif_cc, 1);
                chk_valor("asignacion de altavoces CA (0 = FL/FR)",     aif_ca, 0);
            end
        end
    endtask

    task comprobar_presencia;
        begin
            $display("Paquetes por cuadro:");
            if (g_n[M_PK_AVI] == 0) begin
                $display("  [FALLO] sin cuadros completos");
                n_fallos_chk = n_fallos_chk + 1;
            end
            else begin
                if (g_min[M_PK_AVI] < 1) begin $display("  [FALLO] hay cuadros sin AVI InfoFrame"); n_fallos_chk = n_fallos_chk + 1; end
                else $display("  [ ok  ] AVI InfoFrame en todos los cuadros (%0d..%0d por cuadro)", g_min[M_PK_AVI], g_max[M_PK_AVI]);
                if (g_min[M_PK_AIF] < 1) begin $display("  [FALLO] hay cuadros sin Audio InfoFrame"); n_fallos_chk = n_fallos_chk + 1; end
                else $display("  [ ok  ] Audio InfoFrame en todos los cuadros (%0d..%0d por cuadro)", g_min[M_PK_AIF], g_max[M_PK_AIF]);
                if (g_min[M_PK_ACR] < 1) begin $display("  [FALLO] hay cuadros sin ACR"); n_fallos_chk = n_fallos_chk + 1; end
                else $display("  [ ok  ] ACR en todos los cuadros (%0d..%0d por cuadro)", g_min[M_PK_ACR], g_max[M_PK_ACR]);
                if (g_min[M_PK_ASP] < 1) begin $display("  [FALLO] hay cuadros sin paquetes de audio"); n_fallos_chk = n_fallos_chk + 1; end
                else $display("  [ ok  ] paquetes de audio en todos los cuadros (%0d..%0d por cuadro)", g_min[M_PK_ASP], g_max[M_PK_ASP]);
                // AVMUTE dejaria la pantalla en negro y el audio callado
                chk_valor("paquetes de control general con Set_AVMUTE", gcp_avmute_set, 0);
                $display("          (SPD %0d..%0d, nulos %0d..%0d, otros %0d..%0d, total %0d..%0d por cuadro; %0d..%0d islas de %0d..%0d paquetes)",
                         g_min[M_PK_SPD], g_max[M_PK_SPD], g_min[M_PK_NULO], g_max[M_PK_NULO],
                         g_min[M_PK_OTRO], g_max[M_PK_OTRO], g_min[M_PK_TOT], g_max[M_PK_TOT],
                         g_min[M_ISLAS], g_max[M_ISLAS], g_min[M_ISLA], g_max[M_ISLA]);
            end
        end
    endtask

    task escribe_txt;       // texto de n bytes sin caracteres de control (los nulos se omiten)
        input [127:0] v;
        input integer n;
        integer   i;
        reg [7:0] c;
        begin
            for (i = n - 1; i >= 0; i = i - 1) begin
                c = v[i*8 +: 8];
                if ((c >= 8'h20) && (c < 8'h7F)) $write("%c", c);
                else if (c != 8'h00) $write(".");
            end
        end
    endtask

    task informe;
        begin
            $display("---------------- informe del receptor HDMI ----------------");
            $display("caracteres recibidos: %0d; cuadros completos: %0d; pixeles: %0d", t, n_cuadros, n_pix_total);
            if (n_cuadros > 0) begin
                $display("video : %0d..%0d x %0d..%0d totales, %0d..%0d x %0d..%0d activos, %0d..%0d ciclos por cuadro",
                         g_min[M_HTOT], g_max[M_HTOT], g_min[M_VTOT], g_max[M_VTOT],
                         g_min[M_HACT], g_max[M_HACT], g_min[M_VACT], g_max[M_VACT], g_min[M_FCLK], g_max[M_FCLK]);
                $display("hsync : porche delantero %0d..%0d, anchura %0d..%0d, porche trasero %0d..%0d px, polaridad %0s",
                         g_min[M_HFP], g_max[M_HFP], g_min[M_HSW], g_max[M_HSW], g_min[M_HBP], g_max[M_HBP],
                         !hs_fijada ? "?" : hs_neg ? "negativa" : "positiva");
                $display("vsync : porche delantero %0d..%0d, anchura %0d..%0d, porche trasero %0d..%0d lineas (restos %0d..%0d, %0d..%0d, %0d..%0d px), a %0d..%0d px del hsync, polaridad %0s",
                         g_min[M_VFP], g_max[M_VFP], g_min[M_VSW], g_max[M_VSW], g_min[M_VBP], g_max[M_VBP],
                         g_min[M_VFP_R], g_max[M_VFP_R], g_min[M_VSW_R], g_max[M_VSW_R], g_min[M_VBP_R], g_max[M_VBP_R],
                         g_min[M_VS_OFF], g_max[M_VS_OFF],
                         !vs_fijada ? "?" : vs_neg ? "negativa" : "positiva");
                $display("enlace: periodos de control de %0d..%0d caracteres; %0d..%0d islas por cuadro, de %0d..%0d paquetes",
                         g_min[M_CTRL], g_max[M_CTRL], g_min[M_ISLAS], g_max[M_ISLAS], g_min[M_ISLA], g_max[M_ISLA]);
                $display("audio : %0d..%0d muestras por cuadro (media %0d.%03d)",
                         g_min[M_AUD], g_max[M_AUD], g_sum[M_AUD] / g_n[M_AUD],
                         ((g_sum[M_AUD] % g_n[M_AUD]) * 1000) / g_n[M_AUD]);
            end
            $display("paquetes desde el arranque: %0d (rotos %0d): nulos %0d, ACR %0d, audio %0d (%0d muestras), AVI %0d, AudioIF %0d, SPD %0d, GCP %0d, otros %0d",
                     n_pk_total, n_pk_malos, n_pk_nulo, n_pk_acr, n_pk_asp, aud_total, n_pk_avi, n_pk_aif, n_pk_spd, n_pk_gcp, n_pk_otro);
            if (n_acr > 0)
                $display("ACR   : N = %0d, CTS = %0d (primero %0d, min %0d, max %0d)", acr_n, acr_cts, acr_cts_primero, acr_cts_min, acr_cts_max);
            if (avi_n > 0)
                $display("AVI   : VIC %0d, M %0d (1=4:3, 2=16:9), Y %0d, ITC %0d, repeticion %0d", avi_vic, avi_m, avi_y, avi_itc, avi_pr);
            if (aif_n > 0)
                $display("AudIF : CT %0d, CC %0d, SF %0d, SS %0d, CA %02h", aif_ct, aif_cc, aif_sf, aif_ss, aif_ca[7:0]);
            if (spd_n > 0) begin
                $write("SPD   : fabricante \"");
                escribe_txt({64'd0, spd_vendor}, 8);
                $write("\", producto \"");
                escribe_txt(spd_producto, 16);
                $display("\", tipo %02h", spd_sdi[7:0]);
            end
            if (n_bloques_cs > 0)
                $display("estado de canal (izq.): %0d Hz, %0d bits, canal %0d; (der.): %0d Hz, %0d bits, canal %0d; %0d bloques",
                         f_fs_cs(cs_l_ult[27:24]), f_bits_cs(cs_l_ult[35:32]), cs_l_ult[23:20],
                         f_fs_cs(cs_r_ult[27:24]), f_bits_cs(cs_r_ult[35:32]), cs_r_ult[23:20], n_bloques_cs);
            $display("errores de protocolo: %0d  (X %0d, simbolo %0d, preambulo %0d, guarda %0d, codigo de video %0d, balance DC %0d, TERC4 %0d, isla %0d, BCH cabecera %0d, BCH subpaquete %0d, checksum IF %0d, paridad audio %0d, ACR %0d, sin control extendido %0d, CTL reservado %0d)",
                     n_err_total, n_err_x, n_err_sim, n_err_preamb, n_err_guarda, n_err_vcod, n_err_vdc, n_err_terc4,
                     n_err_isla, n_err_bch_cab, n_err_bch_sub, n_err_chk_if, n_err_par, n_err_acr, n_err_ctrl_ext, n_err_ctl);
            $display("desviaciones del estandar (%0s): periodos de control de menos de 12 caracteres %0d; preambulo+guarda de video sin pixeles %0d",
                     (estricto != 0) ? "cuentan como error" : "solo aviso", n_ctrl_corto, n_video_vacio);
            $display("avisos: paquete desconocido %0d, bloque IEC60958 %0d, estado de canal variable %0d, InfoFrame raro %0d, cabecera de audio rara %0d, paquetes de audio con menos de 4 muestras %0d, muestras planas %0d",
                     n_av_pk_desc, n_av_bloque, n_av_cs_cambia, n_av_if, n_av_asp, n_asp_incompleto, n_aud_plano);
            $display("bit 3 del canal 0 en el primer caracter de cada isla: a 0 en %0d islas, a 1 en %0d (en el resto de caracteres, a 0 en %0d)",
                     n_d3_primero_0, n_d3_primero_1, n_d3_resto_0);
            $display("------------------------------------------------------------");
        end
    endtask

    // Ultimo cuadro completo en PPM de texto (P3). Hay que llamarla despues de
    // ver nuevo_cuadro y antes de la primera linea activa del cuadro siguiente.
    task escribir_ppm;
        input integer fd;
        integer i, w, h;
        begin
            w = fb_w_ult;
            if ((w <= 0) || (fb_n_ult <= 0) || (fb_n_ult > FB_N))
                $display("[hdmi_rx] escribir_ppm: no hay cuadro completo (o no cabe en 2^FB_LOG2 pixeles)");
            else begin
                h = fb_n_ult / w;
                $fwrite(fd, "P3\n%0d %0d\n255\n", w, h);
                for (i = 0; i < w * h; i = i + 1)
                    $fwrite(fd, "%0d %0d %0d\n", fb[i][23:16], fb[i][15:8], fb[i][7:0]);
            end
        end
    endtask

endmodule
