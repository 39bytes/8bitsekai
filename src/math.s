; Math operations do not modify volatile registers so callers
; do not have to preserve the registers before calling them.

; 16 bit addition 
.macro ADD16 result, var1, var2
  clc
  ; Add low bytes
  lda var1
  adc var2
  sta result
  ; Add high bytes
  lda var1+1
  adc var2+1
  sta result+1
.endmacro

; 16 bit addition, with separate bytes for the second argument
; useful for immediates
.macro ADD16B result, var1, low, high
  clc
  ; Add low bytes
  lda var1
  adc low
  sta result
  ; Add high bytes
  lda var1+1
  adc high
  sta result+1
.endmacro

; 24 bit addition
.macro ADD24 result, var1, var2
  clc
  ; Add low bytes
  lda var1
  adc var2
  sta result
  ; Add middle bytes
  lda var1+1
  adc var2+1
  sta result+1
  ; Add high bytes
  lda var1+2
  adc var2+2
  sta result+2
.endmacro

; 24 bit addition with separate bytes
.macro ADD24B result, var1, low, middle, high
  clc
  ; Add low bytes
  lda var1
  adc low
  sta result
  ; Add middle bytes
  lda var1+1
  adc middle
  sta result+1
  ; Add high bytes
  lda var1+2
  adc high
  sta result+2
.endmacro

; 16 bit subtraction
.macro SUB16 result, var1, var2
  sec
  ; Subtract low bytes
  lda var1
  sbc var2
  sta result
  ; Subtract borrow from high byte
  lda var1+1
  sbc var2+1
  sta result+1
.endmacro

; 16 bit subtraction with separate bytes
.macro SUB16B result, var1, low, high
  sec
  ; Subtract low bytes
  lda var1
  sbc low
  sta result
  ; Subtract borrow from high byte
  lda var1+1
  sbc high
  sta result+1
.endmacro

; 24 bit subtraction
.macro SUB24 result, var1, var2
  sec
  ; Subtract low bytes
  lda var1
  sbc var2
  sta result
  ; Subtract middle bytes
  lda var1+1
  sbc var2+1
  sta result+1
  ; Subtract high bytes
  lda var1+2
  sbc var2+2
  sta result+2
.endmacro

; 24 bit subtraction with separate bytes
.macro SUB24B result, var1, low, middle, high
  sec
  ; Subtract low bytes
  lda var1
  sbc low
  sta result
  ; Subtract middle bytes
  lda var1+1
  sbc middle
  sta result+1
  ; Subtract high bytes
  lda var1+2
  sbc high
  sta result+2
.endmacro

; 16 bit comparison between two numbers B and C
; Sets Z if B == C
; Sets C if B >= C
.macro CMP16 var1, var2
  ; Compare high bytes
  lda var1+1
  cmp var2+1
  bne :+ 
    ; The high bytes are equal, we need to compare the low bytes
    lda var1
    cmp var2
:
.endmacro

; 24 bit comparison between two numbers B and C
; Sets Z if B == C
; Sets C if B >= C
.macro CMP24 var1, var2
  ; Compare high bytes
  lda var1+2
  cmp var2+2
  bne :++
    ; Compare middle bytes
    lda var1+1
    cmp var2+1
    bne :+
      ; Compare low bytes
      lda var1
      cmp var2
  :
:
.endmacro

.macro CMP24B var1, low, middle, high
  ; Compare high bytes
  lda var1+2
  cmp high
  bne :++
    ; Compare middle bytes
    lda var1+1
    cmp middle
    bne :+
      ; Compare low bytes
      lda var1
      cmp low
  :
:
.endmacro


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
