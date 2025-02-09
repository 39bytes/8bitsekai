.segment "CODE"

.enum PpuSignal
  FrameReady = 1
  DisableRendering = 2
.endenum

.enum Tile
  Blank = $00
  LaneDark = $02
  LaneCursor = $03
  NoteLeft = $04
  NoteMiddle = $05
  NoteRight = $06
  PlayfieldBoundaryLeft = $07
  PlayfieldBoundaryRight = $08
.endenum

.enum Sprite
  Blank = $00
  CursorLeft = $02
  CursorMiddle = $03
  CursorRight = $04
.endenum

; Turn off the PPU rendering for manual nametable updates
; Clobbers A
.proc ppu_disable_rendering
  MOVE nmi_signal, #PpuSignal::DisableRendering
  :
    lda nmi_signal
    bne :-
  rts
.endproc

.macro ENABLE_RENDERING
  lda #%00011110
  sta PPUMASK
.endmacro

; Block until NMI returns
; Clobbers A
.proc ppu_update
  MOVE nmi_signal, #PpuSignal::FrameReady
  :
    lda nmi_signal
    bne :-
  rts
.endproc

; Block for X frames
.proc wait
  :
    jsr ppu_update
    dex
    bne :-

  rts
.endproc

.macro WAIT n_frames
  ldx n_frames
  jsr wait
.endmacro


; Set tile at X/Y to A next time ppu_update is called
; Can be used with rendering on
; Preserves X, Y and A
.proc ppu_update_tile
  ; This function just stores a nametable address + a tile ID for nametable $2000
  ; into the buffer.
  ; The address is gonna have the form 0010 00YY YYYX XXXX

  ; Preserve registers
  sta t1 ; t1 = A
  stx t2 ; t2 = X
  sty t3 ; t3 = Y

  ; Computing the high byte of the address
  ; Take only the top 2 bits of Y
  tya
  lsr
  lsr
  lsr
  ora #$20 

  ldx nt_update_len ; nt_update[nt_update_len] = addr high byte
  sta nt_update, X
  inx               ; nt_update_len++;

  ; Computing the lower byte of the address
  tya ; Put the low 3 bits of Y into the top
  asl
  asl
  asl
  asl
  asl
  sta t4
  ; load X
  lda t2 
  ora t4           ; OR in X so we get YYYX XXXX
  sta nt_update, X ; nt_update[nt_update_len] = addr high byte
  inx              ; nt_update_len++; 
  ; load A
  lda t1
  sta nt_update, X
  inx
  ; Write back the new length of nt_update 
  stx nt_update_len

  ; Restore registers
  lda t1
  ldx t2
  ldy t3

  rts
.endproc

.macro DRAW_TILE tile_id, tile_x, tile_y
  lda #tile_id
  ldx #tile_x
  ldy #tile_y
  jsr ppu_update_tile
.endmacro

; Update a byte in the nametable
; XY = A
.proc ppu_update_byte
  pha ; temporarily store A on stack
  tya
  pha ; temporarily store Y on stack
  ldy nt_update_len
  txa
  sta nt_update, Y
  iny
  pla ; recover Y value (but put in Y)
  sta nt_update, Y
  iny
  pla ; recover A value (byte)
  sta nt_update, Y
  iny
  sty nt_update_len

  rts
.endproc

; Set tile at X/Y to A immediately
; Must be used with rendering off
;  Y =  0- 31 nametable $2000
;  Y = 32- 63 nametable $2400
;  Y = 64- 95 nametable $2800
;  Y = 96-127 nametable $2C00
; Preserves A, X, Y
.proc ppu_set_tile 
  sta t1 ; Preserve registers
  stx t2
  sty t3

  lda PPUSTATUS ; reset latch
  ; The address is gonna have the form 0010 NNYY YYYX XXXX
  ; Compute high byte
  tya           
  lsr
  lsr
  lsr
  ora #$20 
  sta PPUADDR
  ; Compute low byte
  tya
  asl
  asl
  asl
  asl
  asl
  sta t4
  txa 
  ora t4
  sta PPUADDR
  ; Write the tile ID
  lda t1
  sta PPUDATA
  
  ldx t2 ; Restore registers
  ldy t3
  rts
.endproc

; 32x32 -> 16x16
; Update an attribute byte to A where the top left is X/Y
; y >> 1 |
.proc ppu_update_attribute
  pha
  low_byte = t1

  lda #$C0
  sta low_byte

  ; 0xC0 | (y >> 2) << 3 | (x >> 3)
  tya
  lsr 
  lsr 
  asl ; (y >> 2) << 3
  asl
  asl

  ora low_byte
  sta low_byte
  
  txa ; (x >> 2)
  lsr
  lsr
  
  ora low_byte
  sta low_byte

  ldx #$23
  ldy low_byte
  pla
  jsr ppu_update_byte

  rts
.endproc

; Makes the background all black.
; Rendering must be turned off before this is called.
.proc clear_background
  lda PPUSTATUS ; clear write latch

  ; Set base address for the first nametable
  MOVE PPUADDR, #$20
  MOVE PPUADDR, #$00

  ldy #30  ; 30 rows
  :
    ldx #32
    :
      sta PPUDATA
      dex
      bne :-
    dey
    bne :--

  rts
.endproc

.proc clear_sprites
  lda #0
  ldx #0
  :
    sta oam, X
    inx
    bne :-
  
  rts
.endproc

; Draws a null terminated string beginning at X, Y
; ---Parameters---
; ptr - Address of null terminated string
; X - Tile X
; Y - Tile Y
.macro DRAW_STRING_IMPL name, proc
.proc name
  ; Push saved registers
  PUSH s1
  PUSH s2
  
  tile_y = s1
  sty tile_y

  ldy #0
@loop:
  lda (ptr), Y ; while (str[y] != '\0')
  beq @loop_end
  sty s2     ; Preserve the y index
  ldy tile_y
  jsr proc
  ldy s2
  
  inx        ; x++
  iny        ; y++
  jmp @loop
@loop_end:
  ; Restore registers
  POP s2
  POP s1
  rts
.endproc
.endmacro

DRAW_STRING_IMPL draw_string, ppu_update_tile
DRAW_STRING_IMPL draw_string_imm, ppu_set_tile

; Draw a string literal at immediate tile coordinates
.macro DRAW_STRING static_str, tile_x, tile_y
  MOVE ptr,     #<static_str ; write low byte
  MOVE {ptr+1}, #>static_str ; write high byte
  ldx tile_x
  ldy tile_y
  jsr draw_string
.endmacro

.macro DRAW_STRING_IMM static_str, tile_x, tile_y
  MOVE ptr,     #<static_str ; write low byte
  MOVE {ptr+1}, #>static_str ; write high byte
  ldx tile_x
  ldy tile_y
  jsr draw_string_imm
.endmacro

; Draws a number encoded in binary coded decimal onto the screen.
; ---Parameters---
; X - X position of the first digit
; Y - Y position
; p1_24 - The number in binary coded decimal (ascii)
.proc draw_bcd_number
  PUSH s1
  PUSH s2

  MOVE s1, #0
  sty s2

  ldy s1
  lda p1_24, Y
  ldy s2
  jsr ppu_update_tile
  inc s1
  inx

  ldy s1
  lda p1_24, Y
  ldy s2
  jsr ppu_update_tile
  inc s1
  inx

  ldy s1
  lda p1_24, Y
  ldy s2
  jsr ppu_update_tile

  POP s1
  POP s2
  rts
.endproc

.macro DEBUG_VAR var, tile_x, tile_y
  lda var
  jsr hex8_to_decimal
  MOVE24 p1_24, r1_24
  ldx #tile_x
  ldy #tile_y
  jsr draw_bcd_number
.endmacro
