# moontang_trace.tcl -- openMSX I/O trace for MoonSound / MSX-Audio software
#
# Logs, with the emulated time and the PC, every access to the sound ports
# (MoonSound 7Eh-7Fh and C4h-C7h, MSX-Audio C0h-C3h, Music Module DAC 0Ah,
# MSX-Music 7Ch-7Dh), the BIOS inter-slot calls software uses to look for a
# ROM (RDSLT, WRSLT, CALSLT, ENASLT, CALLF, EXTBIO), and a count of every other
# I/O port touched (the VDP ports 98h-9Bh excepted).
#
# Use (openMSX console, F10):
#   source moontang_trace.tcl
#   moontang_trace::start /path/to/trace.log
#   ... boot the disk, let it detect the hardware and play for a few seconds ...
#   moontang_trace::mark "song 1 started"
#   moontang_trace::stop
#
# The PC logged is the one openMSX reports while the access happens: the
# address of the next instruction (for IN/OUT: the instruction's address + 2).
# Streams of sample-memory bytes (wave register 06h) are summarised in one
# line: count, start address, first bytes and a checksum. Identical
# consecutive lines (polling loops) are folded into "(xN)".

namespace eval moontang_trace {
    variable fh ""
    variable ids {}
    variable lines 0
    variable max_lines 300000
    variable prev ""
    variable rep 0
    variable wave_latch 0
    variable fm_latch 0
    variable new2 0
    variable mreg3 0
    variable mreg4 0
    variable maddr 0
    variable mem_dir ""
    variable mem_count 0
    variable mem_start 0
    variable mem_first ""
    variable mem_sum 0
    variable mem_pc ""
    variable mem_last 0.0
    variable mem_gap 0.0
    variable cpu ""
    variable ma 0
    variable mem_ma 0
    variable hist
    array set hist {}
    variable detail
    array set detail {}
    foreach p {0x0A 0x7C 0x7D 0x7E 0x7F 0xC0 0xC1 0xC2 0xC3 0xC4 0xC5 0xC6 0xC7} {
        set detail([expr {$p}]) 1
    }

    proc now {} {
        return [format "%12.7f" [machine_info time]]
    }

    proc out {line} {
        variable fh
        variable lines
        variable max_lines
        if {$fh eq ""} return
        if {$lines >= $max_lines} {
            if {$lines == $max_lines} {
                puts $fh "*** max_lines reached, detailed log stopped (histogram still counts) ***"
                incr lines
            }
            return
        }
        puts $fh $line
        incr lines
    }

    # fold identical consecutive events (time excluded)
    proc emit {key} {
        variable prev
        variable rep
        if {$key eq $prev} {
            incr rep
            return
        }
        flush_rep
        set prev $key
        out "[now] $key"
    }

    proc flush_rep {} {
        variable prev
        variable rep
        if {$rep > 0} {
            out "           (x[expr {$rep + 1}] in total)"
            set rep 0
        }
    }

    proc flush_mem {} {
        variable mem_dir
        variable mem_count
        variable mem_start
        variable mem_first
        variable mem_sum
        variable mem_pc
        variable mem_gap
        variable mem_ma
        if {$mem_count == 0} return
        flush_rep
        variable prev
        set prev ""
        set gap [expr {$mem_count > 1 ? [format "%.2f us" $mem_gap] : "-"}]
        out [format "%s MEM%s %6d bytes from %06Xh  pc=%s  min.gap=%s  MA=%d  first: %s  sum=%04X" \
            [now] $mem_dir $mem_count $mem_start $mem_pc $gap $mem_ma $mem_first [expr {$mem_sum & 0xFFFF}]]
        set mem_count 0
        set mem_dir ""
        set mem_first ""
        set mem_sum 0
    }

    proc mem_access {dir val pc} {
        variable mem_dir
        variable mem_count
        variable mem_start
        variable mem_first
        variable mem_sum
        variable mem_pc
        variable mem_last
        variable mem_gap
        variable maddr
        variable ma
        variable mem_ma
        set t [machine_info time]
        if {$mem_dir ne $dir} {
            flush_mem
            set mem_dir $dir
            set mem_ma $ma
            set mem_start $maddr
            set mem_pc $pc
            set mem_gap 1e9
        } else {
            set g [expr {($t - $mem_last) * 1e6}]
            if {$g < $mem_gap} { set mem_gap $g }
        }
        set mem_last $t
        if {$mem_count < 16} { append mem_first [format "%02X " $val] }
        incr mem_count
        set mem_sum [expr {$mem_sum + $val}]
        # the YMF278 only advances the address with MA (reg 02h bit 0) set
        if {$ma} { set maddr [expr {($maddr + 1) & 0x3FFFFF}] }
    }

    proc io {dir} {
        variable hist
        variable detail
        variable wave_latch
        variable fm_latch
        variable mreg3
        variable mreg4
        variable maddr
        variable ma
        set port [expr {$::wp_last_address & 0xFF}]
        if {$dir eq "W"} {
            set val [expr {$::wp_last_value & 0xFF}]
        } else {
            # side-effect free peek of what the IN will return
            set val [debug read ioports $port]
        }
        set k [format "%s%02X" $dir $port]
        if {[info exists hist($k)]} { incr hist($k) } else { set hist($k) 1 }
        if {![info exists detail($port)]} return
        check_cpu
        set pc [format "%04X" [reg pc]]
        # sample memory streams through wave register 06h
        if {$port == 0x7F && $wave_latch == 6} {
            mem_access $dir $val $pc
            return
        }
        flush_mem
        set note ""
        switch -- $port {
            196 - 198 {
                if {$dir eq "W"} {
                    set fm_latch [expr {$val | (($port == 198) ? 0x100 : 0)}]
                } else {
                    set note [format "status bits: IRQ=%d FT1=%d FT2=%d LD=%d BUSY=%d" \
                        [expr {($val>>7)&1}] [expr {($val>>6)&1}] [expr {($val>>5)&1}] \
                        [expr {($val>>1)&1}] [expr {$val&1}]]
                }
            }
            197 - 199 {
                set note [format "FM reg %03Xh" $fm_latch]
            }
            126 {
                if {$dir eq "W"} { set wave_latch $val }
            }
            127 {
                set note [format "WAVE reg %02Xh" $wave_latch]
                if {$dir eq "W"} {
                    switch -- $wave_latch {
                        2 { set ma [expr {$val & 1}]
                            append note [format " (WTH=%d MT=%d MA=%d)" [expr {($val>>2)&7}] [expr {($val>>1)&1}] $ma] }
                        3 { set mreg3 [expr {$val & 0x3F}] }
                        4 { set mreg4 $val }
                        5 { set maddr [expr {($mreg3 << 16) | ($mreg4 << 8) | $val}]
                            append note [format " -> memory address %06Xh" $maddr] }
                    }
                }
            }
        }
        emit [format "%s %02Xh %s %02X  pc=%s  %s" \
            [expr {$dir eq "W" ? "OUT" : "IN "}] $port [expr {$dir eq "W" ? "<-" : "->"}] $val $pc $note]
    }

    proc bios {name} {
        check_cpu
        flush_mem
        set a  [format "%02X" [reg a]]
        set hl [format "%04X" [reg hl]]
        set iy [format "%04X" [reg iy]]
        set ix [format "%04X" [reg ix]]
        set sp [reg sp]
        set ret [format "%04X" [expr {[peek $sp] | ([peek [expr {$sp + 1}]] << 8)}]]
        switch -- $name {
            RDSLT  { emit "BIOS RDSLT  slot=$a addr=$hl  (called from $ret)" }
            WRSLT  { emit [format "BIOS WRSLT  slot=%s addr=%s val=%02X  (called from %s)" $a $hl [reg e] $ret] }
            CALSLT { emit "BIOS CALSLT slot=[format %02X [expr {[reg iy] >> 8}]] addr=$ix  (called from $ret)" }
            ENASLT { emit "BIOS ENASLT slot=$a page-addr=[format %04X [reg h]]00  (called from $ret)" }
            CALLF  { emit "BIOS CALLF  (inline slot/addr after $ret)" }
            EXTBIO { emit [format "EXTBIO D=%02X E=%02X  (called from %s)" [reg d] [reg e] $ret] }
        }
    }

    # turbo R: log every switch between Z80 and R800 (MoonTANG's /WAIT on
    # IN 7Fh has ~70 ns to spare at 3.58 MHz and may be too late on R800)
    proc check_cpu {} {
        variable cpu
        set c "z80"
        catch {set c [get_active_cpu]}
        if {$c ne $cpu} {
            set cpu $c
            set f ""
            catch {set f " z80_freq=$::z80_freq locked=$::z80_freq_locked"}
            flush_mem
            flush_rep
            variable prev
            set prev ""
            out "[now] ===== CPU: $c$f ====="
        }
    }

    proc mark {text} {
        flush_mem
        flush_rep
        variable prev
        set prev ""
        out "[now] ===== $text ====="
    }

    proc start {{fname "moontang_trace.log"}} {
        variable fh
        variable ids
        variable lines
        variable hist
        if {$fh ne ""} { stop }
        array unset hist
        array set hist {}
        set lines 0
        variable cpu
        set cpu ""
        set fh [open $fname w]
        puts $fh "moontang_trace  machine=[machine_info config_name]  extensions=[list_extensions]"
        puts $fh "devices: [machine_info device]"
        foreach t {read_io write_io} d {R W} {
            foreach r {{0x00 0x97} {0x9C 0xFF}} {
                lappend ids [debug set_watchpoint $t $r {} [list moontang_trace::io $d]]
            }
        }
        foreach {addr name} {0x000C RDSLT 0x0014 WRSLT 0x001C CALSLT 0x0024 ENASLT 0x0030 CALLF 0xFFCA EXTBIO} {
            lappend ids [debug set_bp $addr {} [list moontang_trace::bios $name]]
        }
        return "tracing to $fname"
    }

    proc stop {} {
        variable fh
        variable ids
        variable hist
        if {$fh eq ""} { return "not tracing" }
        foreach id $ids {
            if {[string match wp* $id]} { catch {debug remove_watchpoint $id} } else { catch {debug remove_bp $id} }
        }
        set ids {}
        flush_mem
        flush_rep
        puts $fh "\n===== I/O ports touched (R=IN, W=OUT; VDP 98h-9Bh not counted) ====="
        foreach k [lsort [array names hist]] {
            puts $fh [format "  %s  %8d" $k $hist($k)]
        }
        close $fh
        set fh ""
        return "trace closed"
    }
}
