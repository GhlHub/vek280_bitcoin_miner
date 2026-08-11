#!/usr/bin/env python3
import argparse
import shutil
from pathlib import Path

import vitis


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_WORKSPACE = REPO_ROOT / "vitis_ws"
DEFAULT_PLATFORM_XPFM = (
    DEFAULT_WORKSPACE
    / "vek280_miner_platform"
    / "export"
    / "vek280_miner_platform"
    / "vek280_miner_platform.xpfm"
)
DEFAULT_APP = "vek280_miner_app"
DEFAULT_DOMAIN = "r5_freertos"


def parse_args():
    parser = argparse.ArgumentParser(description="Create/build the R5 FreeRTOS miner app.")
    parser.add_argument("--workspace", default=str(DEFAULT_WORKSPACE))
    parser.add_argument("--platform", default=str(DEFAULT_PLATFORM_XPFM))
    parser.add_argument("--app", default=DEFAULT_APP)
    parser.add_argument("--domain", default=DEFAULT_DOMAIN)
    parser.add_argument("--clean", action="store_true")
    return parser.parse_args()


def main():
    args = parse_args()
    workspace = Path(args.workspace).resolve()
    platform = Path(args.platform).resolve()
    app_dir = workspace / args.app

    if not platform.is_file():
        raise FileNotFoundError(f"Platform not found: {platform}")
    if args.clean and app_dir.exists():
        shutil.rmtree(app_dir)

    client = vitis.create_client()
    try:
        client.set_workspace(path=str(workspace))
        client.create_app_component(
            name=args.app,
            platform=str(platform),
            domain=args.domain,
            template="empty_application",
        )
        print(f"Created app component: {app_dir}")
    finally:
        vitis.dispose()


if __name__ == "__main__":
    main()
