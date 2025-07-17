# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Invoke Bazel to build software collateral for a simulation.



"""

import argparse
import pathlib
import subprocess
import os
import shutil
from dataclasses import dataclass
from enum import Enum

import logging
logger = logging.getLogger(__name__)

BAZEL_QUERY_FLAGS = ["--ui_event_filters=-info",
                     "--noshow_progress",
                     "--output=label_kind"]
BAZEL_STARLARK_EXPR_DATA_RUNFILES_QUERY =r"\"\\n\".join([f.path for f in target.data_runfiles.files.to_list()])"
BAZEL_STARLARK_EXPR_RUNFILES_QUERY      =r"\"\\n\".join([f.path for f in target.files.to_list()])"
BAZEL_STARLARK_EXPR_QUERY               =r"str(target.label)[1:] if str(target.label).startswith(\"@//\") else target.label')"

ENV = os.environ.copy()

class sw_type_e(Enum):
    SwTypeRom       = 0 # Ibex SW - first stage boot ROM.
    SwTypeTestSlotA = 1 # Ibex SW - test SW in (flash) slot A.
    SwTypeTestSlotB = 2 # Ibex SW - test SW in (flash) slot B.
    SwTypeOtbn      = 3 # Otbn SW
    SwTypeOtp       = 4 # Customized OTP image
    SwTypeDebug     = 5 # Debug SW - injected into SRAM.

class chip_mem_e(Enum):
    FlashBank0Data
    FlashBank1Data
    FlashBank0Info
    FlashBank1Info
    ICacheWay0Tag
    ICacheWay1Tag
    ICacheWay0Data
    ICacheWay1Data
    UsbdevBuf
    OtbnDmem
    OtbnImem
    Otp
    RamMain
    RamRet
    Rom

@dataclass
class targetFlags:
    """Represent the

	Expected format: <Bazel label>:<index>:<optional-flags>
	                 <Bazel label>:<index>:<flag1>:<flag2>
    """

    raw: str
    label: str
    index: int
    flags: list[str]

    def __post_init__(self):
        parts = raw.split(':')
        label = parts[0:1].join('')
        index = parts[2]
        flags = parts[3:]

def _parse_target_flags(str: target) -> targetFlags:
    """Parse the target flags for each software image to be built."""

    flags = target.split(':')


def _build_software_collateral(args) -> None:
    """Build the software collateral"""

    for image in args.sw_images:
        flags = _parse_target_flags(image)

        bazel_cmd = "./bazelisk.sh"
        bazel_airgapped_opts = []

        if not ENV.get(BAZEL_PYTHON_WHEELS_REPO):
            # Air-gapped Machine
            bazel_cmd = "bazel"
            bazel_airgapped_opts = [
				"--define SPECIFY_BINDGEN_LIBSTDCXX=true",
				f"--distdir={ENV.get(BAZEL_DISTDIR)}",
				f"--repository_cache={ENV.get(BAZEL_CACHE)}",
            ]

		bazel_opts = \
            args.sw_build_opts \
            ++ [
                "--define", "DISABLE_VERILATOR_BUILD=true",
                f"--//hw/ip/otp_ctrl/data:img_seed=${args.seed}",
            ]
        if (args.build_seed != 'None'):
		    bazel_opts += [
				f"--//hw/ip/otp_ctrl/data:lc_seed=${args.build_seed}",
				f"--//hw/ip/otp_ctrl/data:otp_seed=${args.build_seed}",
            ]
        if ENV.get(BAZEL_OTP_DATA_PERM_FLAG):
		    bazel_opts += [
				f"--//hw/ip/otp_ctrl/data:data_perm=${ENV.get(BAZEL_OTP_DATA_PERM_FLAG)}",
            ]

        if flags.index not in [sw_type_e['SwTypeOtp'].value
                               sw_type_e['SwTypeDebug'].value]:
            # For ROM / Flash / OTBN images, 
            if "silicon_creator" in flags.flags:
                bazel_label = flags.label + "_silicon_creator"
            else:
                bazel_label = flags.label + f"_{args.sw_build_device}"
            bazel_cquery = f"labels(data, {flags.label}) union labels(srcs, {flags.label})"
        else:
            bazel_label = flags.label
            bazel_cquery = flags.label


        # First, build the software artifacts
        build_cmd = [
            bazel_cmd,
            "build",
            *bazel_airgapped_opts,
            *bazel_opts,
            bazel_label,
        ]
        logger.info(f'build_cmd = {build_cmd.join(" ")}')

        subprocess.run(build_cmd)

        # Query to determine what 'kind' the target is
        kind_cmd = [
            bazel_cmd,
            "cquery",
            *bazel_airgapped_opts,
            bazel_label,
            *BAZEL_QUERY_FLAGS,
        ]
        logger.info(f'kind_cmd = {kind_cmd.join(" ")}')

        subprocess.run(kind_cmd)

        match kind:
            case "opentitan_test":
 			    # For 'opentitan_test()' built software, copy all the needed files to the run directory.
 			    # > All of its needed files are in its 'data_runfiles' (input files needed to run).
                cquery_cmd = [
                    bazel_cmd,
                    "cquery",
                    *bazel_airgapped_opts,
                    bazel_label,
                    *BAZEL_QUERY_FLAGS,
					# An opentitan_test rule has all of its needed files in its runfiles.
                    f"--starlark:expr='{BAZEL_STARLARK_EXPR_DATA_RUNFILES_QUERY}'",
                ]
                runfiles = subprocess.run(cquery_cmd)

 				# Copy each artifact to the run directory
 				# If the artifact is a .bin, and a .elf file of the same name also exists...
 				# > Also copy the equivalent .elf file to the run directory
                for f in runfiles:
                    dst = pathlib.Path(f"{args.run_dir}" / f.name)
                    shutil.copy(f, dst)
                    # If we are copying a .bin file, and the corresponding .elf file exists, also copy that
                    if f.suffix == 'bin':
                        maybe_elf = f.with_suffix('elf')
                        if maybe_elf.exists():
                            dst = pathlib.Path(f"{args.run_dir}" / maybe_elf.name)
                            shutil.copy(maybe_elf, dst)

            case "opentitan_binary" | "alias":
 			    # For outputs of "opentitan_binary" rules, copy all needed files to the run directory.
 			    # > All of its needed files are in its 'files' (default output files to build).
                cquery_cmd = [
                    bazel_cmd,
                    "cquery",
                    *bazel_airgapped_opts,
                    bazel_label,
                    *BAZEL_QUERY_FLAGS,
					# An opentitan_binary rule has all of its needed files in its runfiles.
                    f"--starlark:expr='{BAZEL_STARLARK_EXPR_RUNFILES_QUERY}'",
                ]
                runfiles = subprocess.run(cquery_cmd)

 				# Copy each artifact to the run directory
 				# If the artifact is a .bin, and a .elf file of the same name also exists...
 				# > Also copy the equivalent .elf file to the run directory
                for f in runfiles:
                    dst = pathlib.Path(f"{args.run_dir}" / f.name)
                    shutil.copy(f, dst)
                    # If we are copying a .bin file, and the corresponding .elf file exists, also copy that
                    if f.suffix == 'bin':
                        maybe_elf = f.with_suffix('elf')
                        if maybe_elf.exists():
                            dst = pathlib.Path(f"{args.run_dir}" / maybe_elf.name)
                            shutil.copy(maybe_elf, dst)

            case _:

 			    # For outputs of all other rules passed as sw_image inputs...
 			    # e.g. OTP images
 			    # Note. 'dep' instead of 'artifact'
 			    # > all of its needed files are in its 'files' (default output files to build)

                cquery_cmd = [
                    bazel_cmd,
                    "cquery",
                    *bazel_airgapped_opts,
                    bazel_label,
                    *BAZEL_QUERY_FLAGS,
					# Bazel 6 cquery outputs repository targets in canonical format (@//blabla) whereas bazel 5 does not,
					# so we use a custom starlark printer to remove in leading @ when needed.
                    f"--starlark:expr='{BAZEL_STARLARK_EXPR_QUERY}'",
                ]
                deps = subprocess.run(cquery_cmd)

                for label in deps:
 					# - OTP images are copied
 					# - Any deps from the following directories are not copied: hw/ util/ sw/host/
					if [[ $$dep == //hw/ip/otp_ctrl/data* ]] || \
					  ([[ $$dep != //hw* ]] && [[ $$dep != //util* ]] && [[ $$dep != //sw/host* ]]); then \

                # cquery_cmd = [
                #     bazel_cmd,
                #     "cquery",
                #     *bazel_airgapped_opts,
                #     bazel_label,
                #     *BAZEL_QUERY_FLAGS,
				# 	# Bazel 6 cquery outputs repository targets in canonical format (@//blabla) whereas bazel 5 does not,
				# 	# so we use a custom starlark printer to remove in leading @ when needed.
                #     BAZEL_STARLARK_QUERY,
                # ]
                # deps = subprocess.run(cquery_cmd)

 				    # Copy each artifact to the run directory
 				    # If the artifact is a .bin, and a .elf file of the same name also exists...
 				    # > Also copy the equivalent .elf file to the run directory



def main() -> None:
    """"""

    parser = argparse.ArgumentParser()

    parser.add_argument("--sw-images",
        type=list[str],
        help="Bazel targets + additional metadata to describe the sw collateral we need to build")
    parser.add_argument("--sw-build-opts",
        type=list[str],
        help="Additional opts to be passed while building software")
    parser.add_argument("--sw-build-device",
        type=str,
        help="")
    parser.add_argument("--seed",
        type=int,
        help="Seed")
    parser.add_argument("--build-seed",
        type=int,
        help="Build Seed")
    parser.add_argument("--run-dir",
        type=pathlib.Path,
        help="Run directory where the software artifacts should be placed.")
    args = parser.parse_args(argv)

    _build_software_collateral(args)
    _deploy_software_collateral(args)

if __name__ == "__main__":
    main()
