PPUCTRL = $2000
; PPUCTRL bit flags
NMI_ENABLE          = 1 << 7
SPRITE_8X16         = 1 << 5
BG_PT_RIGHT         = 1 << 4
SPRITE_PT_RIGHT     = 1 << 3
VRAM_INCREMENT_DOWN = 1 << 2

PPUMASK = $2001
; PPUMASK bit flags
ENABLE_SPRITES    = 1 << 4
ENABLE_BG         = 1 << 3
SHOW_SPRITES_LEFT = 1 << 2
SHOW_BG_LEFT      = 1 << 1

PPUSTATUS = $2002
OAMADDR = $2003
OAMDATA = $2004
PPUSCROLL = $2005
PPUADDR = $2006
PPUDATA = $2007
OAMDMA = $4014

CONTROLLER1 = $4016
