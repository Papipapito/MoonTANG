// ============================================================================
// smd_bus.v — acceso al bus del MSX en la placa MSXhdmi_tn20k_smd. (MoonTANG)
//
// En esa placa el bus llega DIRECTO a la FPGA a traves de cuatro 74LVC245:
//   U1, U2, U4 (direcciones y control): DIR fijo, solo MSX -> FPGA.
//   U3 (datos D0-D7): /OE a masa (siempre conduce hacia un lado) y sentido en
//       `datadir` (pin 18, con R1 de 10k a 3V3):
//           datadir = 1 -> MSX -> FPGA (reposo)   datadir = 0 -> FPGA -> MSX
//
// ENTRADAS. Cada linea pasa por dos registros (sincronizador) y un filtro que
// solo acepta el cambio cuando dos muestras seguidas coinciden: un pico de
// ruido de menos de un ciclo de 54 MHz no llega al OPL4 como un falso /WR.
// Todas las lineas llevan el mismo retardo (~55-74 ns), asi que la relacion
// entre direccion, dato y /IORQ-/RD-/WR se conserva.
//
// LECTURAS (el MSX lee C4h-C7h o 7Eh-7Fh). Misma temporizacion que el firmware
// Asgard de jabadiagm, que es el que funciona en esta placa (slave_bus.v: girar
// el 245 unos 130 ns despues de /RD, soltar en el primer flanco tras /RD), con
// un escalon para que la FPGA y U3 no se pisen en el lado de la FPGA:
//   1. ~110-130 ns tras /RD: datadir baja y U3 se vuelve hacia el MSX;
//   2. un ciclo despues (~130-150 ns) la FPGA empieza a conducir el dato;
//   3. al subir /RD o /IORQ se suelta todo A LA VEZ en 18-37 ns: la FPGA deja
//      de conducir y U3 vuelve a mirar al MSX. Para soltar no se espera al
//      filtro de entradas: basta un registro directo del pin.
// INVARIANTE: la FPGA solo conduce D0-D7 con datadir = 0 (con datadir = 1 U3
// empuja esos mismos pines). Los dos salen de biestables, nunca de logica
// combinacional sobre el bus.
// `rd_active` ya viene del nucleo con la guarda de bus vivo (reloj del slot
// presente y sin /RESET), de modo que con el MSX apagado no se conduce nunca.
// ============================================================================
`default_nettype none

module smd_bus (
    input  wire        clk,             // clk_54m

    // ---- pines ----
    input  wire [7:0]  a_pin,           // A0-A7
    inout  wire [7:0]  d_pin,           // D0-D7 (lado FPGA de U3)
    input  wire        iorq_n_pin,
    input  wire        rd_n_pin,
    input  wire        wr_n_pin,
    output wire        datadir,         // 1 = MSX -> FPGA

    // ---- hacia el nucleo (dominio clk) ----
    output wire        iorq_n,
    output wire        rd_n,
    output wire        wr_n,
    output wire [7:0]  addr,
    output wire [7:0]  din,

    // ---- desde el nucleo ----
    input  wire [7:0]  rd_data,
    input  wire        rd_active,

    output wire        driving          // 1 = el cartucho conduce D0-D7 hacia el MSX
);
    // ------------------------------------------------------------------
    //  Entradas: 2 registros + filtro de dos muestras iguales
    // ------------------------------------------------------------------
    localparam W = 8 + 8 + 3;
    wire [W-1:0] raw = {a_pin, d_pin, iorq_n_pin, rd_n_pin, wr_n_pin};
    (* syn_preserve = 1 *) reg [W-1:0] s0 = {W{1'b1}};
    (* syn_preserve = 1 *) reg [W-1:0] s1 = {W{1'b1}};
    reg [W-1:0] prev = {W{1'b1}};
    reg [W-1:0] flt  = {W{1'b1}};
    integer i;
    always @(posedge clk) begin
        s0   <= raw;
        s1   <= s0;
        prev <= s1;
        for (i = 0; i < W; i = i + 1)
            if (prev[i] == s1[i]) flt[i] <= s1[i];
    end
    assign addr   = flt[18:11];
    assign din    = flt[10:3];
    assign iorq_n = flt[2];
    assign rd_n   = flt[1];
    assign wr_n   = flt[0];

    // ------------------------------------------------------------------
    //  Lectura: sentido de U3 y triestado de la FPGA
    // ------------------------------------------------------------------
    // el ciclo sigue vivo en los pines: un solo registro, para soltar pronto
    (* syn_preserve = 1 *) reg live = 1'b0;
    always @(posedge clk) live <= ~rd_n_pin & ~iorq_n_pin;

    wire go = rd_active & live;
    reg  go_d = 1'b0, turn = 1'b0, oe = 1'b0;
    always @(posedge clk) begin
        go_d <= go;
        turn <= go & go_d;              // U3 hacia el MSX
        oe   <= go & go_d & turn;       // un ciclo despues, la FPGA conduce
    end

    assign datadir = ~turn;
    assign d_pin   = (oe & turn) ? rd_data : 8'hzz;
    assign driving = turn;
endmodule

`default_nettype wire
