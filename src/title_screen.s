; ================
; | Title Screen |
; ================
.segment "BSS"
  menu_cursor_position: .res 1

.segment "CODE"

str_game_title:  .asciiz "8-Bit Sekai"
str_press_start: .asciiz "PRESS START"

title_screen:
  DRAW_STRING str_press_start, 10, 16
  ; LOAD24 p1_16, #'0', #'6', #'2'

@loop:
  jsr poll_input

  ; If start is pressed, go to the song select screen
  IS_JUST_PRESSED BUTTON_START 
  beq :+
    MOVE last_frame_buttons, buttons
    jmp song_select
:

  MOVE last_frame_buttons, buttons

  jsr ppu_update
  jmp @loop
