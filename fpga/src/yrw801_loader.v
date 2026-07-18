// ============================================================================
// yrw801_loader.v — carga la wave ROM YRW801 (2 MB) de la flash SPI de la Tang
// Nano 20K a la SDRAM al arranque, a través del puerto HOST de wave_sdram.
// (MoonTANG)
//
// El YMF278B (MoonSound) necesita la YRW801: 2 MB de muestras PCM de los
// instrumentos GM. En el MoonSound real es una mask-ROM del chip; aquí vive en
// la flash de la placa y se copia a la SDRAM en el boot (como los packs de BIOS:
// el fichero lo aporta el usuario por copyright — se graba en la flash en
// FLASH_BASE).
//
// Flujo: flash_rw (lectura continua 0x03, cada pulso de `rd` saca el byte
// siguiente) -> puerto host de wave_sdram (req_toggle/we/addr/wdata, done_toggle).
// wave_sdram arbitra esta escritura contra las lecturas del motor y las envía a
// la SDRAM por el shim wv_to_sdram. Mientras dura la carga, eng_rst_n del motor
// se mantiene bajo (wl_done=0) para que no lea muestras a medias.
//
// Reloj: clk_host (54 MHz), mismo dominio que el puerto host de wave_sdram y que
// flash_rw en este diseño.
// ============================================================================

module yrw801_loader #(
    parameter [23:0] FLASH_BASE = 24'h100000,  // offset del YRW801 en la flash
    parameter [22:0] WAVE_SIZE  = 23'h200000    // 2 MB
) (
    input  wire        clk,          // clk_host (54 MHz)
    input  wire        rst_n,
    input  wire        start,        // arrancar la carga (p.ej. tras lock de PLL)

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
    output reg         wl_done,      // 1 = YRW801 cargado; libera el motor
    output wire [2:0]  wl_dbg_state
);
    localparam [2:0] S_WAIT   = 3'd0,  // espera a flash lista + start
                     S_RDISS  = 3'd1,  // pulso de lectura de flash
                     S_RDWAIT = 3'd2,  // espera byte de flash
                     S_WRISS  = 3'd3,  // emite escritura a wave_sdram
                     S_WRWAIT = 3'd4,  // espera done de wave_sdram
                     S_DONE   = 3'd5;

    reg [2:0]  st;
    reg [22:0] cnt;                    // bytes transferidos
    reg [7:0]  byte_r;
    reg        done_seen;              // último wl_done_toggle observado
    reg [15:0] warm;                   // pequeña espera de arranque de la flash

    assign wl_dbg_state = st;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= S_WAIT;
            flash_addr <= FLASH_BASE; flash_rd <= 1'b0; flash_terminate <= 1'b0;
            wl_req_toggle <= 1'b0; wl_we <= 1'b0; wl_addr <= 22'd0; wl_wdata <= 8'd0;
            wl_done <= 1'b0; cnt <= 23'd0; byte_r <= 8'd0; done_seen <= 1'b0;
            warm <= 16'd0;
        end
        else begin
            flash_rd <= 1'b0;          // pulso por defecto
            case (st)
            // --------------------------------------------------------
            S_WAIT: begin
                flash_addr <= FLASH_BASE;
                cnt        <= 23'd0;
                if (start && !flash_busy) begin
                    if (warm[15]) begin        // margen tras power-on de la flash
                        flash_rd <= 1'b1;      // 1ª lectura (usa flash_addr)
                        st <= S_RDWAIT;
                    end
                    else warm <= warm + 16'd1;
                end
            end
            // --------------------------------------------------------
            S_RDISS: begin                     // siguiente byte del stream
                flash_rd <= 1'b1;
                st <= S_RDWAIT;
            end
            // --------------------------------------------------------
            S_RDWAIT: begin
                if (flash_data_ready) begin
                    byte_r <= flash_dout;
                    st <= S_WRISS;
                end
            end
            // --------------------------------------------------------
            S_WRISS: begin
                wl_addr       <= cnt[21:0];
                wl_wdata      <= byte_r;
                wl_we         <= 1'b1;
                wl_req_toggle <= ~wl_req_toggle;   // dispara la escritura
                done_seen     <= wl_done_toggle;   // valor previo del done
                st <= S_WRWAIT;
            end
            // --------------------------------------------------------
            S_WRWAIT: begin
                if (wl_done_toggle != done_seen) begin  // escritura completada
                    if (cnt + 23'd1 >= WAVE_SIZE) begin
                        flash_terminate <= 1'b1;
                        st <= S_DONE;
                    end
                    else begin
                        cnt <= cnt + 23'd1;
                        st  <= S_RDISS;            // pedir el siguiente byte
                    end
                end
            end
            // --------------------------------------------------------
            S_DONE: begin
                flash_terminate <= 1'b0;
                wl_we   <= 1'b0;
                wl_done <= 1'b1;                  // libera el motor PCM
            end
            default: st <= S_WAIT;
            endcase
        end
    end
endmodule
