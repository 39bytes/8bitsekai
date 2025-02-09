str_results: .asciiz "RESULTS"
str_perfect: .asciiz "PERFECT"
str_great:   .asciiz "GREAT"
str_good:    .asciiz "GOOD"
str_bad:     .asciiz "BAD"
str_miss:    .asciiz "MISS"

score_screen:
  ; Clear draw buffer
  MOVE nt_update_len, #0
  ; Clear background
  jsr ppu_disable_rendering
  jsr clear_background

  DRAW_STRING str_results, #12, #8

  SCORE_LINE str_perfect, perfect_hits, 12, 10
  SCORE_LINE str_great, great_hits, 12, 11
  SCORE_LINE str_good, good_hits, 12, 12
  SCORE_LINE str_bad, bad_hits, 12, 13
  SCORE_LINE str_miss, misses, 12, 14

@loop:
  jmp @loop

.macro SCORE_LINE str, count_var, x_coord, y_coord
  DRAW_STRING str, #x_coord
  MOVE16 p1_16, count_var  
  jsr hex16_to_decimal
  ldx #(x_coord + 8)
  ldy #y_coord
  jsr draw_4digit_num
  jsr ppu_update
.endmacro

; Draws a 4 digit number from the result of hex16_to_decimal.
; ---Parameters---
; X - The x coordinate to draw at.
; Y - The y coordinate to draw at.
.proc draw_4digit_num
  lda r2
  jsr ppu_update_tile
  inx

  lda r3
  jsr ppu_update_tile
  inx

  lda r4
  jsr ppu_update_tile
  inx

  lda r5
  jsr ppu_update_tile

  rts
.endproc
