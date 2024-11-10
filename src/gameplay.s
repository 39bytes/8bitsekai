; ============
; | Gameplay |
; ============

.segment "ZEROPAGE"
  gameplay_cursor_position: .res 1 ; Lane index of the beginning
  ; --- Chart Relevant Data ---
  ; I'm defining a 'timing unit' to be 1/240 of a beat.
  timer: .res 3 ; For note timing, measured in timing units
  frame_units: .res 1 ; How many timing units occur in 1 frame
  chart_length: .res 3 ; The length of the chart, in timing units
  note_index: .res 2 ; Where we are in the chart in terms of notes
  ; Need some kind of note queue for hits...
  

TILE_WIDTH = 8
CURSOR_WIDTH = 2 ; Lane width of the cursor
N_LANES = 8      ; Total number of lanes
LANE_WIDTH = 2   ; Tile width of 1 lane
LANE_X = 8       ; X position of the start of the lanes
LANE_Y = 28      ; Y position of the lanes
SCROLL_SPEED = 3 ; Vertical scroll speed
  
.segment "CODE"

str_gameplay: .asciiz "Gameplay"
chart:
  .byte 5 ; 150 BPM
  .byte $00, $00, $00 ; Length
  .byte $03, 240, $00, $00 ; Note after 1 beat, width 1, lanes 0-3
  .byte $35, 240, $01, $00 ; Note after 1 beat, width 1, lanes 3-5

gameplay:
  ; Clear the background first
  jsr ppu_disable_rendering
  jsr clear_background
  ; jsr draw_lanes
  
  ; Setup cursor sprite
  SET_SPRITE gameplay_cursor, #224, #Sprite::Cursor, #0, #128   ; Left
  SET_SPRITE gameplay_cursor+4, #224, #Sprite::Cursor, #0, #136 ; Left 2
  SET_SPRITE gameplay_cursor+8, #224, #Sprite::Cursor, #0, #144 ; Right 
  SET_SPRITE gameplay_cursor+12, #224, #Sprite::Cursor, #0, #152 ; Right 2

  ; Reset the timer
  lda #0
  sta timer
  sta timer+1
  sta timer+2
  ; Setup scroll Y to bottom of screen initially
  MOVE scroll_y, #239 
  ; Compute map relevant information
  ; Read BPM and convert it to timing units
  lda chart
  clc
  rol
  sta frame_units
  ; Read chart length
  MOVE24 chart_length, {chart+1}
  
@loop:
  ; Gameplay logic
  jsr tick_timer       
  jsr inc_scroll
  jsr handle_gameplay_input

  ; Rendering 
  ; DRAW_STRING str_gameplay, 12, 0
  ; Debug info
  ; ldx #2
  ; ldy #2
  ; lda gameplay_cursor_position
  ; clc
  ; adc #'0'
  ; jsr ppu_update_tile
  DRAW_TILE Tile::Note, 8, 0

  
  jsr ppu_update
  jmp @loop

; Draw the vertical lines outlining the lanes in the playfield.
.proc draw_playfield
  ; TODO:
.endproc

; Input handler for charts
.proc handle_gameplay_input
  jsr poll_input

  IS_JUST_PRESSED BUTTON_LEFT
  beq @skip_left
    DEC_WRAP gameplay_cursor_position, #(N_LANES-1) ; Move the cursor left
@skip_left:

  IS_JUST_PRESSED BUTTON_RIGHT
  beq @skip_right
    INC_WRAP gameplay_cursor_position, #N_LANES     ; Move the cursor right
@skip_right:

  jsr update_cursor_position
  MOVE last_frame_buttons, buttons
  rts
.endproc

.proc update_cursor_position
  ; Cursor should be placed at LANE_START + (cursor_pos * 8)
  lda gameplay_cursor_position
  asl
  asl
  asl
  asl
  clc
  adc #(LANE_X * TILE_WIDTH)

  sta gameplay_cursor+3 
  adc #8
  sta gameplay_cursor+7
  adc #8
  sta gameplay_cursor+11
  adc #8
  sta gameplay_cursor+15

  rts
.endproc


; 24 bit addition for the timer
.proc tick_timer
  clc          
  lda timer
  adc frame_units ; Low byte
  sta timer

  lda timer+1     ; Middle byte
  adc #0
  sta timer+1

  lda timer+2     ; High byte
  adc #0
  sta timer+2

  rts
.endproc

; Decrement the scroll Y by SCROLL_SPEED.
.proc inc_scroll
  sec
  lda scroll_y
  sbc #SCROLL_SPEED
  sta scroll_y
  bcs :+ ; if scroll_y underflowed
    MOVE scroll_y, #(240 - SCROLL_SPEED)
    lda scroll_nt ; If scroll Y rolls over, toggle the Y nametable bit
    eor #$02
    sta scroll_nt
:
  rts
.endproc

; Load at most the next 8 notes, stopping when encountering a note
; that shouldn't be loaded yet
.proc load_notes
  
  rts
.endproc
