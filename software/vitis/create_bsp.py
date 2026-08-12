#!/usr/bin/env python3
import argparse
import os
import shutil
from pathlib import Path

import vitis


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_XSA = (
    REPO_ROOT / "reports" / "impl_vek280_4x32_ooc" / "miner_system_wrapper.xsa"
)
DEFAULT_WORKSPACE = REPO_ROOT / "vitis_ws"
DEFAULT_PLATFORM = "vek280_miner_platform"
DEFAULT_DOMAIN = "r5_freertos"
DEFAULT_CPU = "psv_cortexr5_0"


def parse_args():
    parser = argparse.ArgumentParser(
        description="Create the VEK280 miner Vitis platform and FreeRTOS BSP."
    )
    parser.add_argument("--xsa", default=str(DEFAULT_XSA), help="Exported hardware XSA")
    parser.add_argument("--workspace", default=str(DEFAULT_WORKSPACE), help="Vitis workspace")
    parser.add_argument("--platform", default=DEFAULT_PLATFORM, help="Platform component name")
    parser.add_argument("--domain", default=DEFAULT_DOMAIN, help="FreeRTOS domain name")
    parser.add_argument("--cpu", default=DEFAULT_CPU, help="Processor instance for the BSP")
    parser.add_argument(
        "--clean",
        action="store_true",
        help="Delete the existing workspace before creating the platform",
    )
    return parser.parse_args()


def main():
    args = parse_args()
    xsa = Path(args.xsa).resolve()
    workspace = Path(args.workspace).resolve()

    if not xsa.is_file():
        raise FileNotFoundError(f"XSA not found: {xsa}")

    clean_requested = args.clean or os.environ.get("VITIS_BSP_CLEAN") == "1"
    if clean_requested and workspace.exists():
        shutil.rmtree(workspace)

    workspace.mkdir(parents=True, exist_ok=True)

    client = vitis.create_client()
    try:
        client.set_workspace(path=str(workspace))
        platform = client.create_platform_component(
            name=args.platform,
            hw_design=str(xsa),
            os="freertos",
            cpu=args.cpu,
            domain_name=args.domain,
            desc="VEK280 Bitcoin miner platform with R5 FreeRTOS BSP",
        )
        platform.report()
        platform.build()
    finally:
        vitis.dispose()

    xpfm = workspace / args.platform / "export" / args.platform / f"{args.platform}.xpfm"
    print(f"Created platform: {xpfm}")
    print(f"Created FreeRTOS BSP domain: {args.domain} on {args.cpu}")


if __name__ == "__main__":
    main()
