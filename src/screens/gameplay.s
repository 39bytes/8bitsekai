; ============
; | Gameplay |
; ============

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

  combo:         .res 2
  max_combo:     .res 2
  ; Judgements
  perfect_hits:  .res 2 
  great_hits:    .res 2 
  good_hits:     .res 2 
  bad_hits:      .res 2 
  misses:        .res 2 

  
  ; The queue of notes currently present on the playfield
  live_notes_head_index: .res 1
  live_notes_tail_index: .res 1
  live_notes_lanes:      .res MAX_NOTES
  live_notes_timing1:    .res MAX_NOTES
  live_notes_timing2:    .res MAX_NOTES
  live_notes_timing3:    .res MAX_NOTES
  ; TODO: Waste less space with this
  live_notes_hit:        .res MAX_NOTES


SCREEN_WIDTH = 256
SCREEN_HEIGHT = 208
TILE_WIDTH = 8
CURSOR_WIDTH = 2 ; Lane width of the cursor
N_LANES = 6      ; Total number of lanes
LANE_WIDTH = 2   ; Tile width of 1 lane
LANE_X = 6       ; X position of the start of the lanes
SCROLL_SPEED = 4 ; Vertical scroll speed

; TODO: Dynamically calculate this
BPM = 4
; How many timing units ahead we should spawn the note?
SPAWN_DIFF = SCREEN_HEIGHT / SCROLL_SPEED * BPM * 2 
; How many timing units should have passed before force missing a live note?
PERFECT_DIFF = (BPM * 2) * 2
GREAT_DIFF = (BPM * 2) * 4
GOOD_DIFF = (BPM * 2) * 6
BAD_DIFF = (BPM * 2) * 8
MISS_DIFF = (BPM * 2) * 10
IGNORE_DIFF = (BPM * 2) * 15

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
  SET_SPRITE gameplay_cursor, #196, #Sprite::CursorLeft, #(BEHIND_BACKGROUND | PAL1), #128 
  SET_SPRITE gameplay_cursor+4, #196, #Sprite::CursorLeft, #(BEHIND_BACKGROUND | PAL1), #136
  SET_SPRITE gameplay_cursor+8, #196, #Sprite::CursorMiddle, #(BEHIND_BACKGROUND | PAL1), #144
  SET_SPRITE gameplay_cursor+12, #196, #Sprite::CursorMiddle, #(BEHIND_BACKGROUND | PAL1), #152

  ; Setup combo sprites
  SET_SPRITE combo_text, #112, #'0', #PAL0, #200
  SET_SPRITE combo_text+4, #112, #'0', #PAL0, #208
  SET_SPRITE combo_text+8, #112, #'0', #PAL0, #216
  SET_SPRITE combo_text+12, #112, #'0', #PAL0, #224

  ; Setup judgement sprites
  SET_SPRITE judgement_text, #128, #0, #PAL0, #0
  SET_SPRITE judgement_text+4, #128, #0, #PAL0, #0
  SET_SPRITE judgement_text+8, #128, #0, #PAL0, #0
  SET_SPRITE judgement_text+12, #128, #0, #PAL0, #0
  SET_SPRITE judgement_text+16, #128, #0, #PAL0, #0
  SET_SPRITE judgement_text+20, #128, #0, #PAL0, #0
  SET_SPRITE judgement_text+24, #128, #0, #PAL0, #0

  ; Setup note sprites, put them off screen
  ldx #0
@set_note:
  txa
  asl
  asl
  asl
  tay
  
  ; left
  MOVE {notes, Y}, #255
  MOVE {notes+1, Y}, #Sprite::NoteLeft
  MOVE {notes+2, Y}, #PAL0
  MOVE {notes+3, Y}, #0

  ;right
  MOVE {notes+4, Y}, #255
  MOVE {notes+5, Y}, #Sprite::NoteRight
  MOVE {notes+6, Y}, #PAL0
  MOVE {notes+7, Y}, #0

  inx
  cpx #MAX_NOTES
  bcc @set_note

  ; Setup judgement sprites

  MOVE gameplay_cursor_position, #2

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
  sta max_combo
  sta max_combo+1

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
  ldx #(MAX_NOTES * 6)
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
;     ; Tick the timer
;     ADD24B timer, timer, frame_units, #$00, #$00
;     jsr inc_scroll
;     jmp @endif
; @skiptick:
;     LOAD16 frame, #$00, #$00
; @endif:

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
    SUB_WRAP gameplay_cursor_position, #2, #(N_LANES-2) ; Move the cursor left
@skip_left:

@check_right:
  IS_JUST_PRESSED BUTTON_RIGHT
  beq @skip_right
    ADD_WRAP gameplay_cursor_position, #2, #(N_LANES) ; Move the cursor right 
@skip_right:

@check_a:
  IS_JUST_PRESSED BUTTON_A
  beq @skip_a
    lda #1 ; right
    jsr cursor_hit
@skip_a:

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

; Scroll all of the notes by SCROLL_SPEED.
.proc inc_scroll
  ldx live_notes_head_index

@move_note:
  cpx live_notes_tail_index
  beq @done

  ; If the note has been hit already, we don't want to move it,
  ; since it should be off screen.
  lda live_notes_hit, X
  bne @skip
  
  txa
  asl
  asl
  asl
  tay

  lda notes, Y
  adc #SCROLL_SPEED
  
  sta notes, Y
  sta notes+4, Y
  
@skip:
  INX_WRAP #MAX_NOTES
  jmp @move_note
@done:
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

  INC_WRAP live_notes_tail_index, #MAX_NOTES

  lda lanes
  ldy #0
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

; Draws a single note (positions the sprite at the correct coordinates)
; ---Parameters---
; X - The index of the note in the note queue
; Y - the Y coordinate to draw it at.
.proc draw_note
  @lane = t1
  @note_x = t2

  ; Read the lane byte
  MOVE @lane, {live_notes_lanes, X}
  
  ; Compute the sprite offset of this note
  txa
  asl
  asl
  asl
  tax

  ; Position should be (LANE_X * TILE_WIDTH) + lane * 16
  MOVE @note_x, #(LANE_X * TILE_WIDTH)
  lda @lane
  asl
  asl
  asl
  asl
  clc
  adc @note_x

  ; Write the note X coordinates, while we have it in the A register
  sta notes+3, X ; Left note
  adc #8
  sta notes+7, X ; Right note

  tya
  ; Then write the Y coordinates
  sta notes, X
  sta notes+4, X

  ; TODO: Color these?
  ; MOVE {notes+2, X}, #PAL0
  ; MOVE {notes+6, X}, #PAL0

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

  ; Missed, so break combo
  LOAD16 combo, #$00, #$00
  INC16 misses
  jsr draw_miss
  jsr draw_combo
@increment:
  INC_WRAP live_notes_head_index, #MAX_NOTES
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

  lda live_notes_lanes, X
  cmp hit_lane
  bne @next
  
  ; If we get here, then the note should be hit
  jsr calc_note_judgement

  ; Set hit to true
  MOVE {live_notes_hit, X}, #1

  ; Clear the note by moving it off screen.
  txa
  asl
  asl
  asl
  tay
  MOVE {notes, Y}, #255
  MOVE {notes+4, Y}, #255

  ; Draw the new combo
  jsr draw_combo
  ; Break from the loop
  jmp @end

@next:
  INC_WRAP index, #MAX_NOTES
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
  jsr draw_miss
  rts ; Then early return, because we don't want to increment the combo again
@bad:
  CMP24B t2_24, #<BAD_DIFF, #>BAD_DIFF, #$00
  bcc @good
  INC16 bad_hits
  jsr draw_bad
  jmp @hit
@good:
  CMP24B t2_24, #<GOOD_DIFF, #>GOOD_DIFF, #$00
  bcc @great
  INC16 good_hits
  jsr draw_good
  jmp @hit
@great:
  CMP24B t2_24, #<GREAT_DIFF, #>GREAT_DIFF, #$00
  bcc @perfect
  INC16 great_hits
  jsr draw_great
  jmp @hit
@perfect:
  INC16 perfect_hits ; Fallthrough case, don't need to do any extra comparisons
  jsr draw_perfect

@hit:
  INC16 combo            ; For any of the hits, we should increment the combo
  CMP16 combo, max_combo ; Then compute a new max combo
  bcc :+
    MOVE16 max_combo, combo
:
  rts
.endproc

.proc draw_combo
  MOVE16 p1_16, combo
  jsr hex16_to_decimal
  
  MOVE combo_text+1, r2
  MOVE combo_text+5, r3
  MOVE combo_text+9, r4
  MOVE combo_text+13, r5

  rts
.endproc

LEFT_WIDTH = (LANE_X + N_LANES * LANE_WIDTH) * TILE_WIDTH
RIGHT_CENTER = (SCREEN_WIDTH - LEFT_WIDTH) / 2 + LEFT_WIDTH

; width of text is 8 * length
; so start it at center - (text_width / 2)

PERFECT_WIDTH = .strlen("PERFECT") * TILE_WIDTH
PERFECT_START = RIGHT_CENTER - (PERFECT_WIDTH / 2)
.proc draw_perfect
  MOVE judgement_text+1, #'P'
  MOVE judgement_text+3, #(PERFECT_START)

  MOVE judgement_text+5, #'E'
  MOVE judgement_text+7, #(PERFECT_START+8)

  MOVE judgement_text+9, #'R'
  MOVE judgement_text+11, #(PERFECT_START+16)

  MOVE judgement_text+13, #'F'
  MOVE judgement_text+15, #(PERFECT_START+24)

  MOVE judgement_text+17, #'E'
  MOVE judgement_text+19, #(PERFECT_START+32)

  MOVE judgement_text+21, #'C'
  MOVE judgement_text+23, #(PERFECT_START+40)

  MOVE judgement_text+25, #'T'
  MOVE judgement_text+27, #(PERFECT_START+48)
  rts
.endproc

GREAT_WIDTH = .strlen("GREAT") * TILE_WIDTH
GREAT_START = RIGHT_CENTER - (GREAT_WIDTH / 2)
.proc draw_great
  MOVE judgement_text+1, #'G'
  MOVE judgement_text+3, #(GREAT_START)

  MOVE judgement_text+5, #'R'
  MOVE judgement_text+7, #(GREAT_START+8)

  MOVE judgement_text+9, #'E'
  MOVE judgement_text+11, #(GREAT_START+16)

  MOVE judgement_text+13, #'A'
  MOVE judgement_text+15, #(GREAT_START+24)

  MOVE judgement_text+17, #'T'
  MOVE judgement_text+19, #(GREAT_START+32)

  MOVE judgement_text+21, #0
  MOVE judgement_text+23, #(GREAT_START+40)

  MOVE judgement_text+25, #0
  MOVE judgement_text+27, #(GREAT_START+48)
  rts
.endproc

GOOD_WIDTH = .strlen("GOOD") * TILE_WIDTH
GOOD_START = RIGHT_CENTER - (GOOD_WIDTH / 2)
.proc draw_good
  MOVE judgement_text+1, #'G'
  MOVE judgement_text+3, #(GOOD_START)

  MOVE judgement_text+5, #'O'
  MOVE judgement_text+7, #(GOOD_START+8)

  MOVE judgement_text+9, #'O'
  MOVE judgement_text+11, #(GOOD_START+16)

  MOVE judgement_text+13, #'D'
  MOVE judgement_text+15, #(GOOD_START+24)

  MOVE judgement_text+17, #0
  MOVE judgement_text+19, #(GOOD_START+32)

  MOVE judgement_text+21, #0
  MOVE judgement_text+23, #(GOOD_START+40)

  MOVE judgement_text+25, #0
  MOVE judgement_text+27, #(GOOD_START+48)
  rts
.endproc

BAD_WIDTH = .strlen("BAD") * TILE_WIDTH
BAD_START = RIGHT_CENTER - (BAD_WIDTH / 2)
.proc draw_bad
  MOVE judgement_text+1, #'B'
  MOVE judgement_text+3, #(BAD_START)

  MOVE judgement_text+5, #'A'
  MOVE judgement_text+7, #(BAD_START+8)

  MOVE judgement_text+9, #'D'
  MOVE judgement_text+11, #(BAD_START+16)

  MOVE judgement_text+13, #0
  MOVE judgement_text+15, #(BAD_START+24)

  MOVE judgement_text+17, #0
  MOVE judgement_text+19, #(BAD_START+32)

  MOVE judgement_text+21, #0
  MOVE judgement_text+23, #(BAD_START+40)

  MOVE judgement_text+25, #0
  MOVE judgement_text+27, #(BAD_START+48)
  rts
.endproc

MISS_WIDTH = .strlen("MISS") * TILE_WIDTH
MISS_START = RIGHT_CENTER - (MISS_WIDTH / 2)
.proc draw_miss
  MOVE judgement_text+1, #'M'
  MOVE judgement_text+3, #(MISS_START)

  MOVE judgement_text+5, #'I'
  MOVE judgement_text+7, #(MISS_START+8)

  MOVE judgement_text+9, #'S'
  MOVE judgement_text+11, #(MISS_START+16)

  MOVE judgement_text+13, #'S'
  MOVE judgement_text+15, #(MISS_START+24)

  MOVE judgement_text+17, #0
  MOVE judgement_text+19, #(MISS_START+32)

  MOVE judgement_text+21, #0
  MOVE judgement_text+23, #(MISS_START+40)

  MOVE judgement_text+25, #0
  MOVE judgement_text+27, #(MISS_START+48)
  rts
.endproc
