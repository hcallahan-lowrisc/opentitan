#!/usr/bin/env python3
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Models the OTP partition memory map, used to generate RTL packages and documentation.

The derived class OtpMemImg models an OTP system with (non-default) values for each partition
item, as well as the current lifecycle state. From this, a valid memory image can be generated
that is targeted towards loading into simulation/emulation environments via a backdoor method.

This class models the OTP partitions and items we are configuring the system to use,
as well as some netlist constants used in the RTL.

Constructing an OtpMemMap object requires providing a MMap Configuration object, which
defines the partitions and items, as well as their layout and any additional attributes
they may have.
After validating the intended OTP configuration, the object can be queried for information
used to constuct a number of pieces of hardware and documentation collateral, such as:
- SystemVerilog packages containing netlist constants, and interface definitions
- SystemVerilog used in a DV/UVM environment, for environment, stimulus and coverage collection
- Software Header Files and low-level accessors / drivers
- Tables that the describe the specific MMAP config for insertion into OTP Documentation

A memory image for the state of the OTP system cannot yet be generated, as at a minimum, we
need to provide a current lifecycle state.
"""

import copy
import logging as log
from math import ceil, log2
from typing import Optional

from mubi.prim_mubi import is_width_valid, mubi_value_as_int
from tabulate import tabulate
from topgen import secure_prng as sp

from lib.common import check_bool, check_int, random_or_hexvalue

DIGEST_SUFFIX = "_DIGEST"
DIGEST_SIZE = 8

# Seed diversification constant for OtpMemMap (this enables to use
# the same seed for different classes)
OTP_SEED_DIVERSIFIER = 177149201092001677687

# This must match the rtl parameter ScrmblBlockWidth / 8
SCRAMBLE_BLOCK_WIDTH = 8

def _avail_blocks(size: int) -> int:
    """If remaining number of bytes are not perfectly aligned, truncate."""
    return int(size / SCRAMBLE_BLOCK_WIDTH)

def _dist_blocks(num_blocks: int, parts: list):
    """Distribute number of blocks among partitions."""
    num_parts = len(parts)

    if not num_parts:
        return

    # Very slow looping
    for i in range(num_blocks):
        parts[i % num_parts]['size'] += SCRAMBLE_BLOCK_WIDTH

def _calc_size(part: dict, size: int) -> int:
    """Return the aligned partition size."""

    size = SCRAMBLE_BLOCK_WIDTH * \
        int((size + SCRAMBLE_BLOCK_WIDTH - 1) / SCRAMBLE_BLOCK_WIDTH)

    if part["sw_digest"] or part["hw_digest"]:
        size += DIGEST_SIZE

    return size


class OtpMemMap_Validator():
    """This class validates and constructs an OTP mmap configuration.

    Input is a config object dictionary, typically loaded from a mmap .hjson file.
    As this input is validated, additional metadata is added in the form of new
    fields and values derived from other fields.
    """

    def __init__(self, config: dict):
        # Initial checks that the top-level fields exist. These fields
        # pass their values down to individual validation functions, so
        # we need to confirm they exist to even attempt to lookup their
        # values below.
        if "seed" not in config:
            raise RuntimeError("Missing RNG seed value.")
        if "otp" not in config:
            raise RuntimeError("Missing otp configuration.")
        if "scrambling" not in config:
            raise RuntimeError("Missing scrambling configuration.")
        if "partitions" not in config:
            raise RuntimeError("Missing partition configuration.")
        if not isinstance(config["partitions"], list):
            raise RuntimeError('The "partitions" key must contain a list')

        self.ic = config                 # input config
        self.vc = copy.deepcopy(self.ic) # validated config

    def validate_config(self) -> None:
        """"""

        # Validate fields of 'otp' config dict, and define some derived attributes.
        OtpMemMap_Validator._validate_otp(self.vc["otp"])

        # Validate fields of the 'scrambling' config dict.
        OtpMemMap_Validator._validate_scrambling(self.vc["scrambling"])

        # Validate all partitions in the memory map.
        self._validate_parts(self.vc["partitions"])

    @staticmethod
    def _validate_otp(otp: dict) -> None:
        """Validate fields of 'otp' config dict, and define some derived attributes."""

        otp.setdefault("depth", "1024")
        otp.setdefault("width", "2")
        otp["depth"] = check_int(otp["depth"])
        otp["width"] = check_int(otp["width"])

        # Define some derived attributes
        otp["size"] = otp["depth"] * otp["width"]
        otp["addr_width"] = ceil(log2(check_int(otp["depth"])))
        otp["byte_addr_width"] = ceil(log2(otp["size"]))

    @staticmethod
    def _validate_scrambling(scr: dict):
        """Validate fields of the 'scrambling' config dict."""

        scr.setdefault("key_size", "16")
        scr.setdefault("iv_size", "8")
        scr.setdefault("cnst_size", "16")
        scr["key_size"] = check_int(scr["key_size"])
        scr["iv_size"] = check_int(scr["iv_size"])
        scr["cnst_size"] = check_int(scr["cnst_size"])

        if "keys" not in scr:
            raise RuntimeError("Missing key configuration.")
        if "digests" not in scr:
            raise RuntimeError("Missing digest configuration.")

        for key in scr["keys"]:
            key.setdefault("name", "unknown_key_name")
            key.setdefault("value", "<random>")

        for dig in scr["digests"]:
            dig.setdefault("name", "unknown_key_name")
            dig.setdefault("iv_value", "<random>")
            dig.setdefault("cnst_value", "<random>")

    @staticmethod
    def _validate_item(item: dict, isBuffered: bool, isSecret: bool):
        """Validates a single item within a partition.

        Inputs:
            item: the configuration dict of the item
            isBuffered: if the item is in a buffered partition
            isSecret: if the item is in a secret partition

        Generate random constant to be used when partition has
        not been initialized yet or when it is in error state.
        """

        # Set default values for absent fields
        item.setdefault("name", "unknown_name")
        item.setdefault("size", "0")
        item.setdefault("isdigest", "false")
        item.setdefault("ismubi", "false")
        item.setdefault("iskeymgr_creator", "false")
        item.setdefault("iskeymgr_owner", "false")

        # Make sure field values have the correct types
        item["iskeymgr_creator"] = check_bool(item["iskeymgr_creator"])
        item["iskeymgr_owner"] = check_bool(item["iskeymgr_owner"])
        item["isdigest"] = check_bool(item["isdigest"])
        item["ismubi"] = check_bool(item["ismubi"])
        item["size"] = check_int(item["size"])

        def _validate_keymgr_attrs() -> None:
            """Validate that items for keymgr use have a valid configuration."""

            # Key material can either be for the creator stage or owner stage, but not
            # both. This is because the two have separate SW write enable signals in HW.
            if item["iskeymgr_creator"] and item["iskeymgr_owner"]:
                raise RuntimeError(
                    "Key material for {} for sideloading into the key manager cannot be "
                    "associated with the creator AND the owner.".format(item["name"]))

            # Key material for the keymgr needs to live in a buffered partition so that
            # it can be sideloaded. The partition should also be secret for
            # confidentiality.
            if item["iskeymgr_creator"] or item["iskeymgr_owner"]:
                if not isBuffered:
                    raise RuntimeError(
                        "Key material {} for sideloading into the key manager needs "
                        "to be stored in a buffered partition.".format(item["name"]))
                if not isSecret:
                    raise RuntimeError(
                        "Key material {} for sideloading into the key manager needs "
                        "to be stored in a secret partition.".format(item["name"]))

        _validate_keymgr_attrs()

        # Genererate default values for MUBI types
        # - If 'inv_default' is not given, assume a default of Mubi::False
        item_width = item["size"] * 8
        if item["ismubi"]:
            item.setdefault("inv_default", "false")
            item["inv_default"] = check_bool(item["inv_default"])

            # Lookup MUBI encoding for the default value
            if not is_width_valid(item_width):
                raise RuntimeError(f"Mubi value {item['name']} has invalid width")
            item["inv_default"] = mubi_value_as_int(item["inv_default"], item_width)

    def _validate_part(self, part: dict):
        """Validates a partition within the OTP memory map."""

        # Set default values for ommitted attributes
        part.setdefault("name", "unknown_name")
        part.setdefault("variant", "Unbuffered")
        part.setdefault("secret", False)
        part.setdefault("sw_digest", False)
        part.setdefault("hw_digest", False)
        part.setdefault("write_lock", "none")
        part.setdefault("read_lock", "none")
        part.setdefault("key_sel", "NoKey")
        part.setdefault("absorb", False)
        part.setdefault("iskeymgr_creator", False)
        part.setdefault("iskeymgr_owner", False)
        log.debug("Validating partition {}".format(part["name"]))

        # Make sure these are boolean types (simplifies the mako templates)
        part["secret"] = check_bool(part["secret"])
        part["sw_digest"] = check_bool(part["sw_digest"])
        part["hw_digest"] = check_bool(part["hw_digest"])
        part["bkout_type"] = check_bool(part["bkout_type"])
        part["integrity"] = check_bool(part["integrity"])

        # basic checks
        if part["variant"] not in ["Unbuffered", "Buffered", "LifeCycle"]:
            raise RuntimeError(f"Invalid partition type {part['variant']}")

        key_names = ["NoKey"] + [key['name'] for key in self.vc["scrambling"]["keys"]]
        if part["key_sel"] not in key_names:
            raise RuntimeError(f"Invalid 'key_sel' value: {part['key_sel']}")

        if check_bool(part["secret"]) and part["key_sel"] == "NoKey":
            raise RuntimeError(
                "A secret partition needs a 'key_sel' (key select) value other than 'NoKey'")

        if part["write_lock"].lower() not in ["digest", "csr", "none"]:
            raise RuntimeError("Invalid value for write_lock")

        if part["read_lock"].lower() not in ["digest", "csr", "none"]:
            raise RuntimeError("Invalid value for read_lock")

        if part["sw_digest"] and part["hw_digest"]:
            raise RuntimeError(
                "A partition with both SW and HW digest is not supported.")

        if part["variant"] == "Unbuffered" and part["hw_digest"]:
            raise RuntimeError(
                "Unbuffered partitions with a HW digest are not supported.")

        if part["variant"] == "Buffered" and part["read_lock"].lower() == "csr":
            raise RuntimeError(
                "CSR read lock is only supported for SW partitions.")

        if not part["sw_digest"] and not part["hw_digest"]:
            if ((part["write_lock"].lower() == "digest") or
                (part["read_lock"].lower() == "digest")):
                raise RuntimeError(
                    "A partition can only be write/read lockable if it has a hw or sw digest.")

        # Validate items and calculate partition size if necessary

        # Basic type checks
        if not isinstance(part['items'], list):
            raise RuntimeError('The "items" key must contain a list')
        if (len(part['items']) == 0):
            raise RuntimeError('A partition cannot have no items.')
        # Check for duplicate item names
        item_names = [item['name'] for item in part['items']]
        if not len(item_names) == len(set(item_names)):
            raise RuntimeError("Duplicate item names within a partition is not allowed.")

        # Validate all items in the partition individually
        for item in part["items"]:
            OtpMemMap_Validator._validate_item(
                item=item,
                isBuffered=(part["variant"] == "Buffered"),
                isSecret=part["secret"])

        # Partitions can either hold keymaterial for the creator stage or owner
        # stage, but not both. This is because the two have separate SW write
        # enable signals in HW.
        for item in part["items"]:
            if item["iskeymgr_creator"]:
                part["iskeymgr_creator"] = True
            elif item["iskeymgr_owner"]:
                part["iskeymgr_owner"] = True
        if part["iskeymgr_creator"] and part["iskeymgr_owner"]:
            raise RuntimeError(
                f"Partition {part['name']} with key material for the key manager cannot "
                "be associated with the creator AND the owner.")

        # If the 'size' attr was not previously defined, set it
        if "size" not in part:
            size = sum((item['size'] for item in part['items']))
            part["size"] = _calc_size(part, size)

        # Make sure this has integer type.
        part["size"] = check_int(part["size"])

        # Make sure partition size is aligned.
        if part["size"] % SCRAMBLE_BLOCK_WIDTH:
            raise RuntimeError("Partition size must be 64bit aligned")

    def _dist_unused(self, parts: list[dict], allocated: int):
        """Distribute unused OTP bits."""

        # determine how many aligned blocks are left
        # unaligned bits are not used
        leftover_blocks = _avail_blocks(
            self.vc['otp']['size'] - allocated)

        # sponge partitions are partitions that will accept leftover allocation
        sponge_parts = [p for p in parts if p['absorb']]

        # spread out the blocks
        _dist_blocks(leftover_blocks, sponge_parts)

    def _validate_parts(self, parts: list[dict]) -> dict:
        """Validate the OTP partitions in the memory map.

        - Validate all partitions individually (and their items)
        - Distribute unallocated bits
        - Automatically add 'digest' items at the end of partitions where requested.
        - Calculate the offsets for all partitions and items.
        - Check all items/partitions fit within the allotted sizes.
        """

        # Check for duplicate partition names
        part_names = [part['name'] for part in parts]
        if not (len(part_names) == len(set(part_names))):
            raise RuntimeError("Duplicate partition names is not allowed.")

        # Current DV and HW always assumes the LC partition is the last partition
        if parts[-1]["variant"] != "LifeCycle":
            raise RuntimeError(
                "The last partition must always be the life cycle partition")

        # Validate all individal partitions (and their items)
        for p in parts:
            self._validate_part(p)

        # Distribute unallocated bits
        allocated_bytes = sum((part['size'] for part in parts))
        self._dist_unused(parts, allocated_bytes)

        # Determine offsets
        current_offset = 0
        for j, part in enumerate(parts):

            part['offset'] = current_offset
            if check_int(part['offset']) % SCRAMBLE_BLOCK_WIDTH:
                raise RuntimeError(
                    f"Partition {part['name']} offset must be 64bit aligned")

            log.debug("Partition: offset {:4} | size {:4} | name | {}".format(
                part["offset"], part["size"], part["name"]))

            # Loop over items within a partition
            for k, item in enumerate(part["items"]):
                item_name = item['name']
                item['offset'] = current_offset
                log.debug("> Item   : offset {:4} | size {:4} | name | {}".format(
                    current_offset, item["size"], item["name"]))
                current_offset += check_int(item["size"])

            # If a digest is required, place it at the end of a partition.
            if part["sw_digest"] or part["hw_digest"]:

                # The digest must be placed into the last 64bit word of a partition.
                expected_digest_offset = check_int(part["offset"]) + \
                                         check_int(part["size"]) - DIGEST_SIZE
                if current_offset > expected_digest_offset:
                    raise RuntimeError(
                        f"Not enough space left in partition {part['name']}"
                        "to accommodate a digest. Bytes available = "
                        f"{part['size']}, bytes allocated to items = "
                        f"{current_offset - part['offset']}, digest size = {DIGEST_SIZE}")

                # Create an item for the digest, and add it to the 'items' attribute
                digest_name = part["name"] + DIGEST_SUFFIX
                digest_item = {
                    "name": digest_name,
                    "size": DIGEST_SIZE,
                    "offset": expected_digest_offset,
                    "ismubi": False,
                    "isdigest": True,
                    "inv_default": "<random>",
                    "iskeymgr_creator": False,
                    "iskeymgr_owner": False
                }
                part["items"].append(digest_item)

                log.debug("> > Digest {} at offset {} with size {}".format(
                    digest_name, expected_digest_offset, DIGEST_SIZE))

                # Update the offset to start the next partition
                current_offset = expected_digest_offset
                current_offset += DIGEST_SIZE

            # All items in the partition have been handled.
            # Check the final size
            partition_end_offset = check_int(part["offset"]) + check_int(part["size"])
            if current_offset > partition_end_offset:
                raise RuntimeError(f"Not enough space in partition {part['name']} "
                                   "to accommodate all items. Bytes available = "
                                   f"{part['size']}, Bytes allocated to items = "
                                   f"{current_offset - part['offset']}")
            # Update the starting offset for the next partition
            current_offset = partition_end_offset

        # Check if all paritions fit into the overall OTP size available.
        if current_offset > self.vc["otp"]["size"]:
            raise RuntimeError(
                "OTP is not big enough to store all partitions. "
                f"Bytes available = {self.vc['otp']['size']}, "
                f"Bytes required = {current_offset}")

        # Everything has validated, print and return.
        log.debug(f"Total number of partitions: {len(parts)}")
        log.debug(f"Bytes available in OTP: {self.vc['otp']['size']}")
        log.debug(f"Bytes required for partitions: {current_offset}")


class OtpMemMap():
    """This class models the base configuration of an OpenTitan OTP system, the memory map.

    Constructing this object from an input mmap .hjson file will validate the memory
    map in that file for conformance and fitment based on specified avilable size.

    It will also generate any required random constants, such as values that become netlist
    constants in SV packages, and initial values for fields in an generated OTP memory image file.

    Once constructed, the object provides methods to generate output collateral based on the
    memory map. For example,
    - Creating documentation, such as generated tables.
    - Accessor methods for partitions/items (get_part(),get_item()) for use by other scripts.
    """

    # This holds the config dict.
    config = {}

    def __init__(self, config):
        """Construct from a config object dictionary, typically loaded from a mmap .hjson file.

        Note. that the seed value used to instantiate the RNG is taken from config['seed'] in the
        input dictionary. To change this seed, it should be overwritten before passing the dict
        to this constructor.
        """

        log.debug('')
        log.debug('Parsing and validating OTP memory map...')
        log.debug('')

        if "seed" not in config:
            raise RuntimeError("Missing seed in configuration.")

        self.validator = OtpMemMap_Validator(config)
        self.validator.validate_config()
        self.config = self.validator.vc

        log.debug('')
        log.debug('Successfully parsed and validated OTP memory map.')
        log.debug('')

    def gen_netlist_constants(self) -> None:
        """Iterate over the OTP datastructure and insert random values where required.

        There are two types of random netlist constants we may generate:
        - Static scrambling key seeds and cipher IVs / finalization constants.
        - Invalid Default Values for buffered partition items
        """

        # First, generate the Netlist Constants in the 'scrambling' section

        log.debug('')
        log.debug("Generating randomized scrambling seed netlist constants.")

        scr = self.config["scrambling"]
        for key in scr["keys"]:
            # Generate a random value for each scrambling key
            isRandomized = random_or_hexvalue(key, "value", scr["key_size"] * 8)
            if isRandomized:
                log.debug('> Randomized scr key {} with size {}B and value {}:'.format(
                    key['name'], scr["key_size"], key['value']))

        for dig in scr["digests"]:
            # For each digest, generate a random value for the Initialization Vector (iv)
            # and the Finalization Constant (cnst)
            isRandomized = random_or_hexvalue(dig, "iv_value", scr["iv_size"] * 8)
            if isRandomized:
                log.debug('> Randomized digest {} iv_value with size {}B and value {}:'.format(
                    dig['name'], scr["iv_size"], dig['iv_value']))

            isRandomized = random_or_hexvalue(dig, "cnst_value", scr["cnst_size"] * 8)
            if isRandomized:
                log.debug('> Randomized digest {} cnst_value with size {}B and value {}:'.format(
                    dig['name'], scr["cnst_size"], dig['cnst_value']))

        # Next, generate the 'inv_default' (Invalid Default) values for buffered partitions

        log.debug('')
        log.debug("Generating randomized 'Invalid Default' netlist constants for buffered partition items.")

        parts = self.config["partitions"]
        # Next, iterate over the partitions
        for part in parts:
            # Loop over items within a partition (including digest items)
            for item in part["items"]:
                if not item["ismubi"]:
                    isRandomized = random_or_hexvalue(item, "inv_default", item["size"] * 8)
                    if isRandomized:
                        log.debug(
                            '> Randomized invalid default for part {} item {} size {}B value {}:'.format(
                                part['name'], item['name'], item["size"], item["inv_default"]))

    def gen_mmap_random_constants(self) -> None:
        """Initialize the RNG, and use it to generate random netlist constants."""

        rng_seed = check_int(self.config["seed"])

        # (Re-)Initialize the RNG.
        sp.reseed(OTP_SEED_DIVERSIFIER + rng_seed)
        log.debug('')
        log.debug('OtpMemMap RNG Seed: {0:d}'.format(rng_seed))

        # Use the initialized RNG to generate netlist constants
        self.gen_netlist_constants()

        log.debug('')
        log.debug("Randomization complete.")

    def create_partitions_table(self) -> str:
        """Generates a documentation table for the partitions in the OTP memory map."""

        header = [
            "Partition", "Secret", "Buffered", "Integrity", "WR Lockable",
            "RD Lockable", "Description"
        ]
        table = [header]
        colalign = ("center", ) * len(header[:-1]) + ("left", )
        for part in self.config["partitions"]:
            is_secret = "yes" if check_bool(part["secret"]) else "no"
            is_buffered = "yes" if part["variant"] in [
                "Buffered", "LifeCycle"
            ] else "no"
            wr_lockable = "no"
            if part["write_lock"].lower() in ["csr", "digest"]:
                wr_lockable = "yes (" + part["write_lock"] + ")"
            rd_lockable = "no"
            if part["read_lock"].lower() in ["csr", "digest"]:
                rd_lockable = "yes (" + part["read_lock"] + ")"
            integrity = "no"
            if part["integrity"]:
                integrity = "yes"
            desc = part["desc"]
            row = [
                part["name"], is_secret, is_buffered, integrity, wr_lockable,
                rd_lockable, desc
            ]
            table.append(row)

        return tabulate(table,
                        headers="firstrow",
                        tablefmt="pipe",
                        colalign=colalign)

    def create_mmap_table(self) -> str:
        """Generates a documentation table with resolved addresses of the OTP memory map."""

        header = [
            "Index", "Partition", "Size [B]", "Access Granule", "Item",
            "Byte Address", "Size [B]"
        ]
        table = [header]
        colalign = ("center", ) * len(header)

        for k, part in enumerate(self.config["partitions"]):
            for j, item in enumerate(part["items"]):
                granule = "64bit" if check_bool(part["secret"]) else "32bit"

                if check_bool(item["isdigest"]):
                    granule = "64bit"
                    name = "[{}](#Reg_{}_0)".format(item["name"],
                                                    item["name"].lower())
                else:
                    name = item["name"]

                if j == 0:
                    row = [str(k), part["name"], str(part["size"]), granule]
                else:
                    row = ["", "", "", granule]

                row.extend([
                    name, "0x{:03X}".format(check_int(item["offset"])),
                    str(item["size"])
                ])

                table.append(row)

        return tabulate(table,
                        headers="firstrow",
                        tablefmt="pipe",
                        colalign=colalign)

    def create_description_table(self) -> str:
        """Generates a documentation table with descriptions for each item in the mmap."""

        header = ["Partition", "Item", "Size [B]", "Description"]
        table = [header]
        # Everything column center aligned, except the descriptions.
        colalign = ["center"] * len(header)
        colalign[-1] = "left"

        for k, part in enumerate(self.config["partitions"]):
            for j, item in enumerate(part["items"]):
                if part["secret"] or part["name"] in {
                        "VENDOR_TEST", "LIFE_CYCLE"
                }:
                    continue

                name = None
                if check_bool(item["isdigest"]):
                    continue
                else:
                    name = item["name"]

                if j == 0:
                    row = [part["name"]]
                else:
                    row = [""]
                desc = " ".join(item.get("desc", "").split("\n"))
                row.extend([name, str(item["size"]), desc])

                table.append(row)

        return tabulate(table,
                        headers="firstrow",
                        tablefmt="pipe",
                        colalign=colalign)

    def create_digests_table(self) -> str:
        """Generates a documentation table for all digest items in the OTP memory map."""

        header = ["Digest Name", " Affected Partition", "Calculated by HW"]
        table = [header]
        colalign = ("center", ) * len(header)

        for part in self.config["partitions"]:
            if check_bool(part["hw_digest"]) or check_bool(part["sw_digest"]):
                is_hw_digest = "yes" if check_bool(part["hw_digest"]) else "no"
                for item in part["items"]:
                    if check_bool(item["isdigest"]):
                        name = "[{}](#Reg_{}_0)".format(
                            item["name"], item["name"].lower())
                        row = [name, part["name"], is_hw_digest]
                        table.append(row)
                        break
                else:
                    raise RuntimeError(
                        "Partition with digest does not contain a digest item")

        return tabulate(table,
                        headers="firstrow",
                        tablefmt="pipe",
                        colalign=colalign)

    def get_part(self, part_name: str) -> Optional[dict]:
        """Get partition by name.

        Returns:
            If found, a dict of the parsed config for the partition
              or
            If not found, None
        """
        return next(
            filter(lambda p: p['name'] == part_name,
                   self.config['partitions']),
            None #/*default for no-match*/
        )

    def get_item(self, part_name: str, item_name: str) -> Optional[dict]:
        """Get partition item by name.

        Returns:
            If found, a dict of the parsed config for the item
              or
            If not found, None
        """
        part = self.get_part(part_name)
        return next(
            filter(lambda i: i['name'] == item_name,
                   part['items']),
            None #/*default for no-match*/
        )
