; Math operations do not modify volatile registers so callers
; do not have to preserve the registers before calling them.

; 16 bit addition: B + C
; Preserves: X, Y
; ---Parameters---
; p1_16 - B
; p2_16 - C
; ---Returns---
; r1_16 - Result
.proc add16
  clc
  ; Add low bytes
  lda p1_16
  adc p2_16
  sta r1_16
  ; Add high bytes
  lda p1_16+1
  adc p2_16+1
  sta r1_16+1

  rts
.endproc

; 24 bit addition: B + C
; Preserves: X, Y
; ---Parameters---
; p1_24 - B
; p2_24 - C
; ---Returns---
; r1_24 - Result
.proc add24
  clc
  ; Add low bytes
  lda p1_24
  adc p2_24
  sta r1_24
  ; Add middle bytes
  lda p1_24+1
  adc p2_24+1
  sta r1_24+1
  ; Add high bytes
  lda p1_24+2
  adc p2_24+2
  sta r1_24+2

  rts
.endproc

; 16 bit subtraction: B - C
; Preserves: X, Y
; ---Parameters---
; p1_16 - B
; p2_16 - C
; ---Returns---
; r1_16 - Result
.proc sub16
  sec
  ; Subtract low bytes
  lda p1_16
  sbc p2_16
  sta r1_16
  ; Subtract borrow from high byte
  lda p1_16+1
  sbc p2_16+1
  sta r1_16+1

  rts
.endproc

; 24 bit subtraction: B - C
; Preserves: X, Y
; ---Parameters---
; p1_24 - B
; p2_24 - C
; ---Returns---
; r1_24 - Result
.proc sub24
  sec
  ; Subtract low bytes
  lda p1_24
  sbc p2_24
  sta r1_24
  ; Subtract middle bytes
  lda p1_24+1
  sbc p2_24+1
  sta r1_24+1
  ; Subtract high bytes
  lda p1_24+2
  sbc p2_24+2
  sta r1_24+2

  rts
.endproc

; 16 bit comparison between two numbers B and C
; Preserves: X, Y
; ---Parameters----
; p1_24 - B
; p2_24 - C
; ---Returns---
; Sets Z if B == C
; Sets C if B >= C
.proc cmp16
  ; Compare high bytes
  lda p1_16+1
  cmp p2_16+1
  beq :+
    rts
:
  ; Compare low bytes
  lda p1_16
  cmp p2_16
  rts
.endproc

; 24 bit comparison between two numbers B and C
; Preserves: X, Y
; ---Parameters----
; p1_24 - B
; p2_24 - C
; ---Returns---
; Sets Z if B == C
; Sets C if B >= C
.proc cmp24
  ; Compare high bytes
  lda p1_24+2
  cmp p2_24+2
  beq :+
    rts
:
  ; Compare middle bytes
  lda p1_24+1
  cmp p2_24+1
  beq :+
    rts
:
  ; Compare low bytes
  lda p1_24
  cmp p2_24
  rts
.endproc

; Convert a byte to an unpacked binary coded decimal representation
; ---Parameters---
; A - Byte to convert
; ---Returns---
; r1_24 - Binary coded decimal
.proc hex8_to_decimal
  ldy #'0'

  hundreds = r1_24
  tens = r1_24+1
  ones = r1_24+2
  sty hundreds
  sty tens

@calc_hundreds:
  cmp #100
  bcc @calc_tens
  sbc #100
  inc hundreds
  bne @calc_hundreds
@calc_tens:
  cmp #10
  bcc @calc_ones
  sbc #10
  inc tens
  bne @calc_tens
@calc_ones:
  clc
  adc #'0'
  sta ones

  rts
.endproc
