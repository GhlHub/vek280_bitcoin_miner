#!/usr/bin/env python3
import argparse
import os
import re
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


def replace_once(text, old, new, path):
    if old not in text:
        raise RuntimeError(f"Expected text not found in {path}: {old!r}")
    return text.replace(old, new, 1)


def patch_user_config(app_src):
    path = app_src / "UserConfig.cmake"
    text = path.read_text()
    use_ddr_heap = True
    freertos_config = REPO_ROOT / "software" / "vek280_freertos" / "include" / "FreeRTOSConfig.h"
    freertos_h = REPO_ROOT / "FreeRTOS-LTS" / "FreeRTOS" / "FreeRTOS-Kernel" / "include" / "FreeRTOS.h"
    definitions = """
ipconfigZERO_COPY_RX_DRIVER=1
ipconfigZERO_COPY_TX_DRIVER=1
nicUSE_UNCACHED_MEMORY=0
ipconfigNIC_N_TX_DESC=8
ipconfigNIC_N_RX_DESC=8
""".strip()
    miner_axi_instances = os.environ.get("MINER_AXI_INSTANCES", "")
    if not miner_axi_instances:
        miner_slaves = os.environ.get("MINER_NUM_SLAVES", "")
        if miner_slaves:
            miner_axi_instances = miner_slaves
    if miner_axi_instances:
        definitions += f"\nMINER_AXI_INSTANCES={miner_axi_instances}U"
        definitions += f"\nMINER_NUM_ENGINES_EXPECTED=({miner_axi_instances}U * 32U)"
    includes = """
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/include
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/netif_versal
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/include
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/portable/Compiler/GCC
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/portable/NetworkInterface/xilinx_ultrascale
""".strip()
    sources = """
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/src/main.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/src/app_memory.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/src/miner_regs.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/src/miner_service.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/src/sha256_sw.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/src/stratum_client.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/src/telnet_server.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_ARP.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_BitConfig.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_DHCP.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_DNS.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_DNS_Cache.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_DNS_Callback.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_DNS_Networking.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_DNS_Parser.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_ICMP.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_IP.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_IP_Timers.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_IP_Utils.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_IPv4.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_IPv4_Sockets.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_IPv4_Utils.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_Routing.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_Sockets.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_Stream_Buffer.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_IP.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_IP_IPv4.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_Reception.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_State_Handling.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_State_Handling_IPv4.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_Transmission.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_Transmission_IPv4.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_Utils.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_Utils_IPv4.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_TCP_WIN.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_UDP_IP.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_UDP_IPv4.c
${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/portable/BufferManagement/BufferAllocation_1.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/netif_versal/NetworkInterface.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/netif_versal/uncached_memory.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/netif_versal/x_emacpsif_dma.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/netif_versal/x_emacpsif_hw.c
${CMAKE_SOURCE_DIR}/../../../software/vek280_freertos/netif_versal/x_emacpsif_physpeed.c
""".strip()
    if use_ddr_heap:
        definitions += "\nAPP_USE_DDR_HEAP=1"
        sources = sources.replace(
            "${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_ARP.c",
            "${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Kernel/portable/MemMang/heap_4.c\n"
            "${CMAKE_SOURCE_DIR}/../../../FreeRTOS-LTS/FreeRTOS/FreeRTOS-Plus-TCP/source/FreeRTOS_ARP.c",
        )

    text, count = re.subn(
        r"set\(USER_COMPILE_DEFINITIONS\n[\s\S]*?\n?\)",
        f"set(USER_COMPILE_DEFINITIONS\n{definitions}\n)",
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise RuntimeError(f"Failed to replace USER_COMPILE_DEFINITIONS in {path}")

    text, count = re.subn(
        r"set\(USER_INCLUDE_DIRECTORIES\n[\s\S]*?\n?\)",
        f"set(USER_INCLUDE_DIRECTORIES\n{includes}\n)",
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise RuntimeError(f"Failed to replace USER_INCLUDE_DIRECTORIES in {path}")

    text, count = re.subn(
        r"set\(USER_COMPILE_SOURCES\n[\s\S]*?\n?\)",
        f"set(USER_COMPILE_SOURCES\n{sources}\n)",
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise RuntimeError(f"Failed to replace USER_COMPILE_SOURCES in {path}")

    text, count = re.subn(
        r"set\(USER_LINK_OTHER_FLAGS\n[\s\S]*?\n?\)",
        "set(USER_LINK_OTHER_FLAGS\n-Wl,--wrap=XTimer_SetHandler\n)",
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise RuntimeError(f"Failed to replace USER_LINK_OTHER_FLAGS in {path}")

    text, count = re.subn(
        r"set\(USER_COMPILE_OTHER_FLAGS(?:[^\n)]*|\n[\s\S]*?\n?)\)",
        f"set(USER_COMPILE_OTHER_FLAGS\n\" -include {freertos_config} -include {freertos_h}\"\n)",
        text,
        count=1,
        flags=re.S,
    )
    if count != 1:
        raise RuntimeError(f"Failed to replace USER_COMPILE_OTHER_FLAGS in {path}")

    path.write_text(text)


def patch_linker_script(app_src):
    path = app_src / "lscript.ld"
    text = path.read_text()

    replacements = {
        "_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x2000;":
            "_STACK_SIZE = DEFINED(_STACK_SIZE) ? _STACK_SIZE : 0x1000;",
        "_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x2000;":
            "_HEAP_SIZE = DEFINED(_HEAP_SIZE) ? _HEAP_SIZE : 0x1000;",
        "_ABORT_STACK_SIZE = DEFINED(_ABORT_STACK_SIZE) ? _ABORT_STACK_SIZE : 1024;":
            "_ABORT_STACK_SIZE = DEFINED(_ABORT_STACK_SIZE) ? _ABORT_STACK_SIZE : 512;",
        "_SUPERVISOR_STACK_SIZE = DEFINED(_SUPERVISOR_STACK_SIZE) ? _SUPERVISOR_STACK_SIZE : 2048;":
            "_SUPERVISOR_STACK_SIZE = DEFINED(_SUPERVISOR_STACK_SIZE) ? _SUPERVISOR_STACK_SIZE : 1024;",
        "_IRQ_STACK_SIZE = DEFINED(_IRQ_STACK_SIZE) ? _IRQ_STACK_SIZE : 1024;":
            "_IRQ_STACK_SIZE = DEFINED(_IRQ_STACK_SIZE) ? _IRQ_STACK_SIZE : 512;",
        "_FIQ_STACK_SIZE = DEFINED(_FIQ_STACK_SIZE) ? _FIQ_STACK_SIZE : 1024;":
            "_FIQ_STACK_SIZE = DEFINED(_FIQ_STACK_SIZE) ? _FIQ_STACK_SIZE : 512;",
        "_UNDEF_STACK_SIZE = DEFINED(_UNDEF_STACK_SIZE) ? _UNDEF_STACK_SIZE : 1024;":
            "_UNDEF_STACK_SIZE = DEFINED(_UNDEF_STACK_SIZE) ? _UNDEF_STACK_SIZE : 512;",
    }
    for old, new in replacements.items():
        if old in text:
            text = text.replace(old, new, 1)
        elif new not in text:
            raise RuntimeError(f"Expected text not found in {path}: {old!r}")

    old_memory = "\tcips_0_pspmc_0_psv_ocm_ram_0_memory_0 : ORIGIN = 0xfffc0000, LENGTH = 0x40000\n}"
    new_memory = (
        "\tcips_0_pspmc_0_psv_ocm_ram_0_memory_0 : ORIGIN = 0xfffc0000, LENGTH = 0x40000\n"
        "\tpsv_ddr_MEM_0 : ORIGIN = 0x00100000, LENGTH = 0x3FF00000\n}"
    )
    if old_memory in text:
        text = text.replace(old_memory, new_memory, 1)
    elif "psv_ddr_MEM_0 : ORIGIN = 0x00100000" not in text:
        raise RuntimeError(f"Expected OCM memory block not found in {path}")

    old_sections = "} > cips_0_pspmc_0_psv_ocm_ram_0_memory_0\n\n_SDA_BASE_ = __sdata_start"
    new_sections = (
        "} > cips_0_pspmc_0_psv_ocm_ram_0_memory_0\n\n"
        ".ddr_bss (NOLOAD) : {\n"
        "   . = ALIGN(64);\n"
        "   __ddr_bss_start = .;\n"
        "   *(.ddr_bss)\n"
        "   *(.ddr_bss.*)\n"
        "   . = ALIGN(64);\n"
        "   __ddr_bss_end = .;\n"
        "} > psv_ddr_MEM_0\n\n"
        ".ddr_heap (NOLOAD) : {\n"
        "   . = ALIGN(64);\n"
        "   __ddr_heap_start = .;\n"
        "   *(.ddr_heap)\n"
        "   *(.ddr_heap.*)\n"
        "   . = ALIGN(64);\n"
        "   __ddr_heap_end = .;\n"
        "} > psv_ddr_MEM_0\n\n"
        "_SDA_BASE_ = __sdata_start"
    )
    if old_sections in text:
        text = text.replace(old_sections, new_sections, 1)
    elif ".ddr_bss (NOLOAD)" not in text:
        raise RuntimeError(f"Expected SDA insertion point not found in {path}")

    text = text.replace(
        "} > psv_ddr_MEM_0\n\n.ddr_bss (NOLOAD) : {",
        "} > cips_0_pspmc_0_psv_ocm_ram_0_memory_0\n\n.ddr_bss (NOLOAD) : {",
        1,
    )

    path.write_text(text)


def patch_generated_app(app_dir):
    app_src = app_dir / "src"
    patch_user_config(app_src)
    patch_linker_script(app_src)


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
        if not app_dir.exists():
            client.create_app_component(
                name=args.app,
                platform=str(platform),
                domain=args.domain,
                template="empty_application",
            )
        patch_generated_app(app_dir)
        print(f"Prepared app component: {app_dir}")
    finally:
        vitis.dispose()


if __name__ == "__main__":
    main()
