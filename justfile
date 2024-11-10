rom_name := "8bitsekai.nes"

build:
    cl65 --verbose --target nes -C config.cfg -o {{rom_name}} src/main.s

run: build
    fceux {{rom_name}}

import-tiles:
    cp ~/.wine/drive_c/8bitsekai\ bg\ tiles.chr assets/bg_tiles.chr
    cp ~/.wine/drive_c/8bitsekai\ spr\ tiles.chr assets/spr_tiles.chr
