#!/usr/bin/env python3
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
r"""Post-process a (raw) Flash .vmem image for backdoor-loading in simulation.

To mimic the transforms applied by the OpenTitan Flash Controller on write,
hence allowing the Controller to successfully read back data that has been
inserted directly in the memory array, the following processing steps may be required:
- adds both layers of ECC (integrity and reliablity)
- (optionally) scrambles the data using the Flash_CTRL XEX scrambling scheme

For the Flash scrambling to be applied, an OTP mmap .hjson file and an OTP
.vmem image file must be provided.

For programs running in place of a production ROM_EXT, they must be scrambled
according to the Flash Scrambing enablement setting in the OTP parition and
field CREATOR_SW_CFG::FLASH_DATA_DEFAULT_CFG. Otherwise, the jump at the end
of ROM execution will not be able to successfully read the pre-loaded ROM_EXT
image from Flash.
An OTP .vmem image can be provided from which the state of Flash Scrambling
enablement in FLASH_DATA_DEFAULT_CFG is extracted. To descramble this OTP .vmem
image, an OTP mmap .hjson file must be provided, along with the matching seed
value used for Netlist Constant generation. From this information, a scrambled
Flash .vmem image can be generated which is able to be descrambled by an
OpenTitan system synthesized with the given OTP mmap configuration + seed.

The generated images are suitable for backdoor-loading of Flash models on
simulation platforms (e.g., DV and Verilator).
"""

import argparse
import logging as log
import re
import sys
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import List, Optional
from functools import partial

import hjson
from pyfinite import ffield
from util.design.lib.common import (inverse_permute_bits,
                                    validate_data_perm_option,
                                    vmem_permutation_string,
                                    create_outfile_header)
from util.design.lib.OtpMemMap import OtpMemMap
from util.design.lib.Present import Present

import prince
import secded_gen

MUBI4_TRUE = 0x6

# Fixed OTP data / scrambling parameters.
OTP_WORD_SIZE = 16  # bits
OTP_WORD_SIZE_WECC = 24  # bits
OTP_FLASH_DATA_DEFAULT_CFG_RE = re.compile(
    r"CREATOR_SW_CFG: CREATOR_SW_CFG_FLASH_DATA_DEFAULT_CFG")
OTP_FLASH_DATA_DEFAULT_CFG_BLOCK_SIZE = 32  # bits
OTP_SECRET1_RE = re.compile(r"SECRET1")
OTP_SECRET1_BLOCK_SIZE = 64  # bits
OTP_SECRET1_PRESENT_KEY_LENGTH = 128  # bits
OTP_SECRET1_PRESENT_NUM_ROUNDS = 32
OTP_FLASH_ADDR_KEY_SEED_SIZE = 256  # bits
OTP_FLASH_DATA_KEY_SEED_SIZE = 256  # bits

# Flash data / scrambling parameters.
FLASH_ADDR_KEY_SIZE = 128  # bits
FLASH_DATA_KEY_SIZE = 128  # bits
FLASH_WORD_SIZE = 64  # bits
FLASH_ADDR_SIZE = 16  # bits
FLASH_INTEGRITY_ECC_SIZE = 4  # bits
FLASH_RELIABILITY_ECC_SIZE = 8  # bits
FLASH_PRINCE_NUM_HALF_ROUNDS = 5


class FlashScramblingKeyType(Enum):
    ADDRESS = 1
    DATA = 2

# Flash scrambling key computation parameters.
# ------------------------------------------------------------------------------
# DO NOT EDIT: edit fixed parameters above instead.
# ------------------------------------------------------------------------------
# Computed OTP data / scrambling parameters.
# The SECRET1 partition layout looks like:
#   [
#    FLASH_ADDR_KEY_SEED,
#    FLASH_DATA_KEY_SEED,
#    SRAM_DATA_KEY_SEED,
#    DIGEST
#   ]
OTP_SECRET1_FLASH_ADDR_KEY_SEED_START = 0
OTP_SECRET1_FLASH_ADDR_KEY_SEED_STOP = OTP_SECRET1_FLASH_ADDR_KEY_SEED_START + \
                                       (OTP_FLASH_ADDR_KEY_SEED_SIZE //
                                        OTP_SECRET1_BLOCK_SIZE)
OTP_SECRET1_FLASH_DATA_KEY_SEED_START = (OTP_FLASH_ADDR_KEY_SEED_SIZE //
                                         OTP_SECRET1_BLOCK_SIZE)
OTP_SECRET1_FLASH_DATA_KEY_SEED_STOP = OTP_SECRET1_FLASH_DATA_KEY_SEED_START + \
                                       (OTP_FLASH_DATA_KEY_SEED_SIZE //
                                        OTP_SECRET1_BLOCK_SIZE)

# Computed flash data / scrambling parameters.
FLASH_KEY_DERIVATION_KEY_SIZE = OTP_FLASH_ADDR_KEY_SEED_SIZE // 2
FLASH_KEY_DERIVATION_KEY_MASK = (2**FLASH_KEY_DERIVATION_KEY_SIZE) - 1
FLASH_GF_OPERAND_B_MASK = (2**FLASH_WORD_SIZE) - 1
FLASH_GF_OPERAND_A_MASK = (
    FLASH_GF_OPERAND_B_MASK &
    ~(0xffff << (FLASH_WORD_SIZE - FLASH_ADDR_SIZE))) << FLASH_WORD_SIZE
# Create GF(2^64) with irreducible_polynomial = x^64 + x^4 + x^3 + x + 1
FLASH_GF_2_64 = ffield.FField(64,
                              gen=((0x1 << 64) | (0x1 << 4) | (0x1 << 3) |
                                   (0x1 << 1) | 0x1))

# Format string for generating new .vmem file.
FLASH_VMEM_WORD_SIZE = (FLASH_WORD_SIZE + FLASH_INTEGRITY_ECC_SIZE +
                        FLASH_RELIABILITY_ECC_SIZE)
VMEM_FORMAT_STR = " {:0" + f"{FLASH_VMEM_WORD_SIZE // 4}" + "X}"
# ------------------------------------------------------------------------------


@dataclass
class FlashScramblingConfigs:

    # OTP mmap netlist constants
    otp_secret1_scrambling_key: int = None
    addr_key_iv: int = None
    data_key_iv: int = None
    addr_key_final_const: int = None
    data_key_final_const: int = None
    # Provisioned / Pre-loaded state of Flash scrambling enablement in FLASH_DATA_DEFAULT_CFG
    scrambling_enabled: bool = False
    # Provisioned / Pre-loaded Flash scrambling key seeds in SECRET1 partition
    addr_key_seed: int = None
    data_key_seed: int = None
    # Derived Flash scrambling keys (after applying the same transform as the hw OTP KDF)
    addr_key: int = None
    data_key: int = None

    def get_key_seed(self, key_type: FlashScramblingKeyType):
        if key_type == FlashScramblingKeyType.ADDRESS:
            return self.addr_key_seed
        else:
            return self.data_key_seed

    def get_iv(self, key_type: FlashScramblingKeyType):
        if key_type == FlashScramblingKeyType.ADDRESS:
            return self.addr_key_iv
        else:
            return self.data_key_iv

    def get_final_cnst(self, key_type: FlashScramblingKeyType):
        if key_type == FlashScramblingKeyType.ADDRESS:
            return self.addr_key_final_const
        else:
            return self.data_key_final_const


def _xex_scramble(data: int,
                  word_addr: int,
                  flash_addr_key: int,
                  flash_data_key: int) -> int:
    """Perform a XEX scramble matching the flash_ctrl implementation.

    The PRINCE block cipher is used for encryption.
    """

    # Determine the tweak from the 'flash_addr_key' and the word address
    operand_a = ((flash_addr_key & FLASH_GF_OPERAND_A_MASK) >>
                 (FLASH_WORD_SIZE - FLASH_ADDR_SIZE)) | word_addr
    operand_b = flash_addr_key & FLASH_GF_OPERAND_B_MASK
    tweak = FLASH_GF_2_64.Multiply(operand_a, operand_b)

    # Apply the XEX, where 'E' uses the PRINCE cipher with the key 'flash_data_key'
    x = data ^ tweak
    xe = prince.prince(x, flash_data_key, FLASH_PRINCE_NUM_HALF_ROUNDS)
    xex = xe ^ tweak

    return xex


def _convert_array_2_int(data_array: List[int],
                         data_size: int) -> int:
    """Converts array of data blocks to an int."""

    reformatted_data = 0
    for i, data in enumerate(data_array):
        reformatted_data |= (data << (i * data_size))
    return reformatted_data


def _get_otp_ctrl_netlist_consts(otp_mmap_file: str, otp_seed: Optional[int],
                                 scrambling_configs: FlashScramblingConfigs) -> None:
    """Parse the OTP mmap .hjson file to generate and extract the needed netlist constants.

    These are:
    - SECRET1 Scrambling Key (To unscramble the SECRET1 partition from a OTP .vmem image)
    - Flash Address + Data Scrambling (IV and Cnst_Value)

    If the 'otp_seed' arg is provided, this value will be used to seed the randomization
    process for generating the netlist constants from the mmap.
    This will override any default 'seed' value inside the mmap file config.
    """

    # Read in the OTP memory map file to a dictionary.
    with open(otp_mmap_file, 'r') as infile:
        otp_mmap_config = hjson.load(infile)
        # If a OTP memory map seed is provided, we use it.
        if otp_seed is not None:
            otp_mmap_config["seed"] = otp_seed
        # Otherwise, we either take it from the .hjson if present, else we
        # error out. If we did not provide a seed via a cmd line arg, and there
        # is not one present in the .hjson, then it won't be in sync with what
        # `gen-otp-mmap.py` generated on the RTL side.
        elif "seed" not in otp_mmap_config:
            log.error("No OTP seed provided.")
        try:
            otp_mmap = OtpMemMap(otp_mmap_config)
            otp_mmap.gen_mmap_random_constants()
        except RuntimeError as err:
            log.error(err)
            exit(1)

    # Extract OTP SECRET1 partition scrambling key.
    for key in otp_mmap.config["scrambling"]["keys"]:
        if key["name"] == "Secret1Key":
            scrambling_configs.otp_secret1_scrambling_key = int(key["value"])

    # Extract OTP flash scrambling key IVs and cnst_values.
    for digest in otp_mmap.config["scrambling"]["digests"]:
        if digest["name"] == "FlashAddrKey":
            scrambling_configs.addr_key_iv = digest["iv_value"]
            scrambling_configs.addr_key_final_const = digest["cnst_value"]
        if digest["name"] == "FlashDataKey":
            scrambling_configs.data_key_iv = digest["iv_value"]
            scrambling_configs.data_key_final_const = digest["cnst_value"]


def _get_flash_scrambling_configs(otp_vmem_file: str,
                                  otp_data_perm: Optional[list],
                                  configs: FlashScramblingConfigs) -> None:
    """Read and parse an OTP .vmem file to extract the Flash scrambling key seeds.

    This requires the SECRET1 Scrambling Key to have already been extracted from the OTP mmap.

    First, the FLASH_DATA_DEFAULT_CFG field from the CREATOR_SW_CFG partition is
    read to determine if flash scrambling is enabled.
    If not, we can return immediately.

    If so, extract the SECRET1 partition, descramble it, and then extract
    the Flash scrambling key seeds.
    """

    # Open OTP .vmem file and read into memory, skipping comment lines.
    try:
        otp_vmem = Path(otp_vmem_file).read_text()
    except IOError:
        raise Exception(f"Unable to open {otp_vmem_file}")
    # Skip all non-comment lines. Trailing comments are okay.
    otp_vmem_lines = re.findall(r"^(?!//).*$", otp_vmem, flags=re.MULTILINE)

    # Retrieve OTP data from the following partitions:
    # - CREATOR_SW_CFG: contains the flash scrambling enablement flag.
    # - SECRET1:        contains the flash scrambling key seeds.
    flash_data_default_cfg = None
    secret1_data_blocks = []

    # Helper variables to accumulate parsed blocks
    otp_data_block = 0
    idx = 0

    # log.info("Here! :)")

    def _extract_words_from_line(line: str):
        if '//' in line:
            line = line.split('//')[0]
        line_items = line.split()
        assert len(line_items) in list(range(1, 3))

        # Convert OTP .vmem word from string to int.
        # N.B. This assumes the data word is the final element on the line.
        otp_data_word_w_ecc = int(line_items[-1], 16)

        # Un-permute bits if necessary.
        if otp_data_perm:
            bin_fmt_str = "0" + str(OTP_WORD_SIZE_WECC) + "b"
            otp_data_word_as_str = format(otp_data_word_w_ecc, bin_fmt_str)
            otp_data_word_w_ecc = \
                int(inverse_permute_bits(otp_data_word_as_str, otp_data_perm), 2)

        # Drop ECC bits.
        otp_data_word = otp_data_word_w_ecc & (2**OTP_WORD_SIZE - 1)

        # Return the data block
        nonlocal otp_data_block
        nonlocal idx
        otp_data_block |= otp_data_word << (idx * OTP_WORD_SIZE)
        idx += 1

    for line in otp_vmem_lines:
        is_flash_data_default_cfg_line = OTP_FLASH_DATA_DEFAULT_CFG_RE.search(line)
        is_secret1_line = OTP_SECRET1_RE.search(line)

        # log.info(f"line: {line}")

        if is_flash_data_default_cfg_line:
            # log.info(f"Got FLASH_DATA_DEFAULT_CFG line: {line}")
            _extract_words_from_line(line)
            if idx == (OTP_FLASH_DATA_DEFAULT_CFG_BLOCK_SIZE //
                       OTP_WORD_SIZE):
                flash_data_default_cfg = otp_data_block & 0xff
                # If flash data scrambling is disabled, then we can return
                # early as fetching the scrambling key seeds won't be required.
                if flash_data_default_cfg != MUBI4_TRUE:
                    configs.scrambling_enabled = False
                    return
                configs.scrambling_enabled = True
                otp_data_block = 0
                idx = 0
        if is_secret1_line:
            # log.info(f"Got SECRET1 line: {line}")
            _extract_words_from_line(line)
            if idx == (OTP_SECRET1_BLOCK_SIZE // OTP_WORD_SIZE):
                secret1_data_blocks.append(otp_data_block)
                otp_data_block = 0
                idx = 0

    # Check we found the data we were looking for in the OTP image.
    if not flash_data_default_cfg:
        raise RuntimeError(
            "Cannot read flash scrambling enablement state from OTP.")
    if not secret1_data_blocks:
        raise RuntimeError(
            "Cannot read flash scrambling key seeds from OTP.")

    # Descramble SECRET1 partition data blocks.
    otp_secret1_present_cipher = Present(configs.otp_secret1_scrambling_key,
                                         rounds=OTP_SECRET1_PRESENT_NUM_ROUNDS,
                                         keylen=OTP_SECRET1_PRESENT_KEY_LENGTH)
    descrambled_secret1_blocks = list(
        map(otp_secret1_present_cipher.decrypt, secret1_data_blocks))

    # Finally extract the flash scrambling key seeds via their precomputed offsets.
    _convert_64b_array_2_int = \
        partial(_convert_array_2_int, data_size=OTP_SECRET1_BLOCK_SIZE)
    configs.addr_key_seed = _convert_64b_array_2_int(
        descrambled_secret1_blocks[OTP_SECRET1_FLASH_ADDR_KEY_SEED_START:
                                   OTP_SECRET1_FLASH_ADDR_KEY_SEED_STOP])
    configs.data_key_seed = _convert_64b_array_2_int(
        descrambled_secret1_blocks[OTP_SECRET1_FLASH_DATA_KEY_SEED_START:
                                   OTP_SECRET1_FLASH_DATA_KEY_SEED_STOP])


def _derive_flash_scrambling_key(scrambling_configs: FlashScramblingConfigs,
                                  key_type: FlashScramblingKeyType) -> int:
    """Perform the Static Scrambling Key Derivation, mirroring the OTP KDF.

    This matches the hardware implementation in the OTP Controller.
    """

    # Netlist Constants
    iv = scrambling_configs.get_iv(key_type)
    final_cnst = scrambling_configs.get_final_cnst(key_type)
    # Provisioned / Pre-loaded key seed from SECRET1
    key_seed = scrambling_configs.get_key_seed(key_type)

    full_key = 0
    for i in range(2):
        round_1_present_key = \
            (key_seed >> (FLASH_KEY_DERIVATION_KEY_SIZE * i)) & \
            FLASH_KEY_DERIVATION_KEY_MASK
        key_half = 0
        for j in range(2):
            if j == 0:
                cipher = Present(round_1_present_key)
                key_half = cipher.encrypt(iv) ^ iv
            else:
                cipher = Present(final_cnst)
                key_half = cipher.encrypt(key_half) ^ key_half
        full_key |= key_half << (64 * i)
    return full_key


def _reformat_flash_vmem(
        flash_vmem_file: str,
        scrambling_configs: FlashScramblingConfigs) -> List[str]:
    """Reformat flash .vmem file to add integrity/reliablity ECC and (optional) scrambling."""

    # Open (raw) flash .vmem file and read into memory, skipping comment lines.
    try:
        flash_vmem = Path(flash_vmem_file).read_text()
    except IOError:
        raise Exception(f"Unable to open {flash_vmem_file}")
    flash_vmem_lines = re.findall(r"^@.*$", flash_vmem, flags=re.MULTILINE)

    # Load project SECDED configuration.
    ecc_configs = secded_gen.load_secded_config()

    # Add integrity/reliability ECC, and potentially scramble, each flash word.
    reformatted_vmem_lines = []
    address = 0
    for line in flash_vmem_lines:
        line_items = line.split()
        reformatted_line = ""
        address_offset = 0
        data = None
        for item in line_items:
            # Process the address first.
            if re.match(r"^@", item):
                reformatted_line += item
                address = int(item.lstrip("@"), 16)
                address_offset = 0
            # Process the data words.
            else:
                data = int(item, 16)
                # `data_w_intg_ecc` will be in format {ECC bits, data bits}.
                data_w_intg_ecc, _ = secded_gen.ecc_encode(
                    ecc_configs, "hamming", FLASH_WORD_SIZE, data)
                # Due to storage constraints the first nibble of ECC is dropped.
                data_w_intg_ecc &= 0xF_FFFF_FFFF_FFFF_FFFF
                if scrambling_configs.scrambling_enabled:
                    intg_ecc = data_w_intg_ecc & (0xF << FLASH_WORD_SIZE)
                    data = _xex_scramble(data, address + address_offset,
                                         scrambling_configs.addr_key,
                                         scrambling_configs.data_key)
                    data_w_intg_ecc = intg_ecc | data
                # `data_w_full_ecc` will be in format {reliablity ECC bits,
                # integrity ECC bits, data bits}.
                data_w_full_ecc, _ = secded_gen.ecc_encode(
                    ecc_configs, "hamming",
                    FLASH_WORD_SIZE + FLASH_INTEGRITY_ECC_SIZE,
                    data_w_intg_ecc)
                reformatted_line += str.format(VMEM_FORMAT_STR,
                                               data_w_full_ecc)
                address_offset += 1

        # Increment the address (needed if the next line does not start with an address)
        address += address_offset

        # Append reformatted line to what will be the new output .vmem file.
        reformatted_vmem_lines.append(reformatted_line)

    return reformatted_vmem_lines


def main(argv: List[str]):
    # Parse command line args.
    parser = argparse.ArgumentParser()
    parser.add_argument("--in-flash-vmem",
                        type=str,
                        required=True,
                        help="Input VMEM file to reformat.")
    parser.add_argument("--in-otp-mmap",
                        type=str,
                        help="OTP memory map HJSON file.")
    parser.add_argument("--in-otp-vmem",
                        type=str,
                        help="Input OTP (VMEM) file to retrieve data from.")
    parser.add_argument("--otp-seed",
                        type=int,
                        help="""
                        Configuration override seed used to randomize OTP
                        netlist constants.
                        """)
    parser.add_argument("--out-flash-vmem",
                        type=str,
                        required=True,
                        help="Output VMEM file.")
    parser.add_argument("--otp-data-perm",
                        type=vmem_permutation_string,
                        metavar="<map>",
                        default=[],
                        help="""
                        This is a post-processing option and allows permuting
                        the bit positions before writing the memfile. The bit
                        mapping needs to be supplied as a comma separated list
                        of bit slices, where the numbers refer to the bit
                        positions in the original data word before remapping,
                        for example:

                        "[7:0],[15:8]".

                        The mapping must be bijective - otherwise this will
                        generate an error.
                        """)
    args = parser.parse_args(argv)

    log_level = log.INFO
    log_format = '%(levelname)s: [%(filename)s:%(lineno)d] %(message)s'
    log.basicConfig(level=log_level,
                    format=log_format,
                    handlers=[
                        # log.FileHandler("gen-flash-img.log"),
                        log.StreamHandler()
                    ])

    scrambling_configs = FlashScramblingConfigs()

    # (If provided) Validate optional OTP bit permutation configuration.
    if args.otp_data_perm:
        validate_data_perm_option(OTP_WORD_SIZE_WECC, args.otp_data_perm)

    # To check if scrambling is enabled, and to pre-scramble the Flash data if it
    # _IS_ enabled, both the OTP mmap file and an OTP .vmem file are required to
    # provide the necessary netlist constants and key seeds.
    if not (args.in_otp_mmap and args.in_otp_vmem):
        log.info("Cannot pre-scramble Flash .vmem file without both mmap and vmem inputs.")
        log.info("Scrambling will not be applied.")

    else:
        # Parse the OTP mmap .hjson file to generate and extract the needed
        # netlist constants.
        _get_otp_ctrl_netlist_consts(args.in_otp_mmap, args.otp_seed,
                                     scrambling_configs)

        # Read the input OTP .vmem file to determine if scrambling is currently
        # enabled, and if so, get the flash scrambling key seeds.
        _get_flash_scrambling_configs(args.in_otp_vmem, args.otp_data_perm,
                                      scrambling_configs)

        # Scrambling may be disabled in the provided OTP .vmem file.
        # If so, we can skip straight to reformatting step.
        if scrambling_configs.scrambling_enabled:
            # Derive flash scrambling keys from netlist constants + key seeds.
            scrambling_configs.addr_key = _derive_flash_scrambling_key(
                scrambling_configs, FlashScramblingKeyType.ADDRESS)
            scrambling_configs.data_key = _derive_flash_scrambling_key(
                scrambling_configs, FlashScramblingKeyType.DATA)


    # Reformat flash .vmem file to add integrity/reliablity ECC and
    # (optional) scrambling.
    reformatted_vmem_lines = _reformat_flash_vmem(args.in_flash_vmem,
                                                  scrambling_configs)

    # Write re-formatted output file. Use binary mode and a large buffer size
    # to improve performance.
    with open(args.out_flash_vmem, "wb", buffering=2097152) as of:
        of.write(create_outfile_header(sys.argv[0], args).encode('utf-8'))
        of.write("\n".join(reformatted_vmem_lines).encode('utf-8'))


if __name__ == "__main__":
    main(sys.argv[1:])
