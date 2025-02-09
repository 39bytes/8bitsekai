.segment "CODE"

str_results: .asciiz "RESULTS"
str_perfect: .asciiz "PERFECT"
str_great:   .asciiz "GREAT"
str_good:    .asciiz "GOOD"
str_bad:     .asciiz "BAD"
str_miss:    .asciiz "MISS"

str_press_select: .asciiz "PRESS SELECT"

.macro SCORE_LINE str, count_var, x_coord, y_coord
  DRAW_STRING str, #x_coord, #y_coord
  MOVE16 p1_16, count_var
  jsr hex16_to_decimal
  ldx #(x_coord + 8)
  ldy #y_coord

  jsr draw_4digit_num
  jsr ppu_update
.endmacro

score_screen:
  jsr famistudio_music_stop ; Stop music  
  MOVE nt_update_len, #0 ; Clear draw buffer
  ; Clear background
  jsr ppu_disable_rendering 
  jsr clear_background
  ; Clear sprites
  jsr clear_sprites
  ; Set scroll back to nametable 0
  MOVE scroll_y, #0      
  MOVE scroll_nt, #0

  DRAW_STRING str_results, #10, #8

  WAIT #20
  SCORE_LINE str_perfect, perfect_hits, 10, 10
  WAIT #20
  SCORE_LINE str_great, great_hits, 10, 11
  WAIT #20
  SCORE_LINE str_good, good_hits, 10, 12
  WAIT #20
  SCORE_LINE str_bad, bad_hits, 10, 13
  WAIT #20
  SCORE_LINE str_miss, misses, 10, 14

  WAIT #60
  DRAW_STRING str_press_select, #10, #20

@loop:
  ; Input handling
  jsr poll_input

  IS_JUST_PRESSED BUTTON_SELECT
  beq @skip_start
    jmp song_select
@skip_start:

  jsr ppu_update
  jmp @loop

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
