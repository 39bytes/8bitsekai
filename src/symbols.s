PPUCTRL = $2000
PPUMASK = $2001
PPUSTATUS = $2002
OAMADDR = $2003
OAMDATA = $2004
PPUSCROLL = $2005
PPUADDR = $2006
PPUDATA = $2007

.enum PpuCtrl
  NMIEnable  = 1 << 7
  Sprite8x16 = 1 << 5
.endenum

.enum PpuMask
  EnableSprites       = 1 << 4
  EnableBackground    = 1 << 3
  ShowSpritesLeft     = 1 << 2
  ShowBackgroundLeft  = 1 << 1
  Greyscale           = 1 << 0
.endenum

CONTROLLER1 = $4016

.charmap $41, $DC ; A
.charmap $42, $DD ; B
.charmap $43, $DE ; C
.charmap $44, $DF ; D
.charmap $45, $E0 ; E
.charmap $46, $E1 ; F
.charmap $47, $E2 ; G
.charmap $48, $E3 ; H
.charmap $49, $E4 ; I
.charmap $4a, $E5 ; J
.charmap $4b, $E6 ; K
.charmap $4c, $E7 ; L
.charmap $4d, $E8 ; M
.charmap $4e, $E9 ; N
.charmap $4f, $EA ; O
.charmap $50, $EB ; P
.charmap $51, $EC ; Q
.charmap $52, $ED ; R
.charmap $53, $EE ; S
.charmap $54, $EF ; T
.charmap $55, $F0 ; U
.charmap $56, $F1 ; V
.charmap $57, $F2 ; W
.charmap $58, $F3 ; X
.charmap $59, $F4 ; y
.charmap $60, $F5 ; Z
.charmap $30, $F6 ; 0
.charmap $31, $F7 ; 1
.charmap $32, $F8 ; 2
.charmap $33, $F9 ; 3
.charmap $34, $FA ; 4
.charmap $35, $FB ; 5
.charmap $36, $FC ; 6
.charmap $37, $FD ; 7
.charmap $38, $FE ; 8
.charmap $39, $FF ; 9
