"""Program the current 4x32 PDI and launch the matching R5 application."""

import os
import time
from pathlib import Path

import xsdb


root = Path(__file__).resolve().parents[2]
pdi = Path(os.environ.get(
    "MINER_PDI",
    root / "bd/out_vek280_miner_4x32_ooc_dsp/miner_system_wrapper.pdi",
))
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

    # device_program returns after transfer completion, before PLM finishes
    # loading the PS and PL partitions.  The VEK280 image takes ~13 seconds.
    time.sleep(16)

    print(f"Downloading {elf}")
    r5 = session.targets(filter="name =~ \"*Cortex-R5*#0*\"")
    r5.rst("--clear_registers", type="processor")
    r5.dow("--clear", file=str(elf))
    r5.con()
    print("R5 application is running")
finally:
    xsdb.dispose()
