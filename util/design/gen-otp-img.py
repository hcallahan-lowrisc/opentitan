#!/usr/bin/env python3
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Generate OTP memory images and SW collateral suitable for simulation and emulation.


"""
import argparse
import logging as log
import random
import sys
from pathlib import Path

import hjson

from lib.common import vmem_permutation_string, wrapped_docstring, create_outfile_header
from lib.OtpMemImg import OtpMemImg

# Make sure the script can also be called from other dirs than
# just the project root by adapting the default paths accordingly.
PROJ_ROOT = Path(__file__).parents[2]

# Default values for input configuration files
# All can be overridden on the command line

# OTP memory map.
MMAP_DEFINITION_FILE = PROJ_ROOT / Path('hw/ip/otp_ctrl/data/otp_ctrl_mmap.hjson')
# Life cycle state and ECC poly definitions.
LC_STATE_DEFINITION_FILE = PROJ_ROOT / Path('hw/ip/lc_ctrl/data/lc_ctrl_state.hjson')
# Image file.
IMAGE_DEFINITION_FILE = PROJ_ROOT / Path('hw/ip/otp_ctrl/data/otp_ctrl_img_dev.hjson')

# Default output MEMfile name (can be overridden on the command line).
# Note that "BITWIDTH" will be replaced with the architecture's bitness.
MEMORY_MEM_FILE = 'otp-img.BITWIDTH.vmem'


def _resolve_seed(args, seed_name: str, config: dict) -> None:
    """Resolve the final seed to be used to seed the RNG for this config object.

    The following priorities are used:
    1) Commandline override (via --{}-seed)
    2) Existing value of config['seed'] in the config dictionary
    3) Generate a new random value

    A commandline override seed value of 0 is equivalent to the commandline
    override option (--{}-seed) being absent.
    This behaviour is intentional to simplify higher level scripts.
    (The OTP-generation Bazel rule sets the default seed values to 0).
    """

    arg_seed = getattr(args, seed_name, None)
    config_seed = getattr(config, 'seed', None)

    if arg_seed:
        config['seed'] = arg_seed
        log.warning(f"Seed '{seed_name}' set by commandline override.")

    elif config_seed or (config_seed == 0):
        log.info(f"Using '{seed_name}' value from config object.")

    else:
        config['seed'] = random.getrandbits(256)
        log.warning(f"Seed '{seed_name}' not resolved, generated new seed from RNG.")

    log.info(f"Seed '{seed_name}' = {config['seed']}")


def main():
    parser = argparse.ArgumentParser(
        prog="gen-otp-img",
        description=wrapped_docstring(),
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--quiet',
                        '-q',
                        action='store_true',
                        help=""""Don't print out progress messages.""")
    parser.add_argument('--stamp',
                        action='store_true',
                        help="""
                        Add a comment 'Generated on [Date] with [Command]' to
                        generated output files.
                        """)
    parser.add_argument('--seed',
                        type=int,
                        metavar='<seed>',
                        help="Custom seed used for randomization.")
    parser.add_argument('--img-seed',
                        type=int,
                        metavar='<seed>',
                        help="""
                        Custom seed for RNG to compute randomized items in OTP image.

                        Can be used to override the seed value specified in the image
                        config Hjson.
                        """)
    parser.add_argument('--lc-seed',
                        type=int,
                        metavar='<seed>',
                        help="""
                        Custom seed for RNG to compute randomized life cycle netlist constants.

                        Note that this seed must coincide with the seed used for generating
                        the LC state encoding (gen-lc-state-enc.py).

                        This value typically does not need to be specified as it is taken from
                        the LC state encoding definition Hjson.
                        """)
    parser.add_argument('--otp-seed',
                        type=int,
                        metavar='<seed>',
                        help="""
                        Custom seed for RNG to compute randomized OTP netlist constants.

                        Note that this seed must coincide with the seed used for generating
                        the OTP memory map (gen-otp-mmap.py).

                        This value typically does not need to be specified as it is taken from
                        the OTP memory map definition Hjson.
                        """)
    parser.add_argument('-o',
                        '--out',
                        type=str,
                        metavar='<path>',
                        default=MEMORY_MEM_FILE,
                        help=f"""
                        Custom output path for generated MEM file.
                        Defaults to {MEMORY_MEM_FILE}
                        """.format())
    parser.add_argument('--lc-state-def',
                        type=Path,
                        metavar='<path>',
                        default=LC_STATE_DEFINITION_FILE,
                        help="""
                        Life cycle state definition file in Hjson format.
                        """)
    parser.add_argument('--mmap-def',
                        type=Path,
                        metavar='<path>',
                        default=MMAP_DEFINITION_FILE,
                        help=f"""
                        OTP memory map file in Hjson format.
                        Defaults to {MMAP_DEFINITION_FILE}
                        """)
    parser.add_argument('--img-cfg',
                        type=Path,
                        metavar='<path>',
                        default=IMAGE_DEFINITION_FILE,
                        help=f"""
                        Image configuration file in Hjson format.
                        Defaults to {IMAGE_DEFINITION_FILE}
                        """)
    parser.add_argument('--add-cfg',
                        type=Path,
                        metavar='<path>',
                        action='extend',
                        nargs='+',
                        default=[],
                        help="""
                        Additional image configuration file in Hjson format.

                        This switch can be specified multiple times.
                        Image configuration files are parsed in the same
                        order as they are specified on the command line,
                        and partition item values that are specified multiple
                        times are overridden in that order.

                        Note that seed values in additional configuration files
                        are ignored.
                        """)
    parser.add_argument('--data-perm',
                        type=vmem_permutation_string,
                        metavar='<map>',
                        default='',
                        help="""
                        This is a post-processing option and allows permuting
                        the bit positions before writing the memfile.
                        The bit mapping needs to be supplied as a comma separated list
                        of bit slices, where the numbers refer to the bit positions in
                        the original data word before remapping, for example:

                        "[7:0],[15:8]".

                        The mapping must be bijective - otherwise this will generate
                        an error.
                        """)
    parser.add_argument('--c-template',
                        type=Path,
                        metavar='<path>',
                        help="""
                        Template file used to generate C version of the OTP image.
                        This flag is only required when --c-out is set.
                        """)
    parser.add_argument('--c-out',
                        type=Path,
                        metavar='<path>',
                        help="""
                        C output path. Requires the --c-template flag to be
                        set. The --out flag is ignored when this flag is set.
                        """)

    #############################
    # PARSE AND VALIDATE INPUTS #
    #############################

    args = parser.parse_args()

    log_level = log.DEBUG
    log_format = '%(levelname)s: [%(filename)s:%(lineno)d] %(message)s'
    log.basicConfig(level=log_level,
                    format=log_format,
                    handlers=[
                        # log.FileHandler("gen-otp-img.log"),
                         log.StreamHandler()
                    ])
    # if args.quiet:
    #     log.getLogger().setLevel(log.WARNING)

    log.info(f"Loading LC state definition file : {args.lc_state_def}")
    lc_state_cfg = hjson.loads(args.lc_state_def.read_text(encoding="UTF-8"))

    log.info(f"Loading OTP memory map definition file : {args.mmap_def}")
    otp_mmap_cfg = hjson.loads(args.mmap_def.read_text(encoding="UTF-8"))

    log.info(f"Loading main image configuration file : {args.img_cfg}")
    img_cfg = hjson.loads(args.img_cfg.read_text(encoding="UTF-8"))

    # Set the initial random seed so that the generated image is
    # deterministically randomized.
    random.seed(args.seed)

    # Resolve the final value used for each RNG seed.
    _resolve_seed(args, 'lc_seed', lc_state_cfg)
    _resolve_seed(args, 'otp_seed', otp_mmap_cfg)
    _resolve_seed(args, 'img_seed', img_cfg)

    try:
        # Construct the base OtpMemImg object, initialized with the follow
        # config objects
        # - Lifecycle State Encodings
        # - OTP Memory Map
        # - An initial OTP Image
        otp_mem_img = OtpMemImg(
            lc_state_cfg, otp_mmap_cfg, img_cfg, args.data_perm)

        # Add additional configuration values to the OTP Image in the form
        # of overlay files
        for f in args.add_cfg:
            cfg = hjson.loads(f.read_text())
            log.info('')
            log.info(f"Loading additive image configuration file '{f}'")
            log.info('')
            otp_mem_img.apply_override_img_config(cfg)

        # After base image + overrides are applied, generate all the random
        # constants for fields which still take a value of '<random>'
        otp_mem_img.gen_random_constants()

    except RuntimeError as err:
        log.error(err)
        exit(1)

    # Print all defined args into header comment for reference
    argstr = ''
    for arg, argval in sorted(vars(args).items()):
        if argval:
            if not isinstance(argval, list):
                argval = [argval]
            for a in argval:
                argname = '-'.join(arg.split('_'))
                # Get absolute paths for all files specified.
                a = a.resolve() if isinstance(a, Path) else a
                argstr += ' \\\n//   --' + argname + ' ' + str(a) + ''

    file_header = '//\n'
    if args.stamp:
        dt = datetime.datetime.now(datetime.timezone.utc)
        dtstr = dt.strftime("%a, %d %b %Y %H:%M:%S %Z")
        file_header = '// Generated on {} with\n// $ gen-otp-img.py {}\n//\n'.format(
            dtstr, argstr)

    ####################
    # GENERATE OUTPUTS #
    ####################

    # (Optionally) generate a C header file from an input template
    if args.c_out:
        log.info(f'Generating C file: {args.c_out}')
        file_body = otp_mem_img.generate_c_file(
            fileheader=create_outfile_header(sys.argv[0], args),
            templatefile=args.c_template)
        args.c_out.write_bytes(file_body.encode('utf-8'))
        # Return early (The --out flag is ignored if --c-out is given)
        exit(0)

    # Determine the memfile filename
    # Add the bitness into the output file name in place of the placeholder 'BITWIDTH'
    # - If the out argument does not contain "BITWIDTH", it will not be changed.
    bitness = otp_mem_img.lc_state.config['secded']['bitness']
    memfile_path = Path(args.out.replace('BITWIDTH', str(bitness)))

    # Generated the memfile contents, and write it to disk
    # Use binary mode and a large buffer size to improve performance.
    with open(memfile_path, 'wb', buffering=2097152) as outfile:
        outfile.write(create_outfile_header(sys.argv[0], args).encode('utf-8'))
        outfile.write(otp_mem_img.gen_memfile().encode('utf-8'))


if __name__ == "__main__":
    main()
