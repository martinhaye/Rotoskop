; Mini test program for build pipeline
        .org $1000
        .include "msg.inc"
        ldx msg
        jmp $FFF9
