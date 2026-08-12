"""Reset, download, and start the current R5 application without reprogramming PL."""

from pathlib import Path

import xsdb


root = Path(__file__).resolve().parents[2]
elf = root / "vitis_ws/vek280_miner_app/build/vek280_miner_app.elf"
if not elf.is_file():
    raise FileNotFoundError(elf)

session = xsdb.start_debug_session()
try:
    session.connect(url="TCP:10.0.1.109:3121")
    r5 = session.targets(id=3)
    r5.rst("--clear_registers", type="processor")
    r5.dow("--clear", file=str(elf))
    r5.con()
finally:
    xsdb.dispose()
