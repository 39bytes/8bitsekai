; ===============
; | Song Select |
; ===============

.segment "BSS"
  menu_cursor_index:    .res 1
  cur_chart:            .res 2
  cur_song:             .res 2

.segment "CODE"
str_song_select: .asciiz "Song Select"

; Songs
str_lower:	.asciiz "Lower"
str_6_trillion: .asciiz "6 Trillion Years"

MENU_X = 8
MENU_Y = 9
N_MENU_ITEMS = 2

menu_item_labels:
  .addr str_lower      
  .addr str_6_trillion

menu_item_charts:
  .addr chart_lower
  .addr chart_6_trillion

menu_item_songs:
  .addr music_data_lower_short_ver
  .addr music_data_6_trillion_years_and_overnight_story
  

song_select:
  lda #0
  sta menu_cursor_index
  sta cur_chart
  sta cur_chart+1
  sta cur_song
  sta cur_song+1

  ; Clear the background first
  jsr ppu_disable_rendering
  jsr clear_background

  ; Draw the 'Song Select' title and the songs list
  DRAW_STRING_IMM str_song_select, #10, #6
  jsr draw_songs_list
@loop:
  ; Input handling
  jsr poll_input

  IS_JUST_PRESSED BUTTON_UP
  beq @skip_up
    jsr clear_song_select_cursor
    DEC_WRAP menu_cursor_index, #(N_MENU_ITEMS-1)
    jsr draw_song_select_cursor
@skip_up:

  IS_JUST_PRESSED BUTTON_DOWN
  beq @skip_down
    jsr clear_song_select_cursor
    INC_WRAP menu_cursor_index, #N_MENU_ITEMS
    jsr draw_song_select_cursor
@skip_down:

  IS_JUST_PRESSED BUTTON_START
  beq @skip_start
    ; i * sizeof(addr)
    lda menu_cursor_index
    asl
    tax

    ; chart = menu_item_charts[i]
    ; song = menu_item_songs[i]
    MOVE cur_chart, {menu_item_charts, X}
    MOVE cur_song, {menu_item_songs, X}
    inx
    MOVE cur_chart+1, {menu_item_charts, X}
    MOVE cur_song+1, {menu_item_songs, X}

    MOVE last_frame_buttons, buttons
    jmp gameplay
@skip_start:

  MOVE last_frame_buttons, buttons

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
  jsr draw_string_imm
  inc s1

  ; pop it back
  pla
  tax
  cpx #(2 * N_MENU_ITEMS)
  bne @loop
  
  POP s1
  rts
.endproc

; Clears cursor tile.
.proc clear_song_select_cursor
  ; Clear the current cursor position
  ldx #(MENU_X - 1)
  lda #MENU_Y
  clc
  adc menu_cursor_index
  tay
  lda #Tile::Blank

  jsr ppu_update_tile
  rts
.endproc

; Draws the cursor tile.
; Clobbers A, X, Y
.proc draw_song_select_cursor
  ldx #(MENU_X - 1)
  ; y = 8 + menu_cursor_index
  lda #MENU_Y
  clc
  adc menu_cursor_index
  tay

  lda #'>'

  jsr ppu_update_tile
  rts
.endproc
