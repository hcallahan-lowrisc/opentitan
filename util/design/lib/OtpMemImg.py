#!/usr/bin/env python3
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""OTP memory image class, used to create preload images for the OTP memory.

This class derives from OtpMemMap, which models the OTP partitions and items we
are configuring the system to use, as well as some netlist constants used in the block.

OtpMemImg models the OTP partitions and items with a set of (non-default) values associated
with the fields. Constructing an OtpMemImg object requires providing a Image Configuration
object which can set values for any partition item, as well as optionally locking partitions
and inserting the appropriate digest value that the hardware mechanism would generate upon locking.
This Image Configuration object can also set the current LifeCycle State.

After construction, additional Image Configuration objects can be passed which are
applied additively to the base OtpMemImg, allowing additional field values to be set
while also overriding the values of previously set fields.

This allows OTP preload images to be created with any arbitrary set of values in a way
that is convenient for composition.
This can be used, for example, to additively generate images of the OTP state that
mirrors the evolution of an OpenTitan system being provisioned.

The primary memfile output (.vmem) is intended to be consumed by Verilog's $readmemh
function. Therefore, the address is a *word* offset, not a byte offset. The address
does not count ECC bits.

These memfiles are intended for use in simulations and FPGA emulation.
"""

import copy
import logging as log
from pathlib import Path
from typing import List, Tuple

from mako.template import Template
from mubi.prim_mubi import mubi_value_as_int
from topgen import secure_prng as sp

from lib import common
from lib.LcStEnc import LcStEnc
from lib.OtpMemMap import OtpMemMap
from lib.Present import Present

# Seed diversification constant for OtpMemImg (this enables to use
# the same seed for different classes)
OTP_IMG_SEED_DIVERSIFIER = 1941661965323525198146

_OTP_SW_SKIP_FROM_HEADER = ('VENDOR_TEST', 'HW_CFG0', 'HW_CFG1', 'SECRET0',
                            'SECRET1', 'SECRET2', 'LIFE_CYCLE')
_OTP_SW_WRITE_BYTE_ALIGNMENT = {
    'CREATOR_SW_CFG': 4,
    'OWNER_SW_CFG': 4,
    'HW_CFG0': 4,
    'HW_CFG1': 4,
    'ROT_CREATOR_AUTH_CODESIGN': 4,
    'ROT_CREATOR_AUTH_STATE': 4,
    'SECRET0': 8,
    'SECRET1': 8,
    'SECRET2': 8,
}


def _present_64bit_encrypt(plain, key):
    """Scramble a 64bit block with PRESENT cipher."""

    # Make sure data is within 64bit range
    assert (plain >= 0) and (plain < 2**64), \
        'Data block is out of 64bit range'

    # Make sure key is within 128bit range
    assert (key >= 0) and (key < 2**128), \
        'Key is out of 128bit range'

    # Make sure inputs are integers
    assert isinstance(plain, int) and isinstance(key, int), \
        'Data and key need to be of type int'

    cipher = Present(key, rounds=32, keylen=128)
    return cipher.encrypt(plain)


def _present_64bit_digest(data_blocks, iv, const):
    """Compute digest over multiple 64bit data blocks."""

    # Make a deepcopy since we're going to modify and pad the list.
    data_blocks = copy.deepcopy(data_blocks)

    # We need to align the number of data blocks to 2x64bit
    # for the digest to work properly.
    if len(data_blocks) % 2 == 1:
        data_blocks.append(data_blocks[-1])

    # Append finalization constant.
    data_blocks.append(const & 0xFFFF_FFFF_FFFF_FFFF)
    data_blocks.append((const >> 64) & 0xFFFF_FFFF_FFFF_FFFF)

    # This computes a digest according to a Merkle-Damgard construction
    # that uses the Davies-Meyer scheme to turn the PRESENT cipher into
    # a one-way compression function. Digest finalization consists of
    # a final digest round with a 128bit constant.
    # See also: https://docs.opentitan.org/hw/ip/otp_ctrl/doc/index.html#scrambling-datapath
    state = iv
    last_b64 = None
    for b64 in data_blocks:
        if last_b64 is None:
            last_b64 = b64
            continue

        b128 = last_b64 + (b64 << 64)
        state ^= _present_64bit_encrypt(state, b128)
        last_b64 = None

    assert last_b64 is None
    return state


def _add_bitness_to_secded(secded_cfg: dict) -> None:
    """Calculate the bitness based on a secded configuration dict."""

    data_width = secded_cfg['data_width']
    ecc_width = secded_cfg['ecc_width']
    bytes_per_word_ecc = (data_width + ecc_width + 7) // 8
    bitness = bytes_per_word_ecc * 8

    secded_cfg["bitness"] = bitness


def _to_memfile_with_ecc(data,
                         annotation: list,
                         secded_cfg: dict,
                         data_perm: list[int]) -> str:
    """Compute ECC and convert into MEM file.

    - Apply the permutation 'data_perm'
      (Pass an 'identity' permutation for no transform.)
    """

    log.debug('Converting partition data to MEM file format...')

    # Pre-conversion checks
    data_width = secded_cfg['data_width']
    ecc_width = secded_cfg['ecc_width']
    assert data_width % 8 == 0, \
        'OTP data width must be a multiple of 8'
    assert data_width <= 64, \
        'OTP data width cannot be larger than 64'

    # Create helper variables
    num_words = len(data) * 8 // data_width
    bytes_per_word = data_width // 8
    bytes_per_word_ecc = (data_width + ecc_width + 7) // 8
    bit_padding = bytes_per_word_ecc * 8 - data_width - ecc_width

    layout_str = f"{num_words} x {secded_cfg['bitness']}bit"
    mem_lines = [
        f'// OTP MEM file with layout : {layout_str} ',
    ]
    log.debug(f"Memory layout (with ECC) : {layout_str} ")

    for i_word in range(num_words):
        # Assemble native OTP word and uniquify annotation for comments
        word_address = i_word * bytes_per_word
        word = 0
        word_annotations = set()
        for i_byte in range(bytes_per_word):
            byte_address = word_address + i_byte
            word += data[byte_address] << (i_byte * 8)
            word_annotations.add(annotation[byte_address])

        word_bin = f"0{word}b"

        # ECC encode
        word_bin = common.ecc_encode(secded_cfg, word_bin)
        # Pad to word boundary
        word_bin = ('0' * bit_padding) + word_bin
        # Permute data (if needed)
        word_bin = common.permute_bits(word_bin, data_perm)

        # Convert word to hex repr
        hex_format_str = f"0{bytes_per_word_ecc * 2}x"
        word_hex = format(int(word_bin, 2), hex_format_str)

        # Build a MEM line containing this word's address in the memory map and
        # its value. Because this file will be read by Verilog's $readmemh, the
        # address is a *word* offset, not a byte offset. The address does not
        # count ECC bits. In a comment, we also include any annotations
        # associated with the word.
        line_tpl = '@{:06x} {} // {}'
        line = line_tpl.format(i_word, word_hex, ', '.join(word_annotations))

        mem_lines.append(line)

    log.debug('Done.')

    return ('\n'.join(mem_lines))


def _check_unused_keys(dict_to_check: dict, msg_postfix: str = ""):
    """If there are unused keys, print their names and error out."""

    for key in dict_to_check.keys():
        log.debug(f"Unused key '{key}' in '{msg_postfix}'")
    if dict_to_check:
        raise RuntimeError('Aborting due to unused keys in config dict')


def _int_to_hex_array(val: int, size: int, alignment: int) -> List[str]:
    """Converts `val` long value into list of hex strings.

    Args:
        val: Input value.
        size: Target output size in number of bytes.
        alignment: Number of bytes to be bundled into a single hex value.

    Returns:
        A list of string hex values using little-endian encoding.
    """

    fmt_str = '{:0' + str(size * 2) + 'x}'
    val_hex = fmt_str.format(val)

    bytes_hex = []
    for i in range(0, len(val_hex), 2):
        bytes_hex.append(val_hex[i:i + 2])

    if len(bytes_hex) % alignment != 0:
        raise ValueError(len(bytes_hex))

    word_list = []
    for i in range(0, len(bytes_hex), alignment):
        word_list.append("".join(bytes_hex[i:i + alignment]))

    word_list.reverse()
    return [f"0x{y}" for y in word_list]


class OtpMemImg(OtpMemMap):
    """This class models an OTP memory map after Image Configuration objects have been applied.

    These Image Configuration objects augment the base memory map object by setting values for
    fields in the partitions mmap, as well as a current lifecycle state.

    This class adds the ability to generate a memory initialization file (e.g. a .vmem imge)
    via the gen_memfile() method.

    NOTES.

    Key Accounting:
    As config object data is used, the key/value pairs are removed once no longer needed.
    This allows us to check that all config data has been parsed by calling the
    method _check_unused_keys(), which will raise a RuntimeError if the passed dict is
    not empty when we expect it to be.
    """

    def __init__(self,
                 lc_state_config: dict,
                 otp_mmap_config: dict,
                 img_config: dict,
                 data_perm: list[int]):
        """Constructs the OTP Memory Image object from a number of configuration dicts."""

        # Validate & Initialize base OTP memory map
        super().__init__(otp_mmap_config)
        super().gen_mmap_random_constants()

        # Initialize the LC state object
        self.lc_state = LcStEnc(lc_state_config)
        self.lc_state.generate_random_constants()
        _add_bitness_to_secded(self.lc_state.config['secded'])

        # Encryption smoke test with known test vector
        assert _present_64bit_encrypt(
            0x0123456789abcdef, 0x0123456789abcdef0123456789abcdef) \
            == 0x0e9d28685e671dd6, 'Encryption module test failed'

        ############################
        # VALIDATE INITIAL IMG_CFG #
        ############################

        log.debug('')
        log.debug('Checking OTP image config object...')

        otp_width = self.config['otp']['width'] * 8
        secded_width = self.lc_state.config['secded']['data_width']
        if otp_width != secded_width:
            raise RuntimeError('OTP width and SECDED data width must be equal')
        if 'seed' not in img_config:
            raise RuntimeError('Missing seed in configuration.')

        # Validate the data permutation option before using it during
        # image generation.
        self._validate_data_perm(data_perm)

        #################
        # INITIAL MERGE #
        #################

        log.debug(f"Merging partition data from the initial OTP Image Config object.")
        self._merge_parts(img_config)

        self.img_config = img_config

        # Key accounting
        img_config_check = img_config.copy()
        del img_config_check['seed']
        del img_config_check['partitions']
        _check_unused_keys(img_config_check, 'in image config')

        log.debug('')
        log.debug('Parse and merge OTP image successfully completed.')

    def _validate_data_perm(self, data_perm: list[int]) -> None:
        """Validate a given data permutation option."""

        # Byte aligned total width after adding ECC bits
        secded_cfg = self.lc_state.config['secded']
        raw_bitlen = secded_cfg['data_width'] + secded_cfg['ecc_width']
        total_bitlen = ((raw_bitlen + 7) // 8) * 8

        # If the permutation is undefined, use the default (identity) mapping.
        identity_perm = list(range(total_bitlen))
        self.data_perm = identity_perm if not data_perm else data_perm

        common.validate_data_perm_option(total_bitlen, self.data_perm)

    def _get_lifecycle_partition_values(self, part: dict) -> None:
        """Use the LcStEnc object to get the encodings for the LC partition values.

        Add these values as new partition 'items' in the input dictionary.
        """

        part.setdefault('state', 'RAW')
        part.setdefault('count', 0)
        part['count'] = common.check_int(part['count'])

        # Validate configuration
        if len(part['items']) > 0:
            raise RuntimeError(
                'Life cycle items cannot directly be overridden')
        if part['lock']:
            raise RuntimeError('Life cycle partition cannot be locked')
        if part['count'] == 0 and part['state'] != "RAW":
            raise RuntimeError(
                'Life cycle transition counter can only be zero in the RAW state')

        # Get the correct encodings, and add them as the partition 'items'
        state = self.lc_state.encode('lc_state', str(part['state']))
        count = self.lc_state.encode('lc_cnt', str(part['count']))
        part['items'] = [
            {
                'name': 'LC_STATE',
                'value': '0x{:X}'.format(state)
            },
            {
                'name': 'LC_TRANSITION_CNT',
                'value': '0x{:X}'.format(count)
            }
        ]


    def _merge_item_data(self, part: dict, item: dict) -> None:
        """Validate and merge the OTP partition item value into the OTP config dict."""

        item.setdefault('name', 'unknown_name')

        # Item must already exist in the base mmap!
        mmap_item = self.get_item(part['name'], item['name'])
        if mmap_item is None:
            raise RuntimeError('Item {} does not exist'.format(item['name']))

        item_size = mmap_item['size']
        item_width = item_size * 8

        # Helper method to print the value of non-mubi fields
        # - Print out max 64bit per line
        def _value_str() -> str:
            log_str_lines = []
            fmt_str = '{:0' + str(item_size * 2) + 'x}'
            value_str = fmt_str.format(item['value'])
            bytes_per_line = 8
            j = 0
            while value_str:
                line_str = ''
                for k in range(bytes_per_line):
                    num_chars = min(len(value_str), 2)
                    line_str += value_str[-num_chars:]
                    if k < bytes_per_line - 1:
                        line_str += ' '
                    value_str = value_str[:len(value_str) - num_chars]
                log_str_lines.append('  {:06x}: '.format(j) + line_str)
                j += bytes_per_line

            return '\n'.join(log_str_lines)

        # If needed, resolve the mubi value first
        # If not a mubi item, set a default value of 0x0 (if value not already given)
        if mmap_item['ismubi']:
            item.setdefault("value", "false")
            item["value"] = common.check_bool(item["value"])
            pre_str = "mubi "
            val_str = \
                f" kMultiBitBool{item_width}{'True' if item['value'] else 'False'}"
            item["value"] = mubi_value_as_int(item["value"], item_width)
        else:
            item.setdefault('value', '0x0')
            pre_str = ""
            val_str = '\n' + _value_str()

        # Log the value of the item.
        log.debug('> Adding {}item {} with size {}B and value{}:'.format(
            pre_str, item['name'], item_size, val_str))

        # Add the item data into the base OTP mmap dict.
        mmap_item['value'] = item['value']

        # Key accounting
        item_check = item.copy()
        del item_check['name']
        del item_check['value']
        _check_unused_keys(item_check, 'in item {}'.format(item['name']))

    def _merge_part_data(self, part):
        """Validate and merge the partition attributes into the config dict.

        If given the LC partition, this method also adds values for the
        lifecycle state / count.
        """

        log.debug(f"Merging values into the '{part['name']}' partition.")

        part.setdefault('name', 'unknown_name')
        part.setdefault('items', [])
        part.setdefault('lock', 'false')

        # Validate
        mmap_part = self.get_part(part['name'])
        if mmap_part is None:
            raise RuntimeError(f"Partition {part['name']} does not exist")
        if not isinstance(part['items'], list):
            raise RuntimeError('the "items" key must contain a list')

        # Augment memory map datastructure with lock bit.
        part['lock'] = common.check_bool(part['lock'])
        mmap_part['lock'] = part['lock']
        if part['lock'] and not mmap_part['hw_digest']:
            raise RuntimeError(
                f"Partition {part['name']} was marked as 'locked' in the image "
                "configuration, but does not contain a hardware digest."
                "Only partitions with a hardware digest can be locked.")

        # If this is the life_cycle partition, get the state encodings for each
        # item.
        if part['name'] == 'LIFE_CYCLE':
            self._get_lifecycle_partition_values(part)

            # Key accounting
            part_check = part.copy()
            del part_check['state']
            del part_check['count']

        else:
            # Key accounting
            part_check = part.copy()
            if len(part['items']) == 0:
                log.warning("Partition does not contain any items.")

        # Key accounting
        del part_check['items']
        del part_check['name']
        del part_check['lock']
        _check_unused_keys(part_check, "in partition {}".format(part['name']))

    def _merge_parts(self, img_config) -> None:
        """Validate and merge all partition data items in the OTP memory config."""

        if 'partitions' not in img_config:
            raise RuntimeError('Missing partitions key in configuration.')

        if not isinstance(img_config['partitions'], list):
            raise RuntimeError('The "partitions" key must contain a list')

        # Walk all partition/item data and validate/merge
        for part in img_config['partitions']:
            self._merge_part_data(part)
            for item in part['items']:
                self._merge_item_data(part, item)

    def _streamout_partition(self, part: dict) -> tuple[list[int], list[str]]:
        """Scramble and stream out partition data as a list of bytes.

        Returns:
            A tuple of (the raw data as a list of bytes,
                        the annotations, as a list of strings per byte).

        The annotation list can be used to print out informative comments
        in the memory hex file.
        """

        part_name = part['name']
        part_offset = part['offset']
        part_size = part['size']
        assert part_size % 8 == 0, 'Partition must be 64bit aligned'

        log.debug(f"Streaming out partition '{part_name}'")

        # Annotation is propagated into the MEM file as comments
        annotation = ['unallocated'] * part_size
        # Need to keep track of defined items for the scrambling.
        # Undefined regions are left blank (0x0) in the memory.
        defined = [False] * part_size

        # First chop up all partition items into individual bytes.
        data_bytes = [0] * part_size
        for item in part['items']:
            for k in range(item['size']):
                idx = item['offset'] - part_offset + k
                annotation[idx] = part_name + ': ' + item['name']
                if 'value' in item:
                    assert not defined[idx], "Unexpected item collision"
                    data_bytes[idx] = ((item['value'] >> (8 * k)) & 0xFF)
                    defined[idx] = True

        # Reshape bytes into 64bit blocks (this must be aligned at this point)
        assert len(data_bytes) % 8 == 0, 'data_bytes must be 64bit aligned'
        data_blocks = []
        data_block_defined = []
        for k, b in enumerate(data_bytes):
            if (k % 8) == 0:
                data_blocks.append(b)
                data_block_defined.append(defined[k])
            else:
                data_blocks[k // 8] += (b << 8 * (k % 8))
                # If any of the individual bytes are defined, the
                # whole block is considered defined.
                data_block_defined[k // 8] |= defined[k]

        # Check if scrambling is needed
        if part['secret']:
            key_sel = part['key_sel']
            log.debug(f"> Scramble partition {part_name} with key '{key_sel}'")

            # Get scrambling key for this partition
            try:
                key = next(filter(lambda key: key['name'] == key_sel,
                                  self.config['scrambling']['keys']))
            else:
                raise RuntimeError(f"Scrambling key '{key_sel}' cannot be found.")

            # Scramble all blocks in partition
            for k in range(len(data_blocks)):
                if data_block_defined[k]:
                    data_blocks[k] = _present_64bit_encrypt(
                        data_blocks[k], key['value'])

        # Check if a 'hw_digest' partition should have it's digest pre-generated
        # This is controlled by setting the 'lock' attribute to 'True'.
        # If so, calculate the digest
        if part['hw_digest']:

            # Make sure that the digest has not been overridden manually in the
            # image config file / image config overlay
            # (Digest is stored in last block of a partition)
            if data_blocks[-1] != 0:
                raise RuntimeError(
                    f"Partition {part_name} is a 'hw_digest' partition, and hence "
                    "the digest value should not be overridden manually in an "
                    "OTP Image file.\n The OTP preload generation script will automatically "
                    "calculate and insert the digest value if the partition is marked "
                    "as locked.")

            if part.setdefault('lock', False):
                log.debug('> Locking partition by computing digest.')

                # Get the consistency digest constants
                digestcfg = next(filter(lambda cfg: cfg['name'] == "CnstyDigest",
                                        self.config['scrambling']['digests']))
                iv = digestcfg['iv_value']
                const = digestcfg['cnst_value']

                data_blocks[-1] = \
                    _present_64bit_digest(data_blocks[0:-1], iv, const)
            else:
                log.debug(
                    '> Partition is not locked, hence no digest is computed.')

        # Convert to a list of bytes to make final packing into
        # OTP memory words independent of the cipher block size.
        data = []
        for block in data_blocks:
            for k in range(8):
                data.append((block >> (8 * k)) & 0xFF)

        # Make sure this has the right size
        assert len(data) == part['size'], 'Partition size mismatch'

        return data, annotation

    def apply_override_img_config(self, img_config: dict) -> None:
        """Override the value of specific partition items from an overlay configuration dict.

        This method allows specific fields of an existing MemImg to be modified,
        as the final value of any specific field is defined by the last applied
        override to modify the value.
        """

        log.debug(f"Merging partition data from an override OTP Image Config object.")
        self._merge_parts(img_config)

        # Key accounting
        img_config_check = img_config.copy()
        del img_config_check['partitions']
        _check_unused_keys(img_config_check, 'in image config')

    def gen_random_constants(self) -> None:
        """Initialize the RNG, and use it to generate any parition item random values."""

        rng_seed = check_int(self.config["seed"])

        # (Re-)Initialize the RNG.
        sp.reseed(OTP_SEED_DIVERSIFIER + rng_seed)
        log.debug('RNG Seed: {0:x}'.format(rng_seed))
        log.debug('')

        # Use the initialized RNG to generate random values for all '<random>' values.
        for part in self.img_config['partitions']:
            for item in part['items']:
                mmap_item = self.get_item(part['name'], item['name'])
                item_size = mmap_item['size']
                item_width = item_size * 8
                if not mmap_item['ismubi']:
                    common.random_or_hexvalue(item, 'value', item_width)
                    mmap_item['value'] = item['value']

    def gen_memfile(self) -> str:
        """Generate the contents of a memory image in .vmem file format

        Returns:
            The memfile contents
        """

        log.debug('Generating MEM file contents now.')
        log.debug('')
        log.debug('Streaming out partition data...')
        log.debug('')

        otp_size = self.config['otp']['size']

        # Iterate over all partitions, and stream out their raw contents
        # as a list of bytes.
        data = [0] * otp_size
        annotation = [''] * otp_size
        for part in self.config['partitions']:
            assert part['offset'] <= otp_size, \
                'Partition offset out of bounds'
            # Stream out partition data
            part_data, part_annotation = self._streamout_partition(part)
            # Assemble data into the final image array via their offsets
            idx_low = part['offset']
            idx_high = part['offset'] + part['size']
            data[idx_low:idx_high] = part_data
            annotation[idx_low:idx_high] = part_annotation

        log.debug('')
        log.debug('Streamout of partition data successfully completed.')

        # Smoke checks
        assert len(data) <= otp_size, 'Data size mismatch'
        assert len(annotation) <= otp_size, 'Annotation size mismatch'
        assert len(data) == len(annotation), 'Data/Annotation size mismatch'

        return _to_memfile_with_ecc(data, annotation, self.lc_state.config["secded"],
                                    self.data_perm)

    def generate_c_file(self, fileheader: str, templatefile: Path) -> str:
        """Generates C file with provided `header` and `templatefile`.

        Args:
            fileheader: Header to be appended to autogenerated file.
            templatefile: Mako template used to generate header file.

        Returns:
            Generated file in string format.
        """
        data = {}
        for part in self.config['partitions']:
            if part['name'] in _OTP_SW_SKIP_FROM_HEADER:
                continue
            items = []
            for item in part["items"]:
                if 'value' not in item.keys():
                    continue

                alignment = _OTP_SW_WRITE_BYTE_ALIGNMENT[part['name']]

                # TODO: Handle aggregation of fields to match write boundary.
                if item['size'] < alignment:
                    continue
                assert (item['size'] %
                        alignment) == 0, "invalid field alignment"

                # TODO: this is a bug in how reggen generates parameter defines
                item_offset_name = item["name"] + "_OFFSET"
                if item_offset_name == "ROT_CREATOR_AUTH_CODESIGN_BLOCK_SHA2_256_HASH_OFFSET":
                    item_offset_name = "ROTCREATORAUTHCODESIGNBLOCKSHA2_256HASHOFFSET"

                items.append({
                    'name': item['name'],
                    'offset_name': item_offset_name,
                    'values': _int_to_hex_array(item['value'], item['size'], alignment),
                    'ismubi': item['ismubi'],
                    'num_items': item['size'] / alignment,
                })
                items.append(item)

            if len(items):
                data[part['name']] = {
                    'alignment': alignment,
                    'items': items,
                }

        with open(templatefile, 'r') as tplfile:
            tpl = Template(tplfile.read())
            result = tpl.render(fileheader=fileheader, data=data)

        return result
