# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Invoke Bazel to build software collateral for a simulation.

Loop through the list of sw_images and invoke Bazel on each.
`sw_images` is a space-separated list of tests to be built into an image.
Optionally, each item in the list can have additional metadata / flags using
the delimiter ':'. The format is as follows:
<label>:<index>:<flag1>:<flag2>

If one delimiter is detected, then the full string is considered to be the
<label>. If two delimiters are detected, then it must be <label>
followed by <index>. All trailing <flag> parts are optional.

After the images are built, we use `bazel cquery` to locate the built
software artifacts so they can be copied to the test bench run directory.
We only copy device SW images, and do not copy host-side artifacts (like
opentitantool) that are also dependencies of the Bazel test target that
encode the software image targets.
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

	Expected format: <label>:<index>:<optional-flags>
	                 <label>:<index>:<flag1>:<flag2>
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

def _copy_files_to_run_dir(files: list[str], args) -> None:
    """Copy all artifacts to the run directory.

 	If the artifact is a .bin, and a .elf file of the same name also exists,
 	also copy the equivalent .elf file.
    """

    for f in files:
        dst = pathlib.Path(f"{args.run_dir}" / f.name)
        shutil.copy(f, dst)
        # If we are copying a .bin file, and the corresponding .elf file exists, also copy that
        if f.suffix == 'bin':
            maybe_elf = f.with_suffix('elf')
            if maybe_elf.exists():
                dst = pathlib.Path(f"{args.run_dir}" / maybe_elf.name)
                shutil.copy(maybe_elf, dst)


def _deploy_software_collateral(args) -> None:
    """Build, then deploy the software collateral"""

    for image in args.sw_images:
        flags = targetFlags(image)

        bazel_cmd = "./bazelisk.sh"
        bazel_airgapped_opts = []

        if not ENV.get(BAZEL_PYTHON_WHEELS_REPO):
            # Air-gapped Machine
            bazel_cmd = "bazel"
            bazel_airgapped_opts = [
				"--define", "SPECIFY_BINDGEN_LIBSTDCXX=true",
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
                bazel_label = f"{flags.label}_silicon_creator"
            else:
                bazel_label = f"{flags.label}_{args.sw_build_device}"
            bazel_cquery = f"labels(data, {flags.label}) union labels(srcs, {flags.label})"
        else:
            bazel_label = flags.label
            bazel_cquery = flags.label

        logger.debug(f"sw_image={sw_image}")
        logger.debug(f"bazel_cmd={bazel_cmd}")
        logger.debug(f"bazel_opts={bazel_opts}")
        logger.debug(f"bazel_airgapped_opts={bazel_airgapped_opts}")
        logger.debug(f"bazel_cquery={bazel_cquery}")

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
                logger.info(f'cquery_cmd = {cquery_cmd.join(" ")}')
                runfiles = subprocess.run(cquery_cmd)

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
                logger.info(f'cquery_cmd = {cquery_cmd.join(" ")}')
                runfiles = subprocess.run(cquery_cmd)

            case _:

 			    # For outputs of all other rules passed as sw_image inputs...
 			    # e.g. OTP images
 			    # Note. 'dep' instead of 'artifact'
 			    # > all of its needed files are in its 'files' (default output files to build)

                cquery_cmd = [
                    bazel_cmd,
                    "cquery",
                    *bazel_airgapped_opts,
                    bazel_cquery,
                    *BAZEL_QUERY_FLAGS,
					# Bazel 6 cquery outputs repository targets in canonical format (@//blabla) whereas bazel 5 does not,
					# so we use a custom starlark printer to remove in leading @ when needed.
                    f"--starlark:expr='{BAZEL_STARLARK_EXPR_QUERY}'",
                ]
                logger.info(f'cquery_cmd = {cquery_cmd.join(" ")}')
                deps = subprocess.run(cquery_cmd)

                for label in deps:
 					# - OTP images are copied
 					# - Any deps from the following directories are _not_ copied: hw/ util/ sw/host/
					if (any(substring in label for substring in ['//hw/ip/otp_ctrl/data']) or
                        (not any(substring in label for substring in ["//hw" "//util" "//sw/host"]))):

                        cquery_cmd = [
                            bazel_cmd,
                            "cquery",
                            *bazel_airgapped_opts,
                            label,
                            *BAZEL_QUERY_FLAGS,
					        # These rules have all needed files in its runfiles.
                            f"--starlark:expr='{BAZEL_STARLARK_EXPR_RUNFILES_QUERY}'",
                        ]
                        logger.info(f'cquery_cmd = {cquery_cmd.join(" ")}')
                        runfiles = subprocess.run(cquery_cmd)

        # We have built and queried to determine all the needed software collateral for the simulation
        # The final step is to copy it to the test's working directory so it can be accessed via relative path.
        _copy_files_to_run_dir(runfiles, args)


def main() -> None:
    """"""
    parser = argparse.ArgumentParser()
    parser.add_argument("--sw-images",
        type=list[str],
        help="Bazel label + additional metadata to describe the needed sw collateral")
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

    log_level = logging.DEBUG
    logger.basicConfig(level=log_level)

    _deploy_software_collateral(args)

if __name__ == "__main__":
    main()
