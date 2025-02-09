; ============
; | Gameplay |
; ============

QUEUE_LEN = 28

.segment "ZEROPAGE"
  frame: .res 2 ; The current frame count
  gameplay_cursor_position: .res 1 ; Lane index of the beginning
  ; --- Chart Relevant Data ---
  ; I'm defining a 'timing unit' to be 1/240 of a beat. 
  timer:              .res 3 ; For note timing, measured in timing units
  frame_units:        .res 1 ; How many timing units occur in 1 frame
  chart_length:       .res 3 ; 
  chart_total_notes:  .res 2 ; The number of notes in the chart
  notes_spawned:      .res 2 ; The number of notes we've already spawned
  note_ptr:           .res 2 ; Pointer to the most recently non-spawned note

  ; Judgements
  combo:         .res 2 ; Current combo
  perfect_hits:  .res 2 
  great_hits:    .res 2 
  good_hits:     .res 2 
  bad_hits:      .res 2 
  misses:        .res 2 

  
  ; The queue of notes currently present on the playfield
  live_notes_head_index: .res 1
  live_notes_tail_index: .res 1
  live_notes_lanes:      .res QUEUE_LEN
  live_notes_timing1:    .res QUEUE_LEN
  live_notes_timing2:    .res QUEUE_LEN
  live_notes_timing3:    .res QUEUE_LEN
  live_notes_nt_y:       .res QUEUE_LEN
  ; TODO: Waste less space with this
  live_notes_hit:        .res QUEUE_LEN


SCREEN_HEIGHT = 240
TILE_WIDTH = 8
CURSOR_WIDTH = 3 ; Lane width of the cursor
N_LANES = 9      ; Total number of lanes
LANE_WIDTH = 2   ; Tile width of 1 lane
LANE_X = 8       ; X position of the start of the lanes
LANE_Y = 28      ; Y position of the lanes
SCROLL_SPEED = 4 ; Vertical scroll speed

; TODO: Dynamically calculate this
BPM = 4
; How many timing units ahead we should spawn the note?
SPAWN_DIFF = (SCREEN_HEIGHT + TILE_WIDTH) / SCROLL_SPEED * BPM * 2 
; How many timing units should have passed before force missing a live note?
PERFECT_DIFF = (BPM * 2) * 2
GREAT_DIFF = (BPM * 2) * 4
GOOD_DIFF = (BPM * 2) * 8
BAD_DIFF = (BPM * 2) * 12
MISS_DIFF = (BPM * 2) * 20
IGNORE_DIFF = (BPM * 2) * 30

.segment "CODE"

str_gameplay: .asciiz "Gameplay"

chart:
  .incbin "../assets/chart.bin"

gameplay:
  ; Clear draw buffer
  MOVE nt_update_len, #0
  ; Clear the background first
  jsr ppu_disable_rendering
  jsr clear_background
  jsr draw_playfield
  
  ; Setup cursor sprite
  SET_SPRITE gameplay_cursor, #228, #Sprite::CursorLeft, #(BEHIND_BACKGROUND | PAL1), #128 
  SET_SPRITE gameplay_cursor+4, #228, #Sprite::CursorLeft, #(BEHIND_BACKGROUND | PAL1), #136
  SET_SPRITE gameplay_cursor+8, #228, #Sprite::CursorMiddle, #(BEHIND_BACKGROUND | PAL1), #144
  SET_SPRITE gameplay_cursor+12, #228, #Sprite::CursorMiddle, #(BEHIND_BACKGROUND | PAL1), #152
  SET_SPRITE gameplay_cursor+16, #228, #Sprite::CursorRight, #(BEHIND_BACKGROUND | PAL1), #160
  SET_SPRITE gameplay_cursor+20, #228, #Sprite::CursorRight, #(BEHIND_BACKGROUND | PAL1), #168 

  ; Setup combo sprites
  SET_SPRITE combo_text, #16, #'0', #PAL0, #16
  SET_SPRITE combo_text+4, #16, #'0', #PAL0, #24
  SET_SPRITE combo_text+8, #16, #'0', #PAL0, #32

  MOVE gameplay_cursor_position, #3

  ; Reset state
  lda #0
  sta frame
  sta frame+1

  sta timer
  sta timer+1
  sta timer+2
  sta notes_spawned
  sta notes_spawned+1
  sta combo
  sta combo+1

  sta perfect_hits
  sta perfect_hits+1
  sta great_hits
  sta great_hits+1
  sta good_hits
  sta good_hits+1
  sta bad_hits
  sta bad_hits+1
  sta misses
  sta misses+1

  sta live_notes_head_index
  sta live_notes_tail_index

  note_queue = live_notes_lanes
  ldx #(QUEUE_LEN * 6)
  :
    sta note_queue, X
    dex
    bne :-

  ; Setup scroll Y to bottom of screen initially
  MOVE scroll_y, #239 
  ; Compute map relevant information
  lda chart ; Read BPM and convert it to timing units
  clc
  rol
  sta frame_units 
  MOVE24 chart_length, {chart+1}      ; BPM is followed by the chart length
  MOVE16 chart_total_notes, {chart+4} ; followed by the number of notes
  LOAD16 note_ptr, #<(chart+6), #>(chart+6) ; Set the note pointer

  ; Play music
  lda #1
  ldx #<music_data_lower_short_ver
  ldy #>music_data_lower_short_ver
  jsr famistudio_init
  lda #0
  jsr famistudio_music_play

@loop:
  ; If the chart ended, then go to the score screen
  CMP24 timer, chart_length
  bcc :+
    jmp score_screen
:

  ; Gameplay logic
  jsr load_notes
  jsr check_delete_note

  ; Every ~10 seconds, there will be an extra frame, so don't tick on that one
;   ADD16B frame, frame, #$01, #$00
;   CMP16B frame, #$59, #$02 ; 601 in hex
;   bcs @skiptick
; @iftick:
;     jsr tick_timer
;     jsr inc_scroll
;     jmp @endif
; @skiptick:
;     load16 frame, #$00, #$00
; @endif:
  ; Tick the timer
  ADD24B timer, timer, frame_units, #$00, #$00
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
  cpy #30
  bcc @draw_left_2000

  ldy #64
@draw_left_2800:    ; Draw the left boundary on nametable $2800
  jsr ppu_set_tile
  iny
  cpy #94
  bcc @draw_left_2800

  lda #Tile::PlayfieldBoundaryRight
  ldx #(LANE_X + N_LANES * 2)
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

@check_left:
  IS_JUST_PRESSED BUTTON_LEFT
  beq @skip_left
    SUB_WRAP gameplay_cursor_position, #3, #(N_LANES-3) ; Move the cursor left
@skip_left:

@check_right:
  IS_JUST_PRESSED BUTTON_RIGHT
  beq @skip_right
    ADD_WRAP gameplay_cursor_position, #3, #(N_LANES) ; Move the cursor right 
@skip_right:

@check_a:
  IS_JUST_PRESSED BUTTON_A
  beq @skip_a
    lda #2 ; right
    jsr cursor_hit
@skip_a:

@check_up:
  IS_JUST_PRESSED BUTTON_UP
  beq @skip_up
    lda #1 ; middle
    jsr cursor_hit
@skip_up:

@check_b:
  IS_JUST_PRESSED BUTTON_B
  beq @skip_b
    lda #0 ; left
    jsr cursor_hit
@skip_b:

@update:
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
  adc #8
  sta gameplay_cursor+19
  adc #8
  sta gameplay_cursor+23

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
  CMP16 notes_spawned, chart_total_notes
  bcs end

  ldy mem_offset
  MOVE lanes, {(note_ptr), Y} ; Read lane byte
  iny
  MOVE timing1, {(note_ptr), Y} ; Read the 3 timing bytes
  iny
  MOVE timing2, {(note_ptr), Y} 
  iny
  MOVE timing3, {(note_ptr), Y} 
  iny

  ; Check if the note should be loaded, 
  ; i.e timing - timer <= SPAWN_DIFF
  SUB24 t1_24, timing1, timer ; compute timing - timer
  ; Notes are in chronological order so if timing - timer > SPAWN_DIFF then
  ; it's too early for this one so we can just return early
  CMP24B t1_24, #<SPAWN_DIFF, #>SPAWN_DIFF, #$00 ; compare with SPAWN_DIFF
  bcs end
  ; If we get here, then the note should be spawned
  ; so commit the mem_offset change and increment the note counter
  sty mem_offset
  inc notes_spawned

  ; Add this note to the live note queue
  ldx live_notes_tail_index
  MOVE {live_notes_lanes, X}, lanes
  MOVE {live_notes_timing1, X}, timing1
  MOVE {live_notes_timing2, X}, timing2
  MOVE {live_notes_timing3, X}, timing3
  MOVE {live_notes_hit, X}, #0
  
  ; Compute the scroll tile Y
  jsr scroll_position
  sta live_notes_nt_y, X
  tay ; Also move this into the Y register for drawing tiles

  INC_WRAP live_notes_tail_index, #QUEUE_LEN

  lda lanes
  jsr draw_note

  jmp loop

end:
  ; Add the accumulated memory offset to the note pointer
  ADD16B note_ptr, note_ptr, mem_offset, #$00
  
  POP s5
  POP s4
  POP s3
  POP s2
  POP s1
  rts
.endproc

.macro DRAW_NOTE_IMPL name, left_tile, middle_tile, right_tile
; Draws a single note. 
; ---Parameters---
; A - The lane byte of the note.
; Y - The Y coordinate to draw it at
.proc name
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
  lda #left_tile
  jsr ppu_update_tile
  inx
  ; Then draw the middle, that is until `note_end - 1`
  dec note_end
@draw_middle:  
  cpx note_end
  bcs @draw_right

  lda #middle_tile
  jsr ppu_update_tile
  inx
  jmp @draw_middle

@draw_right:
  ; Finish by drawing the right edge
  lda #right_tile
  jsr ppu_update_tile

  POP s2
  POP s1
  rts
.endproc
.endmacro

DRAW_NOTE_IMPL draw_note, Tile::NoteLeft, Tile::NoteMiddle, Tile::NoteRight
DRAW_NOTE_IMPL clear_note, Tile::Blank, Tile::Blank, Tile::Blank

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
    eor #$02
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

; Processes force misses.
.proc check_delete_note
@loop:
  ; If the queue is empty (head == tail), then break
  lda live_notes_head_index
  cmp live_notes_tail_index
  beq @end
  ; First check if the note is already marked for deletion by a hit input
  ldx live_notes_head_index
  lda live_notes_hit, X
  bne @increment
  ; Otherwise, compute timer - timing to see if we should remove the note from the queue
  SUB24B t1_24, timer, {live_notes_timing1, X}, {live_notes_timing2, X}, {live_notes_timing3, X}
  ; Notes in the live queue are stored in increasing time, so
  ; if the timing point hasn't passed yet, then we don't have to check any more notes
  bmi @end
  ; Here, the note has passed the timing point, so check if 
  ; difference >= MISS_DIFF
  CMP24B t1_24, #MISS_DIFF, #0, #0
  bcc @end
  ; Delete the note and remove from the queue.
  lda live_notes_lanes, X
  ldy live_notes_nt_y, X
  jsr clear_note
  ; Missed, so break combo
  LOAD16 combo, #$00, #$00
  INC16 misses             
  jsr draw_combo
@increment:
  INC_WRAP live_notes_head_index, #QUEUE_LEN
  bne @loop
@end:

  rts
.endproc

; Process a hit input on a lane
; This just marks the note as hit and clears from the nametable
; ---Parameters---
; A - Left, middle, or right (0 for left, 1 for middle, 2 for right)
.proc cursor_hit
  hit_lane = t1
  index = t2
  temp = t3

  clc
  adc gameplay_cursor_position
  sta hit_lane

  ; Check the live note queue for notes
  ; NOTE: Can be optimized, don't need to preserve the X register
  ; since when it would be clobbered (jsr clear_note) we break from the loop anyway
  MOVE index, live_notes_head_index
@loop:
  ; while (head_index != tail_index)
  ldx index
  cpx live_notes_tail_index
  beq @end
  
  jsr check_note_timing
  bcs @end

  ; end >= hit_lane

  ; Check if the hit falls within the note
  ; First check that hit_lane <= end
  lda live_notes_lanes, X
  and #$0F
  sta temp
  cmp hit_lane
  bcc @next
  ; Then check that hit_lane >= start
  lda live_notes_lanes, X
  lsr
  lsr
  lsr
  lsr
  sta temp
  lda hit_lane
  cmp temp
  bcc @next
  
  ; If we get here, then the note should be hit
  jsr calc_note_judgement

  ; Set hit to true
  MOVE {live_notes_hit, X}, #1
  ; Clear the note
  lda live_notes_lanes, X
  ldy live_notes_nt_y, X
  jsr clear_note
  ; Draw the new combo
  jsr draw_combo
  ; Break from the loop
  jmp @end

@next:
  INC_WRAP index, #QUEUE_LEN
  jmp @loop
  
@end:
  rts
.endproc

; Subroutine of cursor_hit.
.proc check_note_timing
  ; Check note timing difference
  LOAD24 t2_24, {live_notes_timing1, X}, {live_notes_timing2, X}, {live_notes_timing3, X}
  SUB24 t2_24, t2_24, timer
  bpl :+
    NEGATE24 t2_24
:
  ; If the note we're looking at is too early, then the rest must be later so just break
  ; TODO: Handle early hit better 
  CMP24B t2_24, #<IGNORE_DIFF, #>IGNORE_DIFF, #$00
  rts
.endproc

.proc calc_note_judgement
@miss:
  CMP24B t2_24, #<MISS_DIFF, #>MISS_DIFF, #$00
  bcc @bad
  ; If we missed, then break combo...
  INC16 misses             
  LOAD16 combo, #$00, #$00
  rts ; Then early return, because we don't want to increment the combo again
@bad:
  CMP24B t2_24, #<BAD_DIFF, #>BAD_DIFF, #$00
  bcc @good
  INC16 bad_hits
  jmp @hit
@good:
  CMP24B t2_24, #<GOOD_DIFF, #>GOOD_DIFF, #$00
  bcc @great
  INC16 good_hits
  jmp @hit
@great:
  CMP24B t2_24, #<GREAT_DIFF, #>GREAT_DIFF, #$00
  bcc @perfect
  INC16 great_hits
  jmp @hit
@perfect:
  INC16 perfect_hits ; Fallthrough case, don't need to do any extra comparisons

@hit:
  INC16 combo        ; For any of the hits, we should increment the combo
  rts
.endproc

.proc draw_combo
  lda combo
  jsr hex8_to_decimal
  
  MOVE combo_text+1, r1_24
  MOVE combo_text+5, r1_24+1
  MOVE combo_text+9, r1_24+2

  rts
.endproc
