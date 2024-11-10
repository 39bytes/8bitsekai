; ===============
; | Song Select |
; ===============
str_song_select: .asciiz "Song Select"

; Songs
str_lower:	.asciiz "Lower"
str_mesmerizer: .asciiz "Mesmerizer"
str_senbonzakura: .asciiz "Senbonzakura"
str_rokuchounen: .asciiz "6 Trillion Years"

N_MENU_ITEMS = 4
MENU_X = 8
MENU_Y = 9

menu_item_labels:
  .addr str_lower      
  .addr str_mesmerizer 
  .addr str_senbonzakura
  .addr str_rokuchounen

menu_item_addrs:

song_select:
  ; Clear the background first
  jsr ppu_disable_rendering
  jsr clear_background
@loop:
  ; Clear the current cursor position
  ldx #(MENU_X - 1)
  lda #MENU_Y
  clc
  adc menu_cursor_position
  tay
  lda #Tile::Blank
  jsr ppu_update_tile

  ; Input handling
  jsr poll_input

  IS_JUST_PRESSED BUTTON_UP
  beq @skip_up
    DEC_WRAP menu_cursor_position, #(N_MENU_ITEMS-1)
@skip_up:

  IS_JUST_PRESSED BUTTON_DOWN
  beq @skip_down
    INC_WRAP menu_cursor_position, #N_MENU_ITEMS
@skip_down:

  IS_JUST_PRESSED BUTTON_START
  beq @skip_start
    ; TODO: make the selection actually mean something
    MOVE last_frame_buttons, buttons
    jmp gameplay
@skip_start:

  MOVE last_frame_buttons, buttons

  ; Draw the 'Song Select' title and the songs list
  DRAW_STRING str_song_select, 10, 6
  jsr draw_songs_list
  jsr draw_cursor

  jsr ppu_update
  jmp @loop
  
; Draw the menu items (songs) in the song select screen.
; Clobbers A, X, Y
.proc draw_songs_list
  PUSH s1

  ldx #0
  MOVE s1, #MENU_Y
@loop:
  MOVE ptr, {menu_item_labels, x} ; string low byte
  inx
  MOVE {ptr+1}, {menu_item_labels, x} ; string high byte
  inx

  ; push the index
  txa
  pha

  ldx #MENU_X
  ldy s1
  jsr draw_string
  inc s1

  ; pop it back
  pla
  tax
  cpx #(2 * N_MENU_ITEMS)
  bne @loop
  
  POP s1
  rts
.endproc

; Draws the song select cursor.
; Clobbers A, X, Y
.proc draw_cursor
  ldx #(MENU_X - 1)
  ; y = 8 + menu_cursor_position
  lda #MENU_Y
  clc
  adc menu_cursor_position
  tay

  lda #'>'

  jsr ppu_update_tile
  rts
.endproc
