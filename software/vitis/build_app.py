#!/usr/bin/env python3
import argparse
from pathlib import Path

import vitis


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_WORKSPACE = REPO_ROOT / "vitis_ws"
DEFAULT_APP = "vek280_miner_app"


def parse_args():
    parser = argparse.ArgumentParser(description="Build the R5 FreeRTOS miner app component.")
    parser.add_argument("--workspace", default=str(DEFAULT_WORKSPACE))
    parser.add_argument("--app", default=DEFAULT_APP)
    return parser.parse_args()


def main():
    args = parse_args()
    workspace = Path(args.workspace).resolve()

    client = vitis.create_client()
    try:
        client.set_workspace(path=str(workspace))
        component = client.get_component(name=args.app)
        component.build()
        print(f"Built app component: {workspace / args.app}")
    finally:
        vitis.dispose()


if __name__ == "__main__":
    main()
