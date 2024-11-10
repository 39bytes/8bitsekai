; ================
; | Title Screen |
; ================
.segment "BSS"
  menu_cursor_position: .res 1

.segment "CODE"

str_game_title:  .asciiz "8-Bit Sekai"
str_press_start: .asciiz "PRESS START"

title_screen:
  ; handle input
  jsr poll_input

  IS_JUST_PRESSED BUTTON_START
  beq :+
    MOVE last_frame_buttons, buttons
    jmp song_select
:
  MOVE last_frame_buttons, buttons

  ; Draw stuff
  ; DRAW_STRING str_game_title, 10, 14
  DRAW_STRING str_press_start, 10, 16
  jsr ppu_update
  jmp title_screen
