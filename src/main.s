.include "symbols.s"
.include "macros.s"

INES_MAPPER = 0 ; Mapper 0
INES_MIRROR = 1 ; Horizontal mirroring
INES_SRAM   = 0 ; Battery backed RAM on cartridge

.segment "HEADER" 
  .byte $4E, $45, $53, $1A ; Identifier
  .byte 2                  ; 2x 16KB PRG code
  .byte 1                  ; 1x  8KB CHR data
  .byte INES_MIRROR | (INES_SRAM << 1) | ((INES_MAPPER & $0F) << 4)
  .byte (INES_MAPPER & $F0)
  .byte $0, $0, $0, $0, $0, $0, $0, $0 ; padding

.segment "VECTORS"
  .addr nmi
  .addr reset
  .addr irq

.segment "TILES"
  .incbin "../assets/tiles.chr"

.segment "ZEROPAGE"
  ; NMI state
  nmi_lock: .res 1 ; Prevent NMI re-entry
  ; Signals for the NMI handler
  ; If set to PpuSignal::FrameReady, trigger a frame update (write nt_update)
  ; If set to PpuSignal::DisableRendering, turn off PPU rendering
  ; When the NMI triggers, the NMI handler will set this variable back to 0,
  ; which means it acknowledged the signal.
  nmi_signal: .res 1 

  ; Temp registers
  t1: .res 1
  t2: .res 1
  t3: .res 1
  t4: .res 1
  ; Saved registers
  s1: .res 1
  s2: .res 1
  s3: .res 1
  s4: .res 1
  ; For indirect indexing
  ptr: .res 2
  ; Parameter registers
  p1: .res 1
  p2: .res 1

.segment "OAM"
  oam: .res 256


.segment "BSS"
  ; Nametable/palette buffers for PPU update
  nt_update:     .res 256 
  nt_update_len: .res 1
  pal_update:    .res 32

.include "ppu.s"
.include "input.s"

.segment "CODE"

reset:
  sei           ; disable IRQs
  cld           ; disable decimal mode
  ldx #$40
  stx $4017     ; disable APU frame IRQ
  ldx #$ff      ; Set up stack
  txs           ;  .
  inx           ; now X = 0
  stx PPUCTRL	; disable NMI
  stx PPUMASK	; disable rendering
  stx $4010 	; disable DMC IRQs

;; first wait for vblank to make sure PPU is ready
vblankwait1:
  bit PPUSTATUS
  bpl vblankwait1

clear_memory:
  lda #$00
  sta $0000, x
  sta $0100, x
  sta $0200, x
  sta $0300, x
  sta $0400, x
  sta $0500, x
  sta $0600, x
  sta $0700, x
  inx
  bne clear_memory
  
  jsr clear_background

; second wait for vblank, PPU is ready after this
vblankwait2:
  bit PPUSTATUS
  bpl vblankwait2

  MOVE PPUCTRL, #%10000000	; Enable NMI
  MOVE PPUMASK, #%00011110	; Enable rendering
  jmp main
    
nmi: 
  PUSH_AXY
  ; Lock the NMI, if the NMI takes too long then it will re-enter itself, 
  ; this will make it return immediately if that does happen.
  lda nmi_lock
  beq :+
    jmp @nmi_end
:
  MOVE nmi_lock, #1 

  ; Rendering logic
  ; Check what the NMI signal is
  lda nmi_signal 
  bne :+          ; If the signal is 0, that means the next frame isn't ready yet
    jmp @nmi_end
:
  cmp #PpuSignal::DisableRendering 
  bne :+
    MOVE PPUMASK, #%00000000 ; Disable rendering then end exit NMI
    jmp @ppu_update_done
:

  ; otherwise the signal must've been PpuSignal::FrameRead

  ; Update the nametables with the buffered tile updates
  ldx #0
  
  @nt_update_loop: 
    MOVE PPUADDR, {nt_update, X} ; Write addr high byte
    inx
    MOVE PPUADDR, {nt_update, X} ; Write addr low byte
    inx
    MOVE PPUDATA, {nt_update, X} ; Write tile ID    
    inx
    ; while (x < nt_update_len)
    cpx nt_update_len
    bcc @nt_update_loop

  ; Clear the buffer
  MOVE nt_update_len, #0

@scroll:
  lda #0
  and #%00000011 ; keep only lowest 2 bits to prevent error
  ora #%10001000
  sta PPUCTRL
  lda #0
  sta PPUSCROLL
  lda #0
  sta PPUSCROLL
  MOVE PPUMASK, #%00011110 ; Enable rendering

@ppu_update_done:
  ; Done rendering, unlock NMI and acknowledge frame as complete
  lda #0
  sta nmi_lock
  sta nmi_signal

@nmi_end:
  POP_YXA
  rti

irq:
  rti

palettes:
  ; Background Palette
  .byte $0f, $10, $20, $30
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00

  ; Sprite Palette
  .byte $0f, $20, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00

.enum Tile
  Blank = $00
  LaneDark = $02
  LaneCursor = $03
.endenum

main:
  lda PPUSTATUS       ; reset write latch
  MOVE PPUADDR, #$3f ; write palette base addr ($3F00)
  MOVE PPUADDR, #$00
  
  ldx #$00
@load_palettes:   ; Load all 20 bytes of palettes
  MOVE PPUDATA, {palettes, X}
  inx
  cpx #$20
  bne @load_palettes

  ; Load title screen
  jmp title_screen

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

; ===============
; | Song Select |
; ===============
str_song_select: .asciiz "Song Select"

; Songs
str_lower:	.asciiz "Lower"
str_mesmerizer: .asciiz "Mesmerizer"
str_senbonzakura: .asciiz "Senbonzakura"
str_rokuchounen: .asciiz "6 Trillion Years"

N_MENU_ITEMS = 4
MENU_X = 8
MENU_Y = 9

menu_item_labels:
  .addr str_lower      
  .addr str_mesmerizer 
  .addr str_senbonzakura
  .addr str_rokuchounen

menu_item_addrs:

song_select:
  ; Clear the background first
  jsr ppu_disable_rendering
  jsr clear_background
@loop:
  ; Clear the current cursor position
  ldx #(MENU_X - 1)
  lda #MENU_Y
  clc
  adc menu_cursor_position
  tay
  lda #Tile::Blank
  jsr ppu_update_tile

  ; Input handling
  jsr poll_input

  IS_JUST_PRESSED BUTTON_UP
  beq @skip_up
    DEC_WRAP menu_cursor_position, #(N_MENU_ITEMS-1)
@skip_up:

  IS_JUST_PRESSED BUTTON_DOWN
  beq @skip_down
    INC_WRAP menu_cursor_position, #N_MENU_ITEMS
@skip_down:

  IS_JUST_PRESSED BUTTON_START
  beq @skip_start
    ; TODO: make the selection actually mean something
    MOVE last_frame_buttons, buttons
    jmp gameplay
@skip_start:

  MOVE last_frame_buttons, buttons

  ; Draw the 'Song Select' title and the songs list
  DRAW_STRING str_song_select, 10, 6
  jsr draw_songs_list
  jsr draw_cursor

  jsr ppu_update
  jmp @loop
  
; Draw the menu items (songs) in the song select screen.
; Clobbers x
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
  jsr draw_string
  inc s1

  ; pop it back
  pla
  tax
  cpx #(2 * N_MENU_ITEMS)
  bne @loop
  
  POP s1
  rts
.endproc

.proc draw_cursor
  ldx #(MENU_X - 1)
  ; y = 8 + menu_cursor_position
  lda #MENU_Y
  clc
  adc menu_cursor_position
  tay

  lda #'>'

  jsr ppu_update_tile
  rts
.endproc

; ============
; | Gameplay |
; ============

.segment "ZEROPAGE"
  gameplay_cursor_position: .res 1 ; Lane index of the beginning

CURSOR_WIDTH = 2 ; Lane width of the cursor
N_LANES = 8    ; Total number of lanes
LANE_WIDTH = 2 ; Tile width of 1 lane
LANE_X = 8 ; X position of the start of the lanes
LANE_Y = 28 ; Y position of the lanes
  
.segment "CODE"

str_gameplay: .asciiz "Gameplay"

gameplay:
  ; Clear the background first
  jsr ppu_disable_rendering
  jsr clear_background
@loop:
  jsr handle_gameplay_input

  DRAW_STRING str_gameplay, 12, 0
  ; Debug info
  ldx #2
  ldy #2
  lda gameplay_cursor_position
  clc
  adc #'0'
  jsr ppu_update_tile

  jsr draw_lanes
  
  jsr ppu_update
  jmp @loop

.proc draw_lanes
  PUSH s1
  PUSH s2

  cursor_start = s1
  cursor_end = s2

  ; Compute the start lane of cursor
  ; gameplay_cursor_position * 2 + LANE_X
  lda gameplay_cursor_position ; TODO: figure out how to also do this for 3 width
  asl
  clc
  adc #LANE_X
  sta cursor_start

  ; Compute end lane of cursor
  ; CURSOR_WIDTH * 2 added to start lane
  ldx #CURSOR_WIDTH
  stx cursor_end
  asl cursor_end
  clc 
  adc cursor_end
  sta cursor_end

  ldx #LANE_X
  ldy #LANE_Y
@loop:
  ; if cursor_start <= x < cursor_end
  cpx cursor_start
  bcc @dark
  cpx cursor_end
  bcs @dark
@light:
  lda #Tile::LaneCursor ; use the light color
  jmp @draw
@dark:
  lda #Tile::LaneDark   ; else use the dark color
@draw:
  jsr ppu_update_tile   ; draw the tile
  inx
  cpx #(LANE_X + N_LANES * LANE_WIDTH) ; loop until all lanes covered
  bcc @loop

  POP s2
  POP s1
  rts
.endproc

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
