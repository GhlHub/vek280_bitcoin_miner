"""Program the current 4x32 PDI and launch the matching R5 application."""

from pathlib import Path

import xsdb


root = Path(__file__).resolve().parents[2]
pdi = root / "bd/out_vek280_miner_4x32_ooc/miner_system_wrapper.pdi"
elf = root / "vitis_ws/vek280_miner_app/build/vek280_miner_app.elf"

for artifact in (pdi, elf):
    if not artifact.is_file():
        raise FileNotFoundError(artifact)

session = xsdb.start_debug_session()
try:
    session.connect(url="TCP:10.0.1.109:3121")

    print(f"Programming {pdi}")
    device = session.targets(id=1)
    device.device_program(file=str(pdi))

    print(f"Downloading {elf}")
    r5 = session.targets(id=3)
    r5.rst("--clear_registers", type="processor")
    r5.dow("--clear", file=str(elf))
    r5.con()
    print("R5 application is running")
finally:
    xsdb.dispose()
