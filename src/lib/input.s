.segment "ZEROPAGE"
  buttons: .res 1
  last_frame_buttons: .res 1

.segment "CODE"
; --------------
; Input handling
; --------------

; I would use an enum for this, but 'A' is not allowed since
; it conflicts with register A...
BUTTON_RIGHT  = 1 << 0
BUTTON_LEFT   = 1 << 1
BUTTON_DOWN   = 1 << 2
BUTTON_UP     = 1 << 3
BUTTON_START  = 1 << 4
BUTTON_SELECT = 1 << 5
BUTTON_B      = 1 << 6
BUTTON_A      = 1 << 7

; Reads the input bitset of buttons from the controller.
; Stores it in `buttons` on the zeropage.
; Preserves: X, Y
.proc poll_input
  ; Turn strobe on and off to poll input state once
  lda #1
  sta CONTROLLER1
  sta buttons     ; Insert a bit here that will be shifted out into the carry after 8 reads to end the loop
  lda #0
  sta CONTROLLER1
  
@read_button:
  lda CONTROLLER1
  lsr a        ; bit 0 -> Carry
  rol buttons  ; Carry -> bit 0; bit 7 -> Carry
  bcc @read_button

  rts
.endproc

.macro IS_PRESSED btn
  lda buttons
  and #btn
.endmacro

; Zero flag will be set if false,
; unset if true.
.macro IS_JUST_PRESSED btn
  lda last_frame_buttons
  eor #$FF
  and buttons
  and #btn
.endmacro
