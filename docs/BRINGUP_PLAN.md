## MoonTANG — consolidated bring-up work order
(GW2AR-18C / Tang Nano 20K on WonderTANG. Analysis only; no files were modified.)

---

## 1. Must fix before flashing — ordered by risk

### 1.1 Pinout targets the wrong carrier — DO NOT POWER A WonderTANG WITH THE CURRENT BITSTREAM
**File:** `C:/Users/alber/proyectosAI/msx/MoonTANG/fpga/constraints/moontang.cst` (whole file) + bus front-end in `fpga/src/moontang_top.v`

`moontang.cst` is a copy of hra1129's V9968 cartridge pinout (`V9968_Cartridge/.../tangnano20k_vdp_cartridge.cst`), not the WonderTANG. Verified conflict map against the real WonderTANG 2.0b pinout in `C:/Users/alber/proyectosAI/msx/SlotDoctor/fpga/constraints/slotdoctor.cst`:

| MoonTANG signal (pin) | WonderTANG net | Consequence |
|---|---|---|
| `audio_l` (52) | `DATADIR` | 108 MHz PDM flips the data-bus '245 direction every cycle |
| `audio_r` (53), `slot_intr` (71), `slot_wait` (72), `ws2812_led` (79) | `cd[6]`, `cd[5]`, `cd[4]`, `cd[3]` | 4 DRIVE=8 outputs vs '245 outputs → sustained contention |
| `oe_n` (20) tied `1'b0` (`moontang_top.v:272`) | `msel_n[1]` | mux '245 permanently enabled; with `msel_n[2]`(19)=0 at idle, two mux '245s drive `mp[7:0]` at once |
| `slot_d[7]` (73) | `int_n` (2N3904 base) | drives /INT |
| `slot_d[3:0]` (77/27/28/29) | `mp[0]/mp[1]/mp[2]/mp[5]` | '245 outputs into the FPGA |

Architecturally worse: the WonderTANG has **no direct A0-A15 and no direct /IORQ** — they are time-multiplexed onto `mp[7:0]` selected by `msel_n[2:0]` (`SlotDoctor/fpga/src/slot_probe.v:1-28`; `msel_n=3'b011` → `mp[1]`=/IORQ, `mp[7]`=/M1). `moontang_top.v:35-39` declares flat `slot_a[7:0]` + `slot_iorq_n`, so **it cannot decode a single I/O port on a WonderTANG.**

Also: `slot_a[3]` (pin 42 = `wait_n`) and `slot_d[7]` (pin 73 = `int_n`) are both `PULL_MODE=UP` in `moontang.cst`; both go through inverting 2N3904s, so the machine would boot with /WAIT and /INT asserted (frozen).

**Do:**
1. Re-derive `moontang.cst` from `SlotDoctor/fpga/constraints/slotdoctor.cst`.
2. Write a bus front-end that drives `msel_n[2:0]` and demuxes `mp[7:0]` into {A0-A7, A8-A15, ctrl}; reuse `SlotDoctor/fpga/src/slot_probe.v` (7-state 108 MHz scanner). /IORQ = ctrl bit 1, /M1 = ctrl bit 7 → the `s_m1_n = 1'b1` tie at `moontang_top.v:125` can go.
3. /WAIT → pin 42, /INT → pin 73, both `PULL_MODE=DOWN` (active-high from FPGA is correct for the inverting NPN).
4. Move audio off pin 52. Pins 85/80 are documented free on a bare WonderTANG — but confirm on the schematic that SOUNDIN (MSX edge 49) is actually routed before committing; otherwise external RC to a jack.
5. If the intended carrier is actually hra1129's V9968 PCB, say so plainly in `README.md` and the `.cst` header instead of "verify before flashing".

> Note: moving audio off pin 52 also removes the reason `-use_sspi_as_gpio` is required (see 1.5).

---

### 1.2 `clk_sdram` has NO phase shift — the phase knob is wired to nothing
**File:** `fpga/clocks/pll_main.v:41, 53-54`

`PSDA_SEL="1000"` (180°) is set, but `DYN_DA_EN="true"` makes the rPLL take the **dynamic** `PSDA[3:0]` port, which is tied to `4'b0000` → CLKOUTP = 0°, i.e. `O_sdram_clk` is in phase with the clock that launches commands/address/write data, and `ff_sdr_read_data` captures `IO_sdram_dq` on that same edge (`ip_sdram_tangnano20k_c.v:442-449, 463`). Gowin's `prim_sim.v` confirms: with `DYN_DA_EN=="true"`, `ps_dly = clkout_period*PSDA/16`, and `PSDA_SEL` is dead.

Reference convention on the same device: `V9968_Cartridge/.../gowin_rpll2/gowin_rpll2.v` (the 180° SDRAM clock) = `PSDA_SEL="1000"` + `DYN_DA_EN="FALSE"` + FDLY tied to vcc; `gowin_rpll.v` (no shift) = `"0000"` + `"true"`.

```verilog
defparam rpll_inst.PSDA_SEL   = "1000";
defparam rpll_inst.DYN_DA_EN  = "false";   // <-- was "true"
// and: wire gw_vcc = 1'b1;  .FDLY({gw_vcc,gw_vcc,gw_vcc,gw_vcc})   // 0000 is not a legal FDLY code
```
Verify in the post-synthesis netlist that the primitive really carries `PSDA_SEL=1000, DYN_DA_EN=false`. `PSDA_SEL` is a synthesis-time defparam — sweeping 0110/1000/1010 means one bitstream per value, not a runtime knob. Leave `pll_eng.v` alone (`"0000"`+`"true"`, unused CLKOUTP = correct).

---

### 1.3 `sigma_delta_dac.v` is broken — the only audio path emits noise, not music
**File:** `fpga/src/sigma_delta_dac.v:18-37` *(found independently by two investigators; both reproduced in iverilog)*

Input is offset-binary (`u = din + 16'sh8000`, 0..65535, zero-extended) while feedback is bipolar (`fb = dout ? +32768 : -32768`), so no fixed point exists for any `din > 0`; the 19-bit accumulators also wrap. Measured duty over the full input range: **0.47..0.55** (expected 0.00..1.00). Sine correlation: gain −0.069× ideal and sign-inverted. It is instantiated twice at `moontang_top.v:300-301` driving `audio_l/audio_r`.

Replace with the canonical 1st-order modulator (verified duty error 0.00000 at nine sweep points, AC gain 0.9999×):
```verilog
wire [15:0] u = din + 16'sh8000;
reg  [16:0] acc;
always @(posedge clk or negedge rst_n)
    if (!rst_n) begin acc <= 17'd0; dout <= 1'b0; end
    else begin acc <= {1'b0, acc[15:0]} + {1'b0, u}; dout <= acc[16]; end
```
**Do not** try to salvage the 2nd-order topology: both "minimal repairs" (offset-binary feedback + 24-bit accumulators; and saturation clamps) were tested and still fail the sweep. At 108 MHz vs ~44.1 kHz the OSR is ~2450 — 1st order gives ~100 dB in-band SNR, ample. Update the module header comment ("2 orden para mejor SNR" becomes false). **Gate:** DC ramp sweep must be monotonic ~0.00→~1.00 before burning a bitstream.

---

### 1.4 `yrw801_loader` re-latches a stale byte — YRW801 image lands corrupt
**File:** `fpga/src/yrw801_loader.v:88-98` *(found independently by two investigators)*

`S_RDISS` registers `flash_rd<=1` and goes to `S_RDWAIT` in the same edge; `flash_rw` only clears `r_data_ready` on the *next* edge (`flash_rw.v:275-291`, `STATE_WAIT_NEXT`), and `dout` still holds the previous byte. Both modules are on `clk_54m` with no synchronizer (`moontang_top.v:238, 248`). Simulated: SDRAM comes out **byte-doubled** (only 1 MB of the 2 MB image ever read) at short host latency, or **shifted +1** at long latency — the mode flips with P&R. Either way the YRW801 instrument header tables are misaligned and the whole wavetable is garbage. The hardware-validated MSXimus loader (`MSX_up/fpga/top.v:2988-2990`) never touches `data_ready`; it uses a `flash_busy` full handshake.

**Preferred (proven pattern):** after pulsing `flash_rd`, wait for `flash_busy` to rise, then for `!flash_busy`, then sample `flash_dout`.

**Minimal in-place alternative** — register the ready and require a rising edge (covers the first read out of `S_WAIT` automatically):
```verilog
reg dr_d;
dr_d <= flash_data_ready;                      // unconditional, every cycle
...
S_RDWAIT: if (flash_data_ready && !dr_d) begin byte_r <= flash_dout; st <= S_WRISS; end
```
The one-liner circulating as `flash_data_ready && !flash_rd_d` is **off by one** — `flash_rd_d` is still 0 in the offending cycle. If you use an `S_RDACK` state instead, its condition must be `!flash_data_ready || flash_busy`, and guard the rd issue with `!flash_busy` so it cannot deadlock.

**Gate:** sim against `flash_rw.v` with a ramp flash model (`byte k = k`); assert 2^21 strictly-incrementing distinct writes and exactly `WAVE_SIZE` bytes pulled from flash, at host write latencies 3/8/20/40/200.

---

### 1.5 `build.tcl` turns JTAG/DONE/READY/CPU into GPIO — the "Gowin Device not found" trap
**File:** `fpga/build.tcl:69`

Empirically verified with `gw_sh` on a stub of MoonTANG's exact port list: building with only MSPI+SSPI places cleanly, so **no pin needs JTAG/CPU/DONE/READY as GPIO**; the only difference in the produced `.fs` is the header flag `//JTAGAsRegularIO: OFF → ON` plus one config word. That flag disconnects the JTAG controller once the core runs — the same interface the onboard BL616 uses to program the board (already burned once on the Console 60K, per `msximus_flasheo_jtag_console60k.md`; recoverable via erase+reconfig, but a wasted session).

```tcl
set_option -use_mspi_as_gpio 1 -use_sspi_as_gpio 1
```
MSPI is needed for the flash pins; SSPI is needed **only because `audio_l` sits on pin 52** (removing it gives `PR2017: audio_l cannot be placed ... dedicated pin (SSPI)`). If 1.1 moves audio off 52, re-check whether SSPI is still required.

---

### 1.6 `clk_opl3` from the raw crystal pad → 77 hold violations on the FM sample bus
**File:** `fpga/src/moontang_top.v:74, 136`

`wire clk_27m = clk;` (raw pad) feeds `.clk_opl3()`, while `.clk_host(clk_54m)` comes from `pll_main`. Different insertion delays → **clock skew −2.569 ns** on every clk27→CLKOUTD path in `fpga/impl/pnr/project_tr_content.html`: worst −2.065 ns on `u_opl4fm/pcm_opl3_*_s0/Q → pcm_out_*_s0/D` (the bare 16-bit FM sample bus, crossed by a plain register), plus `u_opl3/host_if/afifo/rgray_*` and `timers/ft2 → dout_sync`. Summary: "Numbers of Hold Violated Endpoints: 77". MSXimus deliberately moved 27 MHz *into* the main PLL for exactly this (`MSX_up/fpga/top.v:281,325` — "hermano de clk_54m"; its report shows **1** hold violation).

`pll_main`'s four outputs are all taken (108 / 108-shifted / 54 / hard-wired /3), so you cannot "add a 27 MHz output". Use a CLKDIV, as MoonTANG's TN20K ancestor did:
```verilog
CLKDIV u_div27 (.CLKOUT(clk_27m), .HCLKIN(clk_108m), .RESETN(lock_main), .CALIB(1'b0));
defparam u_div27.DIV_MODE = "4";     // 108/4 = 27 MHz
defparam u_div27.GSREN    = "false";
```
and delete `wire clk_27m = clk;`. **Do not** add a third rPLL at 27 MHz — that is the unrelated-PLL topology MSXimus's `_84` note blames for the unreliable OPL3 writes of builds _82/_83. **Gate:** no clk27→CLKOUTD entries left in the Hold table.

---

### 1.7 `/WAIT` asserted from SDRAM-init with no timeout
**File:** `fpga/src/moontang_top.v:275`

`assign slot_wait = sdram_init_busy | ~opl4pcm_wait_n;` (active-high = stall). `sdram_init_busy = !ff_sdr_ready`, and `ip_sdram` is held in reset by `por_reset_n`, gated on `lock_main & lock_eng`. If either PLL never locks, /WAIT is asserted from power-on forever → "the MSX is dead", the most expensive symptom to debug. It also buys nothing: the multi-second YRW801 load does **not** hold /WAIT (the engine is held in reset by `eng_rst_n = bus_reset_n & wl_done`), so a 310 µs init stall protects nothing. MSXimus v2.1 composes `WAIT_n` with **no** memory-init term at all (`MSX_up/fpga/top.v:1386-1394`).

```verilog
assign slot_wait = ~opl4pcm_wait_n;   // el motor ya limita el stall a ~19 us (wto)
```
**Do not** touch `opl4pcm_wait_n` — it already has a ~19 µs watchdog (`opl4_pcm.v:197-213`, `wto[10]`), byte-identical to validated MSXimus code. **Do not** tie `slot_wait` to 0 for bring-up: that kills the wave-read stretch the Z80 needs.

---

### 1.8 `flash_terminate` is a 1-cycle pulse `flash_rw` can miss
**File:** `fpga/src/yrw801_loader.v:112, 123`

`flash_rw` samples `terminate` only in `STATE_WAIT_NEXT` (`flash_rw.v:288`); the loader asserts it for exactly one cycle on entering `S_DONE`. Timing analysis shows the SDRAM write round-trip (~13 clk_54m) is *shorter* than `STATE_READ_DATA`+`DATA_END` (~18), so the pulse regularly lands mid-byte and is swallowed → CS stays low, flash parked in active read current. Low harm (nothing re-touches the flash), but it is one line, and MSXimus hit this exact hazard on hardware (`MSX_up/fpga/top.v:~2872`, held 256 cycles unconditionally):

```verilog
S_DONE: begin
    flash_terminate <= 1'b1;   // LEVEL, not a pulse: flash_rw only samples it in STATE_WAIT_NEXT
    wl_we <= 1'b0; wl_done <= 1'b1;
end
```
**Do not** gate it as `~flash_busy` — MSXimus documents that as the broken _90-_94 form (`busy` is also 1 mid-byte). Holding it forever is safe: no post-`STATE_DONE` state re-samples `terminate`.

---

## 2. Should fix — same build

### 2.1 Minimum observability (do not skip — this is what makes the session diagnosable)
**Files:** `fpga/src/moontang_top.v:169, 244, 306`, `fpga/src/opl4_pcm.v:837`, `fpga/constraints/moontang.cst`

Today: `ws2812_led = 1'b0` (306, constant), `.wl_dbg_state()` open (244), `.diag()`/`.dbg_tx()` open (169), `button[1:0]` never read. Nothing exposes `pll_locked`, `sdram_init_busy`, `wl_done` or loader state. (`wave_sdram`'s `.diag()/.ready()` are hardwired constants — ignore those.)

- **LED, cheapest:** replace `assign ws2812_led = 1'b0;` with a blink/heartbeat encoder on pin 79 encoding `{pll_locked, ~sdram_init_busy, wl_done}` + a slow heartbeat. If you want real RGB, port `MSX_up/fpga/src/ws2812.v` (`NUM_LEDS(1), CLK_FRE(27)`) — **not** `V9968_Cartridge/.../ip_ws2812_led.v` unmodified, whose bit timings are hardcoded for an 85 MHz clock (T1H would be ~1.26 µs from clk_54m, out of spec).
- **Wire `.wl_dbg_state()`** (244) into that encoder.
- **UART telemetry:** connect `.dbg_tx()` to a top-level output, `IO_LOC` it (pin 69 = TN20K FPGA→BL616 USB-serial TX, per `SlotDoctor/fpga/constraints/slotdoctor.cst:113-116` and `MSXgoauldSD_tn20k/fpga/tang9k.cst:88` — verify the WonderTANG doesn't drive it), and copy `MSX_up/tools/dbg_reader.py` into `MoonTANG/tools/`. Note `dbg_tx` is clocked under `erst_n = bus_reset_n & wl_done`, so it is **silent while the loader is stuck** — it is a post-load engine probe, not a boot probe.
- **Baud:** `DBG_BAUD_DIV = 9'd326` assumes 37.5 MHz; MoonTANG's `clk_eng` is 37.125 MHz → 113.9 kbaud (−1.1%, decodes, but set `9'd322` while you're there).
- **Restore `fr[15]`** (`opl4_pcm.v:837`), upstream commit `127eb28`: `fr[15] <= {ifw_hits, alive};` — currently `{vid_s1, alive}` from the abandoned `_114diag` probe, and since `vid_diag` is tied to `4'd0` that nibble is dead zeros, while `dbg_reader.py` decodes byte 15 as `{ifw,alive}`. `ifw_hits` is the in-flight-watchdog sentinel — exactly the counter you want during first bring-up of an unproven SDRAM wave path.
- Free: give `button[0]` (pin 88) a job — LED page select or loader restart.

### 2.2 Watchdogs — put them at the *bottom* of the chain
**Files:** `fpga/src/wv_to_sdram.v:131-160`, `fpga/src/yrw801_loader.v:93-120`

No timeout anywhere in flash → loader → wave_sdram → wv_to_sdram → ip_sdram. Any stall leaves `wl_done=0`, `eng_rst_n` low, engine in reset, board silent.

- **Primary — `wv_to_sdram`:** ~16-bit stall counter, reset on every state change, fires after ~4096 clk_108m (~38 µs) in `ST_ACCEPT/ST_RD/ST_WR/ST_REF`. On fire: pulse `wv_done` with poison data, return to `ST_IDLE`, set sticky `sd_timeout`. This unwinds `wave_sdram`'s `ST_REQ` and every client above it — including the engine path, not just boot. A loader-only timeout is **insufficient**: it releases `wl_done` while `wave_sdram` is still parked in `ST_REQ`, moving the hang instead of clearing it.
- **Secondary — loader `S_RDWAIT`/`S_WRWAIT`:** 24-bit counter (~0.31 s @54 MHz). Mirror MSXimus policy (`top.v:2910-2912`, `wl_tcnt[21]` ~39 ms): **retry the whole copy** N times, then fall through to `S_DONE` with sticky `wl_error` so `wl_done` always eventually rises. Do **not** silently jump to `S_DONE` on first timeout — that raises `wl_done` over a half-loaded YRW801, converting a visible hang into silent garbage audio.
- Surface `{wl_error, sd_timeout, wl_dbg_state}` on the LED from 2.1.

### 2.3 SDC: name the PLL clocks, group the two PLLs, silence the phantom OPL3 clocks
**File:** `fpga/constraints/moontang.sdc` (currently 21 lines: 2 `create_clock` + 5 `set_false_path`, nothing else)

Two independent PLLs (`pll_main` 864 MHz VCO, `pll_eng` 594 MHz VCO) with no relationship declared. Gowin auto-derives both as generated clocks off `clk27` and therefore times `clk_eng ↔ clk_108m` **synchronously against a 0.842 ns edge alignment** (the common period of 37.125 and 108 MHz) — setup path #25 is `u_pll_eng/CLKOUT → u_pll_main/CLKOUT` at **−1.805 ns**, and that is the *last line the report prints* (`report_timing -max_paths 25`), so anything worse is invisible. Separately, three tool-invented 100 MHz "Base" clocks inside opl3 (`control_operators/n175_41`, `n633_41`, `envelope_generator/n129_5`, from the 21 inferred latches) produce setup slacks to −15.724 ns against a fictitious requirement; they are inherited from the byte-identical opl3 sources and MSXimus's SDC says nothing about them (don't go looking for a precedent).

```tcl
create_clock -name clk_108m  -period  9.259 [get_pins {u_pll_main/rpll_inst/CLKOUT}]
create_clock -name clk_sdram -period  9.259 [get_pins {u_pll_main/rpll_inst/CLKOUTP}]
create_clock -name clk_54m   -period 18.518 [get_pins {u_pll_main/rpll_inst/CLKOUTD}]
create_clock -name clk_eng   -period 26.936 [get_pins {u_pll_eng/rpll_inst/CLKOUT}]

set_clock_groups -asynchronous \
  -group [get_clocks {clk_108m clk_sdram clk_54m}] \
  -group [get_clocks {clk_eng}] \
  -group [get_clocks {clk27}] \
  -group [get_clocks {clk14m}]

set_clock_groups -asynchronous -group [get_clocks { \
  u_opl4fm/u_opl3/channels/control_operators/n175_41 \
  u_opl4fm/u_opl3/channels/control_operators/n633_41 \
  u_opl4fm/u_opl3/channels/control_operators/operator/envelope_generator/n129_5 }]
```
`clk_sdram` must stay in the same group as `clk_108m`. Verify in the PnR log that each `get_clocks` matched >0 objects (empty matches are silently dropped). Re-run STA with `-max_paths` well above 25 and treat the residual list as a hard gate. Note 1.6 (CLKDIV) removes the `clk27` group's hold violations structurally — the `set_clock_groups` on `clk27` alone would only *hide* them, so do 1.6 as well.

### 2.4 Stale comments that will mislead the next auditor
- `fpga/src/opl4fm.v:20-21` claims "33.75 MHz … CLK_DIV_COUNT=682 → fs 49.487 kHz". Actual: `opl3_pkg.sv:34` has `CLK_DIV_COUNT = 545` at 27 MHz → 49.541 kHz, **+0.05%** vs the YMF278B nominal 49.516 kHz (not −0.35% vs 49.716 kHz — that's the YMF262 rate). Also fix line 30's `// 33.75 MHz (pll_3375)`. Same stale text exists in MSXimus; fix both. No RTL change.
- `fpga/src/wave_sdram.v:16-17, 35` still assert "TODOS los relojes son de la familia del PLLA → paths síncronos" and "clk_eng36 = clk_108m/3". False in MoonTANG (separate `pll_eng`). The 3FF toggle discipline keeps it safe, but the stated premise no longer holds — say so.

---

## 3. Bring-up checklist — verify on hardware, not in code

1. **Before power:** confirm every re-derived pin against the *physical* WonderTANG schematic, not the KiCad netlist (`SlotDoctor/hw/golden_netlist.csv` net names are the ground truth used here). Check with a meter that pin 52 is not DATADIR on your board revision.
2. **/WAIT and /INT NPN bases:** the WonderTANG lacks base pulldowns on Q1/Q2 (`SlotDoctor/hw/README.md` documents this as "un defecto real de la WonderTANG"; their PCB adds R7/R8 10k). During the ~200 ms FPGA config window the bases float and /WAIT+/INT can self-assert regardless of RTL. Verify with a scope on cold boot, or fit the pulldowns.
3. **Programmability check:** after flashing, confirm the BL616 can still re-program the board with the core running (validates 1.5).
4. **SDRAM phase sweep:** rebuild one bitstream per `PSDA_SEL` in {0110, 1000, 1010} and pick by a loader checksum, not by ear. Confirm in the netlist that `PSDA_SEL` actually reached the primitive.
5. **YRW801 integrity on hardware:** read back a known offset from SDRAM (or add a CRC in the loader) and compare against the flash image. Do not judge the wavetable by ear before this passes.
6. **Discriminator order:** `opl4fm` is gated only by `bus_reset_n`, so **FM on ports C4-C7 sounds even if the loader is wedged.** FM working + wavetable silent = wave chain; FM silent too = bus/pinout. `wave_status` is *not* a discriminator (reads 0 both in engine-reset and healthy-idle).
7. **DAC output:** scope pins for a real PDM waveform before blaming the OPL4/SDRAM. Confirm the external RC low-pass is actually populated.
8. **Telemetry:** open the UART at 115200 8N1 with `tools/dbg_reader.py` and confirm `alive` is ticking and `ifw_hits` is 0 before evaluating audio quality.
9. **Flash pin map:** `moontang_top.v:24-26` flags the flash pins as unverified. A wrong `flash_miso` is the single most likely first-session fault — the loader watchdog + LED from §2 turn that from a dead board into a readable symptom.
10. **Read the violation list before flashing.** Project rule: do not flash a build whose timing report you have not read.

---

## 4. Explicitly NOT porting

| Item | Reason (one line) |
|---|---|
| `MSX_up_v3` shadow_b0/b1 → BSRAM (`opl4fm.v`) | GW5AT-60B SSRAM silicon defect + 60K placement pressure; GW2AR-18 SSRAM is fine and already places (483 RAM16, 60% CLS). |
| `_121diag` negedge half-stage on shadow writes (79e6b05) | 60K −0.02 ns hold, inside the ~40 ps FF→RAM floor the project itself now *accepts* (`tools/gate_check.ps1`); MoonTANG's own GW2AR-18 report shows 0 hold endpoints on `CLKOUTD`. |
| `opl4_pcm.v` cache → BSRAM + `rd_edge_d1` pipeline + prefetch guard (88f59ba/bbc223a) | Pure 60K SSRAM-removal area work; adds latency and a documented *new* stale-tag degradation. MoonTANG's cache is bit-identical to hardware-proven v2.1. |
| `opl4_pcm.v` `sl_last` → `sl_mem`/`sl_hi` + `else sl_q <=` (3f44593) | Fixes Arora-V PA2122 (BSRAM WRITE_MODE), a restriction only reached because v3 forced the array into BSRAM. |
| `ymf278b_gowin.v` RAM-primitive rewrite (88f59ba/17419ba/a356640/8c0698d) | 60K BSRAM budget/PA2017; the two "bugs" a356640 mentions were *introduced* by that new sweep design, not pre-existing. |
| `opl3/` `USE_BRAM(1)` in channels/phase_generator/mem_multi_bank | 60K BSRAM migration, opt-in (`USE_BRAM` defaults 0); MoonTANG's opl3 is byte-identical to v2.1. |
| v3 `build.tcl` levers (`place_option 1`, `route_option 2`, `maxfan 50`) | 60K congestion tuning; `maxfan` was reverted the same day upstream, and MoonTANG routes at 60% CLS with no pressure. |
| `opl4wave/YMF278B.sv` + `convert.sh` toolchain | Copying it would create a third divergent source of truth (MSX_up and MSX_up_v3 `.sv` already differ by the 60K BSRAM migration) that a future regen could import by accident. |
| `opl4_pcm.v` CE_INC/CE_MOD 14112/15625 | Intentional: 6272/6875 is correct for MoonTANG's 37.125 MHz `clk_eng` (37.5 MHz needs PFD 1.5 MHz, below the GW2A rPLL minimum). |
| MSXimus's `>>1` on the wavetable mix | Headroom for a nine-term mixer with a master gain; MoonTANG has two terms and no master gain — applying it would put the cartridge's principal voice 6 dB under the FM. |
| `oe_n`/`slot_data_dir` from one register (transceiver always enabled) | Verbatim the hra1129 reference pattern (`msx_slot.v:252-256`, `oe_n = 1'b0`) — but note §1.1 replaces this whole front-end anyway. |
| Async-read `OPL4_*_RAM` (registered addr + combinational Q) | Faithful translation of `altsyncram(addr_reg_b=CLOCK0, outdata=UNREGISTERED)`; write/read addresses come from different pipeline stages so collision is structurally impossible. |