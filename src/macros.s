; Shortcut for lda + sta boilerplate
; Clobbers A
.macro MOVE to, from
  lda from
  sta to
.endmacro

; lda + pla
.macro PUSH var
  lda var
  pha
.endmacro

.macro POP var
  pla
  sta var
.endmacro

; Push the A, X and Y registers to the stack
; Use this at the beginning of a function that preserves registers
.macro PUSH_AXY
  pha
  txa
  pha
  tya
  pha
.endmacro

; Pop the Y, X and A registers from the stack
; Use this when returning from a function that preserves registers.
.macro POP_YXA
  pla
  tay
  pla
  tax
  pla
.endmacro

.macro IF_EQ val1, val2
  lda val1
  cmp val2
  bne :+
.endmacro

.macro ENDIF
  :
.endmacro

; Decrement `var`, wrapping to `wrap_to` if var is already 0.
.macro DEC_WRAP var, wrap_to
  dec var
  bpl :+
    MOVE var, wrap_to
:
.endmacro

; Increment `var`, wrapping to 0 if `var >= max` after incrementing.
.macro INC_WRAP var, max
  inc var
  lda var
  cmp max
  bcc :+
    MOVE var, #0
:
.endmacro

.macro MOVE16 to, from
  lda from
  sta to
  lda from+1
  sta to+1
.endmacro


.macro MOVE24 to, from
  lda from
  sta to
  lda from+1
  sta to+1
  lda from+2
  sta to+2
.endmacro
