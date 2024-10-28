; Shortcut for lda + sta boilerplate
; Clobbers A
.macro MOVE from, to
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

