import sys


class DebugSymbol:
    addr: int
    label: str

    def __init__(self, line: str):
        t, addr, label = line.strip().split()
        assert t == "al"
        # NOTE: ca65 prefixes addresses with 2 extra 0s, only using
        # 32K for now so don't need to worry about it, but in the future
        # when using a bigger cart need to change this
        self.addr = int(addr[2:], 16)
        self.label = label[1:]

    def __str__(self):
        return f"${self.addr:04X}#{self.label}#\n"


def main():
    rom_name, debug_filename = sys.argv[1], sys.argv[2]
    with open(debug_filename) as f:
        symbols = sorted(map(DebugSymbol, f.readlines()), key=lambda s: s.addr)

    ram_labels = []
    rom_labels = []

    for sym in sorted(symbols, key=lambda s: s.addr):
        if 0x0000 <= sym.addr < 0x8000:
            ram_labels.append(str(sym))
        else:
            rom_labels.append(str(sym))

    with open(f"{rom_name}.ram.nl", "w+") as f:
        f.writelines(ram_labels)

    with open(f"{rom_name}.0.nl", "w+") as f:
        f.writelines(rom_labels)

    with open(f"{rom_name[:-4]}.fdb", "w+") as f:
        for sym in symbols:
            if sym.label.startswith("@"):
                continue
            f.write(f'Bookmark: addr={sym.addr:04X}  desc="{sym.label}"\n')


if __name__ == "__main__":
    main()
