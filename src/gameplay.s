.include "math.s"

; ============
; | Gameplay |
; ============

.segment "ZEROPAGE"
  gameplay_cursor_position: .res 1 ; Lane index of the beginning
  ; --- Chart Relevant Data ---
  ; I'm defining a 'timing unit' to be 1/240 of a beat.
  timer: .res 3 ; For note timing, measured in timing units
  frame_units: .res 1 ; How many timing units occur in 1 frame
  chart_length: .res 2 ; The number of notes in the chart
  note_ptr: .res 2 ; Where we are in the chart in terms of notes
  
  ; Need some kind of note queue for hits...
  live_notes_head_index: .res 1
  live_notes_tail_index: .res 1
  live_notes_lanes: .res 16
  live_notes_timing1: .res 16
  live_notes_timing2: .res 16
  live_notes_timing3: .res 16
  live_notes_nt_x: .res 16
  live_notes_nt_y: .res 16


SCREEN_HEIGHT = 240
TILE_WIDTH = 8
CURSOR_WIDTH = 2 ; Lane width of the cursor
N_LANES = 8      ; Total number of lanes
LANE_WIDTH = 2   ; Tile width of 1 lane
LANE_X = 8       ; X position of the start of the lanes
LANE_Y = 28      ; Y position of the lanes
SCROLL_SPEED = 4 ; Vertical scroll speed

; TODO: Dynamically calculate this
BPM = 5
; How many timing units ahead we should spawn the note?
SPAWN_DIFF = (SCREEN_HEIGHT + TILE_WIDTH) / SCROLL_SPEED * BPM * 2 
  
.segment "CODE"

str_gameplay: .asciiz "Gameplay"
chart:
  .byte 5 ; 150 BPM
  .byte $02, $00 ; 2 notes
  .byte $03, 240, $00, $00 ; Note after 1 beat, width 1, lanes 0-3
  .byte $35, 240, $01, $00 ; Note after 1 beat, width 1, lanes 3-5

gameplay:
  ; Clear draw buffer
  MOVE nt_update_len, #0
  ; Clear the background first
  jsr ppu_disable_rendering
  jsr clear_background
  jsr draw_playfield
  
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

  ; Initial rendering
  DRAW_TILE Tile::Note, 8, 0
  DRAW_TILE Tile::Note, 9, 0
  
@loop:
  inc frame
  ; Gameplay logic
  jsr tick_timer       
  jsr inc_scroll
  jsr handle_gameplay_input

  jsr ppu_update
  jmp @loop

; Draw the vertical lines outlining the lanes in the playfield.
.proc draw_playfield
  lda #Tile::PlayfieldBoundaryLeft
  ldx #(LANE_X - 1)
  ldy #0
@draw_left_2000:    ; Draw the left boundary on nametable $2000
  jsr ppu_set_tile
  iny
  cpy #32
  bcc @draw_left_2000

  ldy #64
@draw_left_2800:    ; Draw the left boundary on nametable $2800
  jsr ppu_set_tile
  iny
  cpy #96
  bcc @draw_left_2800

  lda #Tile::PlayfieldBoundaryRight
  ldx #(LANE_X + 18)
  ldy #0
@draw_right_2000:    ; Draw the right boundary on nametable $2000
  jsr ppu_set_tile
  iny
  cpy #32
  bcc @draw_right_2000

  ldy #64
@draw_right_2800:    ; Draw the right boundary on nametable $2800
  jsr ppu_set_tile
  iny
  cpy #96
  bcc @draw_right_2800

  rts
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

; Load at most 8 ready notes into live_notes and also spawn them on the bg
.proc load_notes
  PUSH s1
  PUSH s2
  PUSH s3
  PUSH s4

  lanes = s1
  timing1 = s2
  timing2 = s3
  timing3 = s4

  ldx #0 ; X stores the actual memory offset
  ldy #0 ; Y stores the note offset
@loop:
  MOVE lanes, {note_ptr, X} ; Read lane byte
  inx
  MOVE p1_24, {note_ptr, X} ; Read the 3 timing bytes
  inx
  MOVE p1_24+1, {note_ptr, X} 
  inx
  MOVE p1_24+2, {note_ptr, X} 
  inx
  ; Save the timing for later
  MOVE24 timing1, p1_24

  ; Check if the note should be loaded, 
  ; i.e timing - timer <= SPAWN_DIFF
  MOVE24 p2_24, timer ; compute timing - timer
  jsr sub24
  MOVE24 p1_24, r1_24 ; compare with SPAWN_DIFF
  MOVE p2_24, #<SPAWN_DIFF
  MOVE p2_24+1, #>SPAWN_DIFF
  jsr cmp24
  ; Notes are in chronological order so if it's too early for this one
  ; then we can just return early
  bcs :+ 
    rts
:
  ; Add this to the live note queue
  ldx live_notes_tail_index
  MOVE {live_notes_timing1, X}, timing1
  MOVE {live_notes_timing2, X}, timing2
  MOVE {live_notes_timing3, X}, timing3
  ; Compute the scroll tile
  jsr scroll_position
  ; TODO: left off here

  
  lda scroll_y
  sta live_notes_nt_y

  inc live_notes_tail_index
  
  iny
  cpy #8
  bcc @loop
  
  ; TODO:
  POP s4
  POP s3
  POP s2
  POP s1
  rts
.endproc

; Converts the current scroll position to a nametable tile position.
; ---Returns---
; A - the computed tile position
.proc scroll_position
  tile_y = t1
  nt_bit = t2

  lda scroll_y ; Divide by 8 (tile size)
  lsr
  lsr 
  lsr
  sta tile_y
  
  ; If we're on tile 0 of a nametable, flip the nametable bit, set to 29 (last row of a nametable)
  cmp #0
  bne :+
    lda scroll_nt
    eor $02
    sta nt_bit
    MOVE tile_y, #29
:
  ; If we're on nametable $2800, then we need to add 64 as an offset
  lda nt_bit
  beq :+
    lda tile_y
    clc
    adc #64
    sta tile_y
:

  lda tile_y
  rts
.endproc
