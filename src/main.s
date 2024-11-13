.include "symbols.s"
.include "macros.s"

INES_MAPPER = 0 ; Mapper 0
INES_MIRROR = 0 ; Horizontal mirroring
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
  .incbin "../assets/bg_tiles.chr"
  .incbin "../assets/spr_tiles.chr"

.segment "ZEROPAGE" ; NMI state
  nmi_lock: .res 1 ; Prevent NMI re-entry
  ; Signals for the NMI handler
  ; If set to PpuSignal::FrameReady, trigger a frame update (write nt_update)
  ; If set to PpuSignal::DisableRendering, turn off PPU rendering
  ; When the NMI triggers, the NMI handler will set this variable back to 0,
  ; which means it acknowledged the signal.
  nmi_signal: .res 1 
  ; Scrolling
  scroll_y: .res 1  ; Only using vertical scrolling, X is always 0
  scroll_nt: .res 1 ; Bit 1 of PPUCTRL

  ; Temp registers - volatile
  t1_16:
    t1: .res 1
    t2: .res 1
  t2_16:
    t3: .res 1
    t4: .res 1

  ; Saved registers - non-volatile
  s1_16:
    s1: .res 1
    s2: .res 1
  s2_16:
    s3: .res 1
    s4: .res 1
  s5: .res 1
  s6: .res 1
  

  ; For indirect indexing - volatile
  ptr: .res 2

  ; Parameter registers - volatile
  p1_24:
    p1_16:
      p1: .res 1
      p2: .res 1
    p2_16:
      p3: .res 1
  p2_24:
      p4: .res 1
      p5: .res 1
      p6: .res 1

  ; Return registers - volatile
  r1_24:
    r1_16:
      r1: .res 1
      r2: .res 1
      r3: .res 1


.segment "BSS"
  ; Nametable buffers/palette  for PPU update
  nt_update:     .res 256 
  nt_update_len: .res 1
  palette:       .res 32

.segment "OAM"
  oam:
    sprite0: .res 4
    gameplay_cursor: .res 16

.include "ppu.s"
.include "input.s"
.include "math.s"

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
; place all sprites offscreen at Y=255
  lda #255
  ldx #0
set_sprite:
  sta oam, X
  inx
  inx
  inx
  inx
  bne set_sprite

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
    jmp @ppu_update_done
:
  cmp #PpuSignal::DisableRendering 
  bne :+
    MOVE PPUMASK, #%00000000 ; Disable rendering then exit NMI
    jmp @ppu_update_done
:

  ; Otherwise the signal must've been PpuSignal::FrameRead
  ; Upload sprites via OAM DMA
  MOVE OAMADDR, #0
  MOVE OAMDMA, #>oam

  ; Update palettes with the buffered palette updates
  MOVE PPUCTRL, #(NMI_ENABLE | SPRITE_PT_RIGHT) ; Ensure that NT increment is horizontal
  lda PPUSTATUS      ; Clear write latch
  MOVE PPUADDR, #$3F ; Write palette base address
  MOVE PPUADDR, #$00

  ldx #0
  @palette_update_loop:
    MOVE PPUDATA, {palette, X}
    inx
    cpx #32
    bcc @palette_update_loop

  ; Update the nametables with the buffered tile updates
  ldx #0
  cpx nt_update_len
  bcs @scroll
  
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
  lda scroll_nt
  ora #(NMI_ENABLE | SPRITE_PT_RIGHT) ; Append other flags
  sta PPUCTRL
  lda PPUSTATUS      ; Clear write latch
  lda #0        ; X coordinate for first write, always 0
  sta PPUSCROLL 
  lda scroll_y  ; Y coordinate for second write
  sta PPUSCROLL
  MOVE PPUMASK, #(ENABLE_SPRITES | ENABLE_BG | SHOW_SPRITES_LEFT | SHOW_BG_LEFT) ; Enable rendering

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

default_palette:
  ; Background Palette
  .byte $0f, $10, $20, $30
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00

  ; Sprite Palette
  .byte $0f, $10, $20, $30
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00
  .byte $0f, $00, $00, $00

main:
  ldx #0
  MOVE PPUADDR, #$3F
  MOVE PPUADDR, #$00
@load_palettes:   ; Load all 32 bytes of palettes
  MOVE {palette, X}, {default_palette, X}
  MOVE PPUDATA, {default_palette, X}
  inx
  cpx #32
  bne @load_palettes

  ; Load title screen
  jmp title_screen


.include "title_screen.s"
.include "song_select.s"
.include "gameplay.s"

