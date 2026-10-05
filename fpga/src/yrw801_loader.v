// ============================================================================
// yrw801_loader.v — carga la wave ROM YRW801 (2 MB) de la flash SPI a la SDRAM
// al arranque, a traves del puerto HOST de wave_sdram.  (MoonTANG)
//
// El YMF278B necesita la YRW801: 2 MB de muestras PCM de los instrumentos GM.
// En el MoonSound real es una mask-ROM del chip; aqui vive en la flash de la
// placa y se copia a la SDRAM en el boot. El fichero lo aporta el usuario
// (copyright), grabado en FLASH_BASE.
//
// HANDSHAKE CON flash_rw (leccion cara, auditoria 2026-08-05):
//   NO se puede usar `data_ready` como nivel: flash_rw lo limpia UN CICLO
//   DESPUES de ver `rd`, y `dout` conserva mientras tanto el byte ANTERIOR.
//   Muestrear ahi devolvia el byte rancio -> la imagen aterrizaba DUPLICADA
//   (solo se leia 1 MB de los 2) o DESPLAZADA +1 segun la latencia -> las
//   tablas de cabecera del YRW801 quedaban descolocadas y toda la wavetable
//   sonaba a basura. Se usa el handshake COMPLETO POR `busy` (el mismo patron
//   validado en hardware del MSXimus, top.v:2988): pulso de rd -> esperar a
//   que busy SUBA (orden aceptada) -> esperar a que BAJE -> ahi el dato es
//   valido. Ademas `terminate` se mantiene a NIVEL, no en pulso: flash_rw solo
//   lo muestrea en STATE_WAIT_NEXT y un pulso de 1 ciclo se pierde.
//
// SUMA DE COMPROBACION (05/10/2026): se suman los bytes copiados y al acabar se
// comparan con la suma de la YRW801 de verdad (EXPECTED_SUM). Si no coincide,
// wl_sum_ok queda a 0 y la pantalla y el LED lo dicen: una flash en blanco (todo
// FF), una megaROM que dejo otro firmware en 0x200000 o una imagen incompleta
// suenan a basura o no suenan, y sin esto la carga parecia correcta. NO bloquea:
// wl_done sube igual y el FM funciona.
//
// WATCHDOG: si la flash o la SDRAM se atascan, se reintenta la copia entera
// hasta MAX_RETRIES y despues se sale con wl_error pegajoso — pero wl_done
// SIEMPRE acaba subiendo, para no dejar el motor en reset y la placa muda sin
// diagnostico. (Nunca saltar a DONE al primer timeout: eso daria por buena una
// YRW801 a medias = audio basura silencioso en vez de un fallo visible.)
// ============================================================================

module yrw801_loader #(
    parameter [23:0] FLASH_BASE  = 24'h200000,  // offset del YRW801 en la flash
    parameter [22:0] WAVE_SIZE   = 23'h200000,  // 2 MB
    parameter integer TIMEOUT    = 24'd8000000, // ~148 ms @54 MHz
    parameter integer MAX_RETRIES = 3,
    // suma de los 2 MB de la YRW801 (md5 42af93619160...): 270522894 = 101FDA0Eh.
    // Los bancos de pruebas, que copian 4 KB sinteticos, la cambian con defparam.
    parameter [31:0] EXPECTED_SUM = 32'h101FDA0E
) (
    input  wire        clk,          // clk_host (54 MHz)
    input  wire        rst_n,
    input  wire        start,        // arrancar (SDRAM lista)

    // ---- flash_rw (lado lectura) ----
    output reg  [23:0] flash_addr,
    output reg         flash_rd,
    input  wire [7:0]  flash_dout,
    input  wire        flash_data_ready,
    input  wire        flash_busy,
    output reg         flash_terminate,

    // ---- puerto HOST de wave_sdram ----
    output reg         wl_req_toggle,
    output reg         wl_we,
    output reg  [21:0] wl_addr,
    output reg  [7:0]  wl_wdata,
    input  wire        wl_done_toggle,

    // ---- estado ----
    output reg         wl_done,      // 1 = liberado el motor PCM
    output reg         wl_error,     // 1 = se agotaron los reintentos
    output reg         wl_sum_ok,    // 1 = la imagen copiada es la YRW801 (suma)
    output wire [2:0]  wl_dbg_state
);
    localparam [2:0] S_WAIT   = 3'd0,  // espera a flash lista + start
                     S_RDISS  = 3'd1,  // pulso de rd
                     S_RDBUSY = 3'd2,  // esperar a que busy SUBA (aceptada)
                     S_RDWAIT = 3'd3,  // esperar a que busy BAJE (dato valido)
                     S_WRISS  = 3'd4,  // emitir escritura a wave_sdram
                     S_WRWAIT = 3'd5,  // esperar done de wave_sdram
                     S_DONE   = 3'd6;

    reg [2:0]  st;
    reg [22:0] cnt;                    // bytes transferidos
    reg [7:0]  byte_r;
    reg        done_seen;
    reg [15:0] warm;                   // margen tras power-on de la flash
    reg [23:0] wdog;                   // watchdog de estado
    reg [1:0]  retries;
    reg [31:0] sum;                    // suma de los bytes copiados

    assign wl_dbg_state = st;

    // el watchdog se rearma en CADA cambio de estado
    reg [2:0] st_d;
    wire      st_changed = (st != st_d);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_WAIT; st_d <= S_WAIT;
            flash_addr <= FLASH_BASE; flash_rd <= 1'b0; flash_terminate <= 1'b0;
            wl_req_toggle <= 1'b0; wl_we <= 1'b0; wl_addr <= 22'd0; wl_wdata <= 8'd0;
            wl_done <= 1'b0; wl_error <= 1'b0; wl_sum_ok <= 1'b0; sum <= 32'd0;
            cnt <= 23'd0; byte_r <= 8'd0; done_seen <= 1'b0;
            warm <= 16'd0; wdog <= 24'd0; retries <= 2'd0;
        end
        else begin
            st_d     <= st;
            flash_rd <= 1'b0;                       // pulso por defecto
            wdog     <= st_changed ? 24'd0 : (wdog + 24'd1);

            // ---- watchdog: reintentar la copia ENTERA, o rendirse ----
            if (wdog >= TIMEOUT[23:0] && st != S_WAIT && st != S_DONE) begin
                flash_terminate <= 1'b1;            // cerrar la lectura en curso
                cnt   <= 23'd0;
                wdog  <= 24'd0;
                if (retries >= MAX_RETRIES[1:0]) begin
                    wl_error <= 1'b1;               // pegajoso
                    st <= S_DONE;                   // wl_done sube igualmente
                end
                else begin
                    retries <= retries + 2'd1;
                    warm <= 16'd0;
                    st   <= S_WAIT;                 // reintento completo
                end
            end
            else begin
                case (st)
                // --------------------------------------------------------
                S_WAIT: begin
                    flash_terminate <= 1'b0;
                    flash_addr <= FLASH_BASE;
                    cnt        <= 23'd0;
                    sum        <= 32'd0;
                    if (start && !flash_busy) begin
                        if (warm[15]) st <= S_RDISS;
                        else          warm <= warm + 16'd1;
                    end
                end
                // --------------------------------------------------------
                S_RDISS: begin
                    flash_rd <= 1'b1;               // pide el siguiente byte
                    st <= S_RDBUSY;
                end
                // --------------------------------------------------------
                //  handshake completo: primero busy SUBE (orden aceptada)...
                S_RDBUSY: if (flash_busy) st <= S_RDWAIT;
                // --------------------------------------------------------
                //  ...y luego BAJA: ahi flash_dout es el byte NUEVO
                S_RDWAIT: if (!flash_busy) begin
                    byte_r <= flash_dout;
                    sum    <= sum + {24'd0, flash_dout};
                    st <= S_WRISS;
                end
                // --------------------------------------------------------
                S_WRISS: begin
                    wl_addr       <= cnt[21:0];
                    wl_wdata      <= byte_r;
                    wl_we         <= 1'b1;
                    wl_req_toggle <= ~wl_req_toggle;
                    done_seen     <= wl_done_toggle;
                    st <= S_WRWAIT;
                end
                // --------------------------------------------------------
                S_WRWAIT: if (wl_done_toggle != done_seen) begin
                    if (cnt + 23'd1 >= WAVE_SIZE) begin
                        flash_terminate <= 1'b1;    // NIVEL, no pulso
                        wl_sum_ok <= (sum == EXPECTED_SUM);
                        st <= S_DONE;
                    end
                    else begin
                        cnt <= cnt + 23'd1;
                        st  <= S_RDISS;
                    end
                end
                // --------------------------------------------------------
                S_DONE: begin
                    flash_terminate <= 1'b1;        // se mantiene: nadie mas
                    wl_we   <= 1'b0;                //  vuelve a tocar la flash
                    wl_done <= 1'b1;                // libera el motor PCM
                end
                default: st <= S_WAIT;
                endcase
            end
        end
    end
endmodule
