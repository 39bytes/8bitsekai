rom_name := "8bitsekai.nes"
debug_filename := "debug-symbols.txt"


build:
    cl65 --verbose --target nes -C config.cfg -o {{rom_name}} -g -Ln {{debug_filename}} src/main.s 
    python debug-namelist.py {{rom_name}} {{debug_filename}}
    rm {{debug_filename}}

run: build
    fceux {{rom_name}}

import-tiles:
    cp ~/.wine/drive_c/8bitsekai\ bg\ tiles.chr assets/bg_tiles.chr
    cp ~/.wine/drive_c/8bitsekai\ spr\ tiles.chr assets/spr_tiles.chr
