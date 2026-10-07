// ============================================================================
// wv_to_sdram.v — puente entre los puertos wv_* / wv2_* y el controlador
// ip_sdram (embebida GW2AR-18, 32 bits), más inyección de auto-refresh. (MoonTANG)
//
// wave_sdram.v fue escrito para la SDRAM 16-bit del MSXimus (memory.v). La SDRAM
// EMBEBIDA de la Tang Nano 20K (GW2AR-18C) la sirve ip_sdram (de hra1129, PROBADO
// en esta placa en el cartucho V9968), que es de 32 bits y direcciona por PALABRA
// de 32 bits (bus_address[22:2], pines implícitos del encapsulado). Este shim
// traduce:
//   - Dirección de BYTE (wv_addr[21:0], 4 MB) -> palabra de 32b (wv_addr[21:2]).
//   - Lectura: devuelve la MEDIA-PALABRA de 16b que contiene el byte pedido
//     ({byte impar, byte par}), que es justo lo que espera wave_sdram (cache de
//     palabra); wave_sdram extrae luego el byte.
//   - Escritura: replica el byte a las 4 lanes y enmascara con DQM para escribir
//     SOLO la lane del byte (wv_addr[1:0]).
//
// Contrato wv_* (visto desde el cliente): mientras wv_req=1 hay una operación en
// curso; cuando termina se pulsa wv_done 1 ciclo con wv_dout válido; tras
// wv_done, el cliente baja wv_req. Todo en clk_108m.
//
// DOS CLIENTES, mismo contrato:
//   wv_*   wave_sdram (loader al arrancar, motor PCM después) -> bancos 0-1
//          (bus_address[22] = 0: la YRW801 y la RAM de muestras del OPL4)
//   wv2_*  RAM de muestras del ADPCM del Y8950 (adpcm_sdram) -> bancos 2-3
//          (bus_address[22] = 1: los 4 MB altos, que nadie más usa)
// Prioridad en ST_IDLE: refresco > wv > wv2. El dato vuelve por wv_dout
// (compartido: cada cliente lo toma SOLO con su propio done) y el fin por el
// done del cliente DUEÑO de la operación (owner), y solo si el dueño no bajó su
// req a mitad (operación abortada: ver "aborted"). Con wv2_req a 0 (variantes
// sin Y8950) el puente se comporta exactamente como el de un cliente.
//
// Contrato ip_sdram: bus_valid/bus_refresh sólo se muestrean con bus_ready=1
// (añadido MoonTANG); se mantienen 1 ciclo. Como bus_valid va REGISTRADO, tras
// emitir hay que esperar primero a que bus_ready CAIGA (aceptado) y luego a que
// vuelva a SUBIR (terminado) — si no, se lee el ready del propio ciclo de
// emisión. La lectura además señaliza fin con bus_rdata_en.
// ============================================================================

module wv_to_sdram #(
    parameter integer REFRESH_CYCLES = 780   // ciclos de clk_108m entre refrescos
) (
    input  wire        clk,           // clk_108m
    input  wire        rst_n,

    // ---- cliente 1: wave_sdram (wv_*) ----
    input  wire        wv_req,        // nivel: petición en curso
    input  wire        wv_we,
    input  wire [21:0] wv_addr,       // dirección de BYTE
    input  wire [7:0]  wv_wdata,
    output reg  [15:0] wv_dout,       // media-palabra {byte impar, byte par} (de los dos clientes)
    output reg         wv_done,       // pulso 1 ciclo
    output reg         sd_timeout,    // pegajoso: el watchdog llego a disparar

    // ---- cliente 2: RAM del ADPCM (wv2_*), bancos 2-3; a 0 si no se usa ----
    input  wire        wv2_req,
    input  wire        wv2_we,
    input  wire [21:0] wv2_addr,
    input  wire [7:0]  wv2_wdata,
    output reg         wv2_done,      // pulso 1 ciclo; el dato, en wv_dout

    // ---- lado ip_sdram (bus_*) ----
    output reg  [22:2] bus_address,
    output reg         bus_valid,
    output reg         bus_write,
    output reg         bus_refresh,
    output reg  [31:0] bus_wdata,
    output reg  [3:0]  bus_wdata_mask,
    input  wire [31:0] bus_rdata,
    input  wire        bus_rdata_en,
    input  wire        bus_ready
);
    localparam [2:0] ST_IDLE   = 3'd0,
                     ST_ACCEPT = 3'd1,   // esperando a que el controlador acepte (ready->0)
                     ST_RD     = 3'd2,   // esperando bus_rdata_en
                     ST_WR     = 3'd3,   // esperando fin de escritura (ready->1)
                     ST_REF    = 3'd4,   // esperando fin de refresh (ready->1)
                     ST_DONE   = 3'd5;   // el dueño recibio su done: esperar a que baje su req

    reg [2:0]  st;
    reg        half;                     // addr[1] latcheado (media-palabra)
    reg        was_ref;                  // la op emitida fue refresh
    reg        was_wr;                   // la op emitida fue escritura
    reg        owner2;                   // la op emitida es del cliente 2

    // ---------------------------------------------------------------------
    // WATCHDOG (auditoria 2026-08-05): si el controlador no responde, TODA la
    // cadena se queda colgada — wave_sdram parado en ST_REQ, el loader esperando
    // su done, wl_done a 0, el motor en reset y la placa muda sin sintoma. Este
    // es el punto CORRECTO donde ponerlo: esta en el fondo de la cadena, asi que
    // al desatascarlo se desatascan todos los clientes de arriba (loader Y motor).
    // Al disparar:
    //   - durante un REFRESCO: no hay cliente al que contestar; se vuelve a
    //     ST_IDLE (05/10/2026: antes iba a ST_DONE a esperar que bajase wv_req,
    //     y si habia una peticion encolada detras del refresco nadie le daba su
    //     done, wv_req no bajaba nunca y la cadena quedaba colgada para siempre:
    //     justo lo que el watchdog existe para evitar).
    //   - durante una LECTURA o ESCRITURA: se cierra con dato envenenado (FFFFh)
    //     y el done va SOLO al cliente dueño; luego ST_DONE espera a su req.
    // El contador solo corre en los estados vigilados (ACCEPT/RD/WR/REF): en
    // ST_IDLE (p. ej. los ~300 us del init de ip_sdram, con bus_ready = 0) y en
    // ST_DONE esta a 0. Antes contaba tambien ahi, y el valor acumulado se
    // evaluaba en el primer ciclo de ACCEPT: a 108 MHz no saltaba por pura
    // aritmetica (da la vuelta cada 8192), con otro init o FREQ si.
    // ---------------------------------------------------------------------
    localparam integer WDOG_LIMIT = 4096;   // ~38 us @108 MHz
    reg [12:0] wdog;
    reg [2:0]  st_d;
    wire       st_changed = (st != st_d);
    wire       wdog_fire  = (wdog >= WDOG_LIMIT[12:0]) &&
                            (st == ST_ACCEPT || st == ST_RD || st == ST_WR || st == ST_REF);

    // --- temporizador de refresh ---
    reg [15:0] ref_cnt;
    reg        ref_pending;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ref_cnt <= 16'd0; ref_pending <= 1'b0;
        end
        else begin
            if (ref_cnt >= REFRESH_CYCLES[15:0]) begin
                ref_cnt     <= 16'd0;
                ref_pending <= 1'b1;         // se pide; se limpia al emitirlo
            end
            else begin
                ref_cnt <= ref_cnt + 16'd1;
            end
            if (st == ST_ACCEPT && was_ref) ref_pending <= 1'b0;
        end
    end

    // req del dueño de la operacion en curso (para ST_DONE)
    wire owner_req = owner2 ? wv2_req : wv_req;
    // OPERACION ABORTADA: el dueño bajo su req antes de recibir el done (un
    // /RESET del MSX resetea adpcm_sdram, pero no este puente, que va con el
    // reset de encendido). La operacion se termina en la SDRAM, pero su done
    // NO se entrega: si el cliente ya hubiese vuelto a pedir, lo tomaria como
    // el de su peticion nueva (escritura dada por hecha sin hacerse, lectura
    // con el dato de otra operacion, incluso de otro cliente). wave_sdram nunca
    // baja su req a mitad, asi que para el cliente 1 no cambia nada.
    reg  aborted;
    wire owner_gone = aborted || !owner_req;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE;
            bus_valid <= 1'b0; bus_write <= 1'b0; bus_refresh <= 1'b0;
            bus_address <= 21'd0; bus_wdata <= 32'd0; bus_wdata_mask <= 4'hF;
            wv_dout <= 16'd0; wv_done <= 1'b0; wv2_done <= 1'b0;
            half <= 1'b0; was_ref <= 1'b0; was_wr <= 1'b0; owner2 <= 1'b0;
            aborted <= 1'b0;
            wdog <= 13'd0; st_d <= ST_IDLE; sd_timeout <= 1'b0;
        end
        else if (wdog_fire) begin
            // desatascar: cerrar la operacion en curso
            wdog       <= 13'd0;
            st_d       <= ST_IDLE;
            sd_timeout <= 1'b1;                  // pegajoso, al LED
            bus_valid  <= 1'b0;
            bus_refresh<= 1'b0;
            if (was_ref) begin
                st <= ST_IDLE;                   // refresco: nadie espera respuesta
            end
            else if (owner_gone) begin
                st <= ST_IDLE;                   // abortada: nadie espera el done
            end
            else begin
                wv_dout <= 16'hFFFF;             // dato envenenado
                if (owner2) wv2_done <= 1'b1;    // libera SOLO al dueño
                else        wv_done  <= 1'b1;
                st <= ST_DONE;                   // espera a que el dueño suelte
            end
        end
        else begin
            wv_done     <= 1'b0;     // pulsos por defecto a 0
            wv2_done    <= 1'b0;
            bus_valid   <= 1'b0;
            bus_refresh <= 1'b0;
            st_d        <= st;
            wdog        <= (st_changed || st == ST_IDLE || st == ST_DONE) ? 13'd0 : (wdog + 13'd1);
            if (!was_ref && (st == ST_ACCEPT || st == ST_RD || st == ST_WR) && !owner_req)
                aborted <= 1'b1;
            case (st)
            // ------------------------------------------------------------
            ST_IDLE: begin
                if (bus_ready) begin
                    if (ref_pending) begin
                        bus_refresh <= 1'b1;
                        was_ref     <= 1'b1;
                        was_wr      <= 1'b0;
                        st <= ST_ACCEPT;
                    end
                    else if (wv_req) begin
                        owner2      <= 1'b0;
                        aborted     <= 1'b0;
                        bus_address <= {1'b0, wv_addr[21:2]};    // bancos 0-1
                        half        <= wv_addr[1];
                        bus_write   <= wv_we;
                        bus_valid   <= 1'b1;
                        was_ref     <= 1'b0;
                        was_wr      <= wv_we;
                        if (wv_we) begin
                            // replica el byte a las 4 lanes; DQM=1 enmascara
                            bus_wdata      <= {wv_wdata, wv_wdata, wv_wdata, wv_wdata};
                            bus_wdata_mask <= ~(4'b0001 << wv_addr[1:0]);
                        end
                        else begin
                            bus_wdata_mask <= 4'h0;   // lectura: sin máscara
                        end
                        st <= ST_ACCEPT;
                    end
                    else if (wv2_req) begin
                        owner2      <= 1'b1;
                        aborted     <= 1'b0;
                        bus_address <= {1'b1, wv2_addr[21:2]};   // bancos 2-3
                        half        <= wv2_addr[1];
                        bus_write   <= wv2_we;
                        bus_valid   <= 1'b1;
                        was_ref     <= 1'b0;
                        was_wr      <= wv2_we;
                        if (wv2_we) begin
                            bus_wdata      <= {wv2_wdata, wv2_wdata, wv2_wdata, wv2_wdata};
                            bus_wdata_mask <= ~(4'b0001 << wv2_addr[1:0]);
                        end
                        else begin
                            bus_wdata_mask <= 4'h0;
                        end
                        st <= ST_ACCEPT;
                    end
                end
            end
            // ------------------------------------------------------------
            //  esperar a que el controlador tome la orden (sale de ready)
            ST_ACCEPT: begin
                if (!bus_ready) begin
                    if      (was_ref) st <= ST_REF;
                    else if (was_wr)  st <= ST_WR;
                    else              st <= ST_RD;
                end
            end
            // ------------------------------------------------------------
            ST_RD: begin
                if (bus_rdata_en) begin
                    wv_dout <= half ? bus_rdata[31:16] : bus_rdata[15:0];
                    if (owner_gone) st <= ST_IDLE;          // abortada: sin done
                    else begin
                        if (owner2) wv2_done <= 1'b1;
                        else        wv_done  <= 1'b1;
                        st <= ST_DONE;
                    end
                end
            end
            // ------------------------------------------------------------
            ST_WR: begin
                if (bus_ready) begin      // escritura completa: vuelve a ready
                    if (owner_gone) st <= ST_IDLE;          // abortada: sin done
                    else begin
                        if (owner2) wv2_done <= 1'b1;
                        else        wv_done  <= 1'b1;
                        st <= ST_DONE;
                    end
                end
            end
            // ------------------------------------------------------------
            ST_REF: begin
                if (bus_ready) st <= ST_IDLE;   // refresh no lleva done
            end
            // ------------------------------------------------------------
            //  solo se llega aqui tras ENTREGAR el done al dueño (una
            //  operacion abortada vuelve directamente a ST_IDLE)
            ST_DONE: begin
                if (!owner_req) st <= ST_IDLE;  // esperar a que el dueño suelte
            end
            default: st <= ST_IDLE;
            endcase
        end
    end
endmodule
