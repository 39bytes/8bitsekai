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
  ; Reset the timer
  lda #0
  sta timer
  sta timer+1
  sta timer+2
  ; Setup scroll Y to bottom of screen initially
  ; MOVE scroll_y, #239 
  ; MOVE scroll_nt, $02
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

  ; jsr draw_lanes
  
  jsr ppu_update
  jmp @loop

; Draw the gameplay lanes and the cursor.
.proc draw_lanes
  ldx #LANE_X
  ldy #0

@loop:
  MOVE {oam, Y}, #LANE_Y         ; y coord
  iny
  MOVE {oam, Y}, #Tile::LaneDark ; tile id
  iny
  MOVE {oam, Y}, #0              ; attributes
  iny
  MOVE {oam, Y}, #LANE_X         ; attributes
  iny
  inx
  cpy #N_LANES
  bcc @loop

;   PUSH s1
;   PUSH s2
;
;   cursor_start = s1
;   cursor_end = s2
;
;   ; Compute the start lane of cursor
;   ; gameplay_cursor_position * 2 + LANE_X
;   lda gameplay_cursor_position ; TODO: figure out how to also do this for 3 width
;   asl
;   clc
;   adc #LANE_X
;   sta cursor_start
;
;   ; Compute end lane of cursor
;   ; CURSOR_WIDTH * 2 added to start lane
;   ldx #CURSOR_WIDTH
;   stx cursor_end
;   asl cursor_end
;   clc 
;   adc cursor_end
;   sta cursor_end
;
;   ldx #LANE_X
;   ldy #LANE_Y
; @loop:
;   ; if cursor_start <= x < cursor_end
;   cpx cursor_start
;   bcc @dark
;   cpx cursor_end
;   bcs @dark
; @light:
;   lda #Tile::LaneCursor ; use the light color
;   jmp @draw
; @dark:
;   lda #Tile::LaneDark   ; else use the dark color
; @draw:
;   jsr ppu_update_tile   ; draw the tile
;   inx
;   cpx #(LANE_X + N_LANES * LANE_WIDTH) ; loop until all lanes covered
;   bcc @loop
;
;   POP s2
;   POP s1
;   rts
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

  MOVE last_frame_buttons, buttons
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
