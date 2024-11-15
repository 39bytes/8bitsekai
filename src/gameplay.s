; ============
; | Gameplay |
; ============

.segment "ZEROPAGE"
  frame: .res 1 ; The current frame count
  gameplay_cursor_position: .res 1 ; Lane index of the beginning
  ; --- Chart Relevant Data ---
  ; I'm defining a 'timing unit' to be 1/240 of a beat.
  timer: .res 3         ; For note timing, measured in timing units
  frame_units: .res 1   ; How many timing units occur in 1 frame
  chart_length: .res 2  ; The number of notes in the chart
  notes_spawned: .res 2 ; The number of notes we've already spawned
  note_ptr: .res 2      ; Pointer to the most recently non-spawned note
  
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
  .byte $03, $C0, $03, $00 ; Note after 2 beats, lanes 0-3
  .byte $67, $C0, $03, $00 ; Note after 4 beats, lanes 6-7

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

  ; Reset state
  lda #0
  sta timer
  sta timer+1
  sta timer+2
  sta notes_spawned
  sta notes_spawned+1

  ; Setup scroll Y to bottom of screen initially
  MOVE scroll_y, #239 
  ; Compute map relevant information
  lda chart ; Read BPM and convert it to timing units
  clc
  rol
  sta frame_units 
  MOVE16 chart_length, {chart+1} ; BPM is followed by the chart length
  LOAD16 note_ptr, #<(chart+3), #>(chart+3) ; Set the note pointer

@loop:
  ; Gameplay logic
  jsr load_notes
  jsr tick_timer       
  jsr inc_scroll
  jsr handle_gameplay_input

  inc frame

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
  cpy #30
  bcc @draw_left_2000

  ldy #64
@draw_left_2800:    ; Draw the left boundary on nametable $2800
  jsr ppu_set_tile
  iny
  cpy #94
  bcc @draw_left_2800

  lda #Tile::PlayfieldBoundaryRight
  ldx #(LANE_X + (N_LANES + 1) * 2)
  ldy #0
@draw_right_2000:    ; Draw the right boundary on nametable $2000
  jsr ppu_set_tile
  iny
  cpy #30
  bcc @draw_right_2000

  ldy #64
@draw_right_2800:    ; Draw the right boundary on nametable $2800
  jsr ppu_set_tile
  iny
  cpy #94
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

; Load all ready notes into live_notes and also spawn them on the bg
.proc load_notes
  PUSH s1
  PUSH s2
  PUSH s3
  PUSH s4
  PUSH s5

  lanes = s1
  timing1 = s2
  timing2 = s3
  timing3 = s4

  mem_offset = s5     ; The actual memory offset from the current note pointer value
  MOVE mem_offset, #0

loop:
  ; If we already reached the end of the map then break
  MOVE16 p1_16, notes_spawned
  MOVE16 p2_16, chart_length
  jsr cmp16
  bcs end

  ldy mem_offset
  MOVE lanes, {(note_ptr), Y} ; Read lane byte
  iny
  MOVE p1_24, {(note_ptr), Y} ; Read the 3 timing bytes
  iny
  MOVE p1_24+1, {(note_ptr), Y} 
  iny
  MOVE p1_24+2, {(note_ptr), Y} 
  iny
  ; Save the timing for later
  MOVE24 timing1, p1_24

  ; Check if the note should be loaded, 
  ; i.e timing - timer <= SPAWN_DIFF
  MOVE24 p2_24, timer ; compute timing - timer
  jsr sub24
  ; Notes are in chronological order so if timing - timer > SPAWN_DIFF then
  ; it's too early for this one so we can just return early
  MOVE24 p1_24, r1_24 ; compare with SPAWN_DIFF
  MOVE p2_24, #<SPAWN_DIFF
  MOVE p2_24+1, #>SPAWN_DIFF
  jsr cmp24
  bcs end
  ; If we get here, then the note should be spawned
  ; so commit the mem_offset change and increment the note counter
  sty mem_offset
  inc notes_spawned

  ; Add this note to the live note queue
  ldx live_notes_tail_index
  MOVE {live_notes_timing1, X}, timing1
  MOVE {live_notes_timing2, X}, timing2
  MOVE {live_notes_timing3, X}, timing3
  MOVE {live_notes_nt_x, X}, lanes
  ; Compute the scroll tile Y
  jsr scroll_position
  sta live_notes_nt_y, X
  inc live_notes_tail_index
  tay ; Also move this into the Y register for drawing tiles

  lda lanes
  jsr draw_note

  jmp loop

end:
  ; Add the accumulated memory offset to the note pointer
  MOVE16 p1_16, note_ptr
  LOAD16 p2_16, mem_offset, #$00
  jsr add16
  MOVE16 note_ptr, r1_16
  
  POP s5
  POP s4
  POP s3
  POP s2
  POP s1
  rts
.endproc

; Draws a single note. 
; ---Parameters---
; A - The lane byte of the note.
; Y - The Y coordinate to draw it at
.proc draw_note
  lanes = t1
  note_start = s1
  note_end = s2
  ; Save this argument first
  sta lanes

  ; Save registers
  PUSH s1
  PUSH s2

  ; The left most end point is the top 4 bits (lanes >> 4)
  lda lanes
  lsr
  lsr
  lsr
  lsr
  ; Multiplied by 2
  asl
  adc #LANE_X ; Then add the X offset of the playfield
  sta note_start
  ; The right end point is the bottom 4 bits 
  inc lanes ; First add 1 to make it inclusive
  lda lanes ; Then mask off the bottom 4 bits
  and #$0F 
  asl       ; Multiplied by 2
  adc #LANE_X ; Then also add the X offset of the playfield
  sta note_end 

  ; Now we draw all of those tiles
  ldx note_start
  ; First start with the left edge
  lda #Tile::NoteLeft
  jsr ppu_update_tile
  inx
  ; Then draw the middle, that is until `note_end - 1`
  dec note_end
@draw_middle:  
  cpx note_end
  bcs @draw_right

  lda #Tile::NoteMiddle
  jsr ppu_update_tile
  inx
  jmp @draw_middle

@draw_right:
  ; Finish by drawing the right edge
  lda #Tile::NoteRight
  jsr ppu_update_tile

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

  MOVE nt_bit, scroll_nt
  lda scroll_y ; Divide by 8 (tile size)
  lsr
  lsr 
  lsr
  sta tile_y
  
  ; If we're on tile 0 of a nametable, flip the nametable bit, set to 29 (last row of a nametable)
  cmp #0
  bne :+
    lda nt_bit
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
