; MoonTANG MTVOL -- native YMF278B (OPL4) FM / Wave output level
;
; Build with: sjasmplus --raw=MTVOL.COM mtvol.asm
; Run under MSX-DOS:
;   MTVOL FM   0|3|6|9|12|15|18|M
;   MTVOL WAVE 0|3|6|9|12|15|18|M
;
; Human volume scale: 0 is the lowest numeric level (-18 dB), 18 is maximum
; (0 dB), and M mutes. The OPL4 has one value every 3 dB.
; F8h and F9h are standard YMF278B mix-control registers, accessed through
; the existing MoonSound Wave ports 7Eh/7Fh. No MoonTANG-specific port is used.

        org     0100h

WAVE_ADDR       equ     07eh
WAVE_DATA       equ     07fh
YMF278_ID        equ     020h

start:
        ; Check that the Wave half of an OPL4 answers before changing it.
        ld      a,02h
        out     (WAVE_ADDR),a
        in      a,(WAVE_DATA)
        cp      YMF278_ID
        jp      nz,no_opl4

        ld      hl,081h                ; MSX-DOS command tail
        call    skip_spaces
        ld      a,(hl)
        cp      0dh
        jp      z,show_levels
        and     0dfh                   ; ASCII uppercase
        cp      'F'
        jr      z,select_fm
        cp      'W'
        jr      z,select_wave
        cp      '?'
        jp      z,usage
        jp      bad_arg

select_fm:
        ld      d,0f8h
        jr      select_done

select_wave:
        ld      d,0f9h

select_done:
        call    skip_word
        call    skip_spaces
        ld      a,(hl)
        and     0dfh
        cp      'M'
        jr      z,set_mute
        call    decimal
        jp      c,bad_arg
        call    volume_to_code
        jp      c,bad_arg
        jr      set_level

set_mute:
        ld      a,7

set_level:
        ; The two 3-bit fields are left and right.  Keep the level equal
        ; on both sides: register data = code * 9 (000ccc ccc).
        ld      b,a
        add     a,a
        add     a,a
        add     a,a
        add     a,b
        ld      b,a
        ld      a,d
        out     (WAVE_ADDR),a
        ld      a,b
        out     (WAVE_DATA),a
        ld      de,msg_done
        jp      print_exit

; Show the independently readable left and right mix fields without changing
; them.  A program may have set a non-symmetrical stereo balance after MTVOL.
show_levels:
        ld      de,msg_current
        call    print
        ld      a,0f8h
        call    read_wave
        ld      (mix_read),a
        ld      de,msg_fm_left
        call    print
        ld      a,(mix_read)
        and     7
        call    print_level
        ld      de,msg_right
        call    print
        ld      a,(mix_read)
        rrca
        rrca
        rrca
        and     7
        call    print_level

        ld      a,0f9h
        call    read_wave
        ld      (mix_read),a
        ld      de,msg_wave_left
        call    print
        ld      a,(mix_read)
        and     7
        call    print_level
        ld      de,msg_right
        call    print
        ld      a,(mix_read)
        rrca
        rrca
        rrca
        and     7
        call    print_level
        ld      de,msg_crlf
        jp      print_exit

; Read a Wave register selected by A.  IN 7Fh is already wait-state protected
; by the OPL4 core until the value has travelled back from the PCM domain.
read_wave:
        out     (WAVE_ADDR),a
        in      a,(WAVE_DATA)
        ret

; A contains an OPL4 3-bit mix code. Print its human volume and attenuation.
print_level:
        and     7
        add     a,a
        ld      e,a
        ld      d,0
        ld      hl,level_texts
        add     hl,de
        ld      e,(hl)
        inc     hl
        ld      d,(hl)
        call    print
        ret

; Read an unsigned decimal number at HL into E.  Carry means malformed input.
decimal:
        ld      e,0
        ld      b,0                    ; number of digits
.digit:
        ld      a,(hl)
        cp      0dh
        jr      z,.end
        cp      ' '
        jr      z,.end
        sub     '0'
        jr      c,.bad
        cp      10
        jr      nc,.bad
        push    af
        ld      a,e
        add     a,a                    ; 2 * E
        ld      c,a
        add     a,a                    ; 4 * E
        add     a,a                    ; 8 * E
        add     a,c                    ; 10 * E
        ld      e,a
        pop     af
        add     a,e
        ld      e,a
        inc     hl
        inc     b
        jr      .digit
.end:
        ld      a,b
        or      a
        jr      z,.bad
        or      a                      ; clear carry
        ret
.bad:
        scf
        ret

; Convert human volume to the OPL4 3-bit attenuation code.
; Input E: 0, 3, 6, 9, 12, 15 or 18. 0=-18 dB, 18=0 dB.
; Carry if it is another value.
volume_to_code:
        ld      a,e
        cp      0
        jr      z,.c6
        cp      3
        jr      z,.c5
        cp      6
        jr      z,.c4
        cp      9
        jr      z,.c3
        cp      12
        jr      z,.c2
        cp      15
        jr      z,.c1
        cp      18
        jr      z,.c0
        scf
        ret
.c0:    xor     a
        ret
.c1:    ld      a,1
        ret
.c2:    ld      a,2
        ret
.c3:    ld      a,3
        ret
.c4:    ld      a,4
        ret
.c5:    ld      a,5
        ret
.c6:    ld      a,6
        ret

skip_spaces:
        ld      a,(hl)
        cp      ' '
        ret     nz
        inc     hl
        jr      skip_spaces

skip_word:
        ld      a,(hl)
        cp      0dh
        ret     z
        cp      ' '
        ret     z
        inc     hl
        jr      skip_word

usage:
        ld      de,msg_usage
        jr      print_exit
no_opl4:
        ld      de,msg_no_opl4
        jr      print_exit
bad_arg:
        ld      de,msg_bad_arg

print_exit:
print:
        ld      c,09h                  ; BDOS: display $-terminated string
        call    0005h
        ret

mix_read:
        db      0

msg_done:
        db      13,10,'Nivel aplicado.',13,10,'$'
msg_no_opl4:
        db      13,10,'No se detecta un OPL4/MoonTANG (Wave ID 20h).',13,10,'$'
msg_bad_arg:
        db      13,10,'Argumento no valido.',13,10,'$'
msg_usage:
        db      13,10,'MTVOL 1.0.1beta - nivel OPL4',13,10
        db      'Sin argumentos: muestra FM y WAVE actuales.',13,10
        db      'Uso: MTVOL FM|WAVE 0|3|6|9|12|15|18|M',13,10
        db      'Volumen: 0=minimo, 18=maximo, M=silencio.',13,10,'$'
msg_current:
        db      13,10,'Niveles actuales (volumen):',13,10,'$'
msg_fm_left:
        db      ' FM    L=$'
msg_wave_left:
        db      13,10,' WAVE  L=$'
msg_right:
        db      ' R=$'
msg_crlf:
        db      13,10,'$'
level_texts:
        dw      level_0,level_3,level_6,level_9
        dw      level_12,level_15,level_18,level_mute
level_0:
        db      '18 (0 dB)$'
level_3:
        db      '15 (-3 dB)$'
level_6:
        db      '12 (-6 dB)$'
level_9:
        db      '9 (-9 dB)$'
level_12:
        db      '6 (-12 dB)$'
level_15:
        db      '3 (-15 dB)$'
level_18:
        db      '0 (-18 dB)$'
level_mute:
        db      'M (silencio)$'

        end     start
