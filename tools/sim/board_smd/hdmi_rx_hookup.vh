// ============================================================================
// hdmi_rx_hookup.vh - el receptor HDMI de verificacion (../hdmi/hdmi_rx_check.v)
// enganchado al diseño entero. Se incluye dentro del banco de la placa SMD
// (tb_smd) y del de la WonderTANG con HDMI (tb_board) cuando se compila con
// -DWITH_HDMI_RX. En los dos tops el bloque HDMI es la instancia u_av.
//
// El receptor toma los simbolos TMDS de 10 bits a la entrada del serializador
// (fpga.u_top.u_av.tmds_internal; sv2v lo deja en 30 bits, canal i en [i*10 +: 10])
// y, al final de la prueba, hdmi_final_checks comprueba:
//   - que cada pixel recibido es el que el vumetro le dio al transmisor;
//   - que las muestras de audio recibidas son, una a una y en su canal, las
//     que el transmisor tomo en cada flanco de clk_audio;
//   - geometria de 720x480p, ACR, estado de canal, AVI, Audio InfoFrame y
//     presencia de todo en todos los cuadros;
//   - BCH, checksums, paridades, preambulos, guardas y codigos TMDS.
//
// La copia de hdl-util/hdmi del repo tiene cuatro desviaciones de CEA-861 y
// HDMI 1.4 conocidas (ver ../hdmi/hdmi_cea861.patch). Aqui se aceptan a
// sabiendas, como en "run_hdmi.sh tolerante": ESTRICTO = 0 y porches
// delanteros de 15 px y 10 lineas en vez de 16 y 9.
// ============================================================================

    wire        hrx_hsync, hrx_vsync, hrx_de, hrx_en_cuadro, hrx_nuevo_cuadro, hrx_aud_valid;
    wire [3:0]  hrx_ctl;
    wire [23:0] hrx_rgb, hrx_aud_l, hrx_aud_r;
    wire [15:0] hrx_px, hrx_py;

    hdmi_rx_check #(.VERBOSE(0), .ESTRICTO(0)) rx (
        .clk_pixel (fpga.u_top.u_av.clk_pix), .rst (~fpga.u_top.u_av.rst_n_pix),
        .tmds0 (fpga.u_top.u_av.tmds_internal[ 9: 0]),
        .tmds1 (fpga.u_top.u_av.tmds_internal[19:10]),
        .tmds2 (fpga.u_top.u_av.tmds_internal[29:20]),
        .hsync (hrx_hsync), .vsync (hrx_vsync), .ctl (hrx_ctl),
        .de (hrx_de), .rgb (hrx_rgb), .px (hrx_px), .py (hrx_py), .en_cuadro (hrx_en_cuadro),
        .nuevo_cuadro (hrx_nuevo_cuadro),
        .aud_valid (hrx_aud_valid), .aud_l (hrx_aud_l), .aud_r (hrx_aud_r)
    );

    // ------------------------------------------------------------------
    //  Video: lo que entra al transmisor, por coordenada. Se lee en el flanco
    //  de BAJADA (rgb lleva medio ciclo quieto): rgb es el pixel del cx/cy del
    //  ciclo anterior.
    // ------------------------------------------------------------------
    reg [23:0] hrx_fb [0:720*480-1];
    reg [9:0]  hrx_cx = 10'h3FF, hrx_cy = 10'h3FF;
    always @(negedge fpga.u_top.u_av.clk_pix) begin
        if (hrx_cx < 720 && hrx_cy < 480) hrx_fb[hrx_cy * 720 + hrx_cx] = fpga.u_top.u_av.rgb;
        hrx_cx = fpga.u_top.u_av.cx;
        hrx_cy = fpga.u_top.u_av.cy;
    end

    integer hrx_pix_ok = 0, hrx_pix_mal = 0;
    always @(negedge fpga.u_top.u_av.clk_pix) if (hrx_de && hrx_en_cuadro) begin
        if (hrx_px < 720 && hrx_py < 480 && hrx_rgb === hrx_fb[hrx_py * 720 + hrx_px])
            hrx_pix_ok = hrx_pix_ok + 1;
        else begin
            hrx_pix_mal = hrx_pix_mal + 1;
            if (hrx_pix_mal <= 4)
                $display("  [hdmi] pixel (%0d,%0d): recibido %06h, enviado %06h",
                         hrx_px, hrx_py, hrx_rgb, hrx_fb[hrx_py * 720 + hrx_px]);
        end
    end

    // ------------------------------------------------------------------
    //  Audio: lo que el transmisor toma (cada flanco de subida de clk_audio, desde
    //  el principio: ya captura alguna muestra antes de salir de reset) y lo que
    //  sale del receptor
    // ------------------------------------------------------------------
    localparam integer HRX_N = 65536;
    reg [15:0] hrx_tx_l [0:HRX_N-1], hrx_tx_r [0:HRX_N-1];
    reg [15:0] hrx_rx_l [0:HRX_N-1], hrx_rx_r [0:HRX_N-1];
    integer    hrx_n_tx = 0, hrx_n_rx = 0, hrx_bajos = 0, hrx_tx_x = 0, hrx_tx_x_ult = -1, hrx_tx_on = -1;
    always @(posedge fpga.u_top.u_av.clk_audio_w) if (hrx_n_tx < HRX_N) begin
        hrx_tx_l[hrx_n_tx] = fpga.u_top.u_av.aud_l;
        hrx_tx_r[hrx_n_tx] = fpga.u_top.u_av.aud_r;
        if (fpga.u_top.u_av.rst_n_pix && hrx_tx_on < 0) hrx_tx_on = hrx_n_tx;   // primera con el transmisor en marcha
        if (fpga.u_top.u_av.rst_n_pix && ^{fpga.u_top.u_av.aud_l, fpga.u_top.u_av.aud_r} === 1'bx) begin
            if (hrx_tx_x == 0) $display("  [hdmi] t=%0t: el transmisor toma una muestra con X (L=%h R=%h)", $time, fpga.u_top.u_av.aud_l, fpga.u_top.u_av.aud_r);
            hrx_tx_x = hrx_tx_x + 1;
            hrx_tx_x_ult = hrx_n_tx;
        end
        hrx_n_tx = hrx_n_tx + 1;
    end
    always @(negedge fpga.u_top.u_av.clk_pix) if (hrx_aud_valid && hrx_n_rx < HRX_N) begin
        hrx_rx_l[hrx_n_rx] = hrx_aud_l[23:8];
        hrx_rx_r[hrx_n_rx] = hrx_aud_r[23:8];
        if (hrx_aud_l[7:0] !== 8'h00 || hrx_aud_r[7:0] !== 8'h00) hrx_bajos = hrx_bajos + 1;
        hrx_n_rx = hrx_n_rx + 1;
    end

    // la muestra recibida i tiene que ser la enviada k0 + i, con k0 cerca de la
    // salida de reset; se busca k0 y se exige que solo uno case con todo lo recibido
    integer hk, hi, hrx_k0, hrx_casan, hrx_mal, hrx_solo_l, hrx_en_vuelo;
    task hdmi_final_checks;
        begin
            $display("== M. HDMI en el cable (receptor de verificacion) ==");
            rx.informe;
            rx.comprobar_geometria(858, 525, 720, 480, 15, 62, 10, 6, 1, 1);
            // CTS: en la placa pixel y audio salen del mismo cristal (27 MHz y 54 MHz / 1125)
            // y vale 27000 exacto. Aqui los relojes salen de modelos con periodos redondeados
            // a ps (pixel 26,9993 MHz, audio 47,9962 kHz medidos) y da 27001,7: se tolera +/-2.
            rx.comprobar_acr(6144, 27000, 2);
            rx.comprobar_estado_canal(48000, 16);
            rx.comprobar_avi(3, 2);
            rx.comprobar_aif;
            rx.comprobar_presencia;

            hrx_k0 = -1; hrx_casan = 0;
            for (hk = 0; hk <= hrx_tx_on + 32 && hk < hrx_n_tx; hk = hk + 1) begin
                hrx_mal = 0;
                for (hi = 0; hi < hrx_n_rx && hk + hi < hrx_n_tx; hi = hi + 1)
                    if (hrx_rx_l[hi] !== hrx_tx_l[hk + hi] || hrx_rx_r[hi] !== hrx_tx_r[hk + hi]) hrx_mal = hrx_mal + 1;
                if (hrx_mal == 0) begin hrx_casan = hrx_casan + 1; if (hrx_k0 < 0) hrx_k0 = hk; end
            end
            hrx_solo_l = 0;
            for (hi = 0; hi < hrx_n_rx; hi = hi + 1)
                if (hrx_rx_l[hi] != 16'd0 && hrx_rx_r[hi] == 16'd0) hrx_solo_l = hrx_solo_l + 1;
            hrx_en_vuelo = hrx_n_tx - (hrx_k0 + hrx_n_rx);
            $display("         video: %0d pixeles recibidos iguales a los enviados, %0d distintos (%0d cuadros completos)",
                     hrx_pix_ok, hrx_pix_mal, rx.n_cuadros);
            $display("         audio: tomadas %0d (la %0d, primera con el transmisor fuera de reset; %0d con X), recibidas %0d, la primera recibida es la %0d, en camino %0d; %0d con solo el izquierdo",
                     hrx_n_tx, hrx_tx_on, hrx_tx_x, hrx_n_rx, hrx_k0, hrx_en_vuelo, hrx_solo_l);
            ok(rx.n_cuadros >= 1, "HDMI: llega al menos un cuadro completo (la prueba dura unos 37 ms)");
            ok(hrx_tx_x == 0, "HDMI: el transmisor no toma ninguna muestra con X");
            ok(hrx_pix_mal == 0 && hrx_pix_ok >= rx.n_cuadros * 720 * 480,
               "HDMI: cada pixel del cable es el que pinto el vumetro");
            ok(hrx_casan == 1 && hrx_k0 >= 0 && hrx_n_rx > 0,
               "HDMI: el audio del cable es, muestra a muestra y en su canal, el que se envio");
            ok(hrx_en_vuelo >= 0 && hrx_en_vuelo <= 12, "HDMI: ninguna muestra se queda atras");
            ok(hrx_solo_l > 100, "HDMI: el tramo de FM a la izquierda llega solo por el canal izquierdo");
            ok(hrx_bajos == 0, "HDMI: los 8 bits bajos de cada muestra de 24 van a cero");
            ok(rx.n_err_total == 0, "HDMI: ningun error de protocolo (BCH, checksums, paridad, TMDS)");
            ok(rx.n_fallos_chk == 0, "HDMI: geometria, ACR, estado de canal e InfoFrames correctos");
        end
    endtask
