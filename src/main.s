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

  ; Which screen we're on
  .enum Screen
    Title = 0
    SongSelect = 1
    Game = 2
  .endenum
  current_screen: .res 1

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

; === Title screen ===
str_hello: .asciiz "8-Bit Sekai"
str_press_start: .asciiz "PRESS START"

title_screen:
  ; handle input
  jsr poll_input
  lda buttons
  ; If START is pressed, go to the song select screen
  and #BUTTON_START
  beq :+
    jmp song_select
:

  ; Draw stuff
  DRAW_STRING str_hello, 10, 14
  DRAW_STRING str_press_start, 10, 16
  jsr ppu_update
  jmp title_screen

; === Song select ===
str_song_select: .asciiz "Song Select"

song_select:
  ; Clear the background first
  jsr ppu_disable_rendering
  jsr clear_background
@loop:
  DRAW_STRING str_song_select, 10, 6
  jsr ppu_update
  jmp @loop
