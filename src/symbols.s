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
