# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Common utilities used by various util/design scripts."""

import os
from random import getrandbits, shuffle
import re
import sys
import textwrap
import datetime
from math import ceil, log2
from pathlib import Path
from typing import Union, Any

sys.path.append(os.path.join(os.path.dirname(__file__), '../../'))

from topgen import secure_prng as sp  # noqa : E402

import logging
logger = logging.getLogger(__name__)

OUTFILE_HEADER_TPL = \
"""
// Generated on '{}' with the following cmd:
// $ {} {}
//
"""

def create_outfile_header(file, args) -> str:
    """Returns the file header to be inserted into generated output files.

    This prints the datetime and args for reference.
    """

    # Generate datetime string
    dt = datetime.datetime.now(datetime.timezone.utc)
    dtstr = dt.strftime("%a, %d %b %Y %H:%M:%S %Z")

    # Generate string of script arguments
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

    return OUTFILE_HEADER_TPL.format(dtstr, file, argstr).strip() + '\n'


def wrapped_docstring() -> str:
    """Return a text-wrapped version of a module's docstring."""
    paras = []
    para = []
    for line in __doc__.strip().split('\n'):
        line = line.strip()
        if not line:
            if para:
                paras.append('\n'.join(para))
                para = []
        else:
            para.append(line)
    if para:
        paras.append('\n'.join(para))

    return '\n\n'.join(textwrap.fill(p) for p in paras)


def check_bool(x: Union[bool, str]) -> bool:
    """Coerce input 'x' to a bool which may be either string: ["true", "false"]

    Raises:
        RuntimeError: if 'x' is not boolean or a valid string

    Returns:
        Value 'x' as Bool type.
    """
    if isinstance(x, bool):
        return x
    elif isinstance(x, str) and x.lower() in ["true", "false"]:
        return (x.lower() == "true")
    else:
        raise RuntimeError(f"{x} is not a boolean value, and cannot be coerced.")


def check_int(x: Union[int, str]) -> int:
    """Coerce input 'x' to an integer if it is a decimal string.

    Raises:
        RuntimeError: if 'x' is not a decimal string, or cannot be converted using int().

    Returns:
        'x' as an int type.
    """
    if isinstance(x, int):
        return x
    elif isinstance(x, str) and not x.isdecimal():
        raise RuntimeError(f"{x} is a string but not a decimal number.")
    else:
        # Try to convert to an integer using int(). Throw if this fails.
        x_int: int
        try:
            x_int = int(x)
        except Exception:
            raise RuntimeError(f"Could not convert {x} to a decimal number using int().")
        return x_int


def pascal_to_snake_case(pascal: str) -> str:
    """Convert PascalCase into snake_case.

    This method assumes, and does not check, that the input is already formatted in PascalCase.
    """
    snake: str = ""
    for c in pascal:
        if c.isupper() and len(snake) > 0:
            snake += '_'
        snake += c.lower()
    return snake + ('_' if pascal else '')


def blockify(s: str, size: int, limit: int) -> str:
    """Make sure the output does not exceed a certain size per line.


    """
    output_list: list[str] = []

    str_idx = 2
    remain = size % (limit * 4)
    numbits = remain if remain else limit * 4

    remain = size
    while remain > 0:
        s_incr = int(numbits / 4)
        string = s[str_idx:str_idx + s_incr]

        # Separate 32-bit words for readability.
        for i in range(s_incr - 1, 0, -1):
            if (s_incr - i) % 8 == 0:
                string = string[:i] + "_" + string[i:]

        # 
        output_list.append("{}'h{}".format(numbits, string))

        str_idx += s_incr
        remain -= numbits
        numbits = limit * 4

    return (",\n  ".join(output_list))


def get_random_data_hex_literal(num_bits: int) -> str:
    """Get 'num_bits' random bits and return them as hex-formatted literal.

    This function uses the python 'random' library to generate random bits,
    which uses a Mersenne Twister PRNG seeded with the current system time.

    The returned literal is 'blockified', which adds 
    """
    rnd_bits = getrandbits(num_bits)
    hex_literal = blockify(hex(rnd_bits), num_bits, 64)
    return hex_literal


def get_random_perm_hex_literal(numel) -> str:
    """Compute a random permutation of 'numel' elements and return as packed hex literal.

    This function uses the python 'random' library to randomize the permutation,
    which uses a Mersenne Twister PRNG seeded with the current system time.

    """
    num_elements = int(numel)
    width = int(ceil(log2(num_elements)))
    idx = [x for x in range(num_elements)]
    shuffle(idx)
    literal_str = ""
    for k in idx:
        literal_str += format(k, '0' + str(width) + 'b')
    # convert to hex for space efficiency
    literal_str = hex(int(literal_str, 2))
    return blockify(literal_str, width * numel, 64)


def hist_to_bars(hist, m) -> str:
    """Convert histogramm list into ASCII bar plot"""
    bars = []
    for i, j in enumerate(hist):
        bar_prefix = "{:2}: ".format(i)
        spaces = len(str(m)) - len(bar_prefix)
        hist_bar = bar_prefix + (" " * spaces)
        for k in range(j * 20 // max(hist)):
            hist_bar += "|"
        hist_bar += " ({:.2f}%)".format(100.0 * j / sum(hist)) if j else "--"
        bars += [hist_bar]
    return bars


def get_hd(word1: str, word2: str) -> int:
    """Calculate Hamming distance between two words."""
    if len(word1) != len(word2):
        raise RuntimeError('Words are not of equal size')
    # Python's int(n, 2) function will accept both strings of bits and
    # 0b-prefixed strings. This can lead to edge cases such as get_hd('1001',
    # '0b01'). We forbid the usage of "0b" with this function.
    if '0b' in word1 or '0b' in word2:
        raise ValueError('Words should not contain the "0b" prefix')
    return bin(int(word1, 2) ^ int(word2, 2)).count('1')


def hd_histogram(existing_words) -> dict:
    """Build Hamming distance histogram"""
    minimum_hd = len(existing_words[0])
    maximum_hd = 0
    minimum_hw = len(existing_words[0])
    maximum_hw = 0
    hist = [0] * (len(existing_words[0]) + 1)
    for i, j in enumerate(existing_words):
        minimum_hw = min(j.count('1'), minimum_hw)
        maximum_hw = max(j.count('1'), maximum_hw)
        if i < len(existing_words) - 1:
            for k in existing_words[i + 1:]:
                dist = get_hd(j, k)
                hist[dist] += 1
                minimum_hd = min(dist, minimum_hd)
                maximum_hd = max(dist, maximum_hd)

    stats = {}
    stats["hist"] = hist
    stats["bars"] = hist_to_bars(hist, len(existing_words))
    stats["min_hd"] = minimum_hd
    stats["max_hd"] = maximum_hd
    stats["min_hw"] = minimum_hw
    stats["max_hw"] = maximum_hw
    return stats


def is_valid_codeword(secded_cfg: dict, codeword: str) -> bool:
    """Checks whether the bitstring is a valid ECC codeword.


    Build a syndrome and check whether it is zero.
    """

    logger.info(f"is_valid_codeword(): secded_cfg={secded_cfg},codeword={codeword}")

    data_width = secded_cfg['data_width']
    ecc_width = secded_cfg['ecc_width']
    if len(codeword) != (data_width + ecc_width):
        raise RuntimeError(
            f"Invalid codeword length {len(codeword)} (expected {data_width + ecc_width})")

    syndrome = [0 for k in range(ecc_width)]
    # The bitstring must be formatted as "data bits[N-1:0]" + "ecc bits[M-1:0]".
    for j, fanin in enumerate(secded_cfg['ecc_matrix']):
        syndrome[j] = int(codeword[ecc_width - 1 - j])
        for k in fanin:
            syndrome[j] ^= int(codeword[ecc_width + data_width - 1 - k])
    is_valid = sum(syndrome) == 0

    return is_valid


def ecc_encode(secded_cfg: dict, dataword: str) -> str:
    """Calculate and prepend ECC bits."""
    if len(dataword) != secded_cfg['data_width']:
        raise RuntimeError(f"Invalid codeword length {len(dataword)}")

    # Note that certain codes like the Hamming code refer to previously
    # calculated parity bits. Hence, we incrementally build the codeword
    # and extend it such that previously calculated bits can be referenced.
    codeword = dataword
    for j, fanin in enumerate(secded_cfg['ecc_matrix']):
        bit = 0
        for k in fanin:
            bit ^= int(codeword[secded_cfg['data_width'] + j - 1 - k])
        codeword = str(bit) + codeword

    return codeword


def scatter_bits(mask, bits) -> str:
    """Scatter the bits into unset positions of mask."""
    j = 0
    scatterword = ''
    for b in mask:
        if b == '1':
            scatterword += '1'
        else:
            scatterword += bits[j]
            j += 1

    return scatterword


def validate_data_perm_option(word_bit_length: int, data_perm: list[int]) -> None:
    """Validate OTP data permutation option by checking for bijectivity."""
    if len(data_perm) != word_bit_length:
        raise RuntimeError(
            'Data permutation "{}" is not bijective, since '
            'it does not have the same length ({}) as the data.'.format(
                data_perm, word_bit_length))
    for k in data_perm:
        if k >= word_bit_length:
            raise RuntimeError('Data permutation "{}" is not bijective, '
                               'since the index {} is out of bounds.'.format(
                                   data_perm, k))
    if len(set(data_perm)) != word_bit_length:
        raise RuntimeError(
            'Data permutation "{}" is not bijective, '
            'since it contains duplicated indices.'.format(data_perm))


def inverse_permute_bits(bit_str: str, permutation: list[int]) -> str:
    """Un-permute the bits in a bitstring (inverse of `permute_bits()`)."""
    bit_str_len = len(bit_str)
    assert bit_str_len == len(permutation)
    bit_vector = ["0"] * bit_str_len
    for i, perm_idx in enumerate(permutation):
        bit_vector[bit_str_len - perm_idx - 1] = bit_str[bit_str_len - i - 1]
    return ''.join(bit_vector)


def permute_bits(bit_str: str, permutation: list[int]) -> str:
    """Permute the bits in a bitstring."""
    assert len(bit_str) == len(permutation)
    permword = ''
    for k in permutation:
        permword = bit_str[len(bit_str) - k - 1] + permword
    return permword


def _try_convert_hex_str(inp: Union[list[str], str], num_bits: int) -> int:
    """Parse a string-formatted hex word or list of 4B hex words into an integer.

    The input 'num_bits' captures the number of bits the resultant integer should be
    able to fit into. If the result does not fit into this many bits, something has
    gone wrong, so throw a RuntimeError.

    This function may be passed strings containing some unicode control characters or
    surrounding whitespace. Remove these characters first.

    Returns:
        The converted integer value of 'inp'.

    Example:
        _try_convert_hex_str(["0x10", "0x20"]) = int("0x2000000010", 16)
                                               = 137438953488
        _try_convert_hex_str("0x10101bb000000a5") = 72340971685150885
    """
    def _remove_control_chars_and_whitespace(s: str) -> str:
        """Remove some stray control characters and whitespace."""
        trans_map = str.maketrans('', '', ' \r\n\t')
        return s.translate(trans_map)

    result: int = 0

    if isinstance(inp, list):
        for (i, v) in enumerate(inp):
            s = _remove_control_chars_and_whitespace(v)
            int_w = int(s, 16)
            # Check each word is a maximum of 4B
            assert int_w < (1 << 32)
            result |= int_w << (i * 32)
    elif isinstance(inp, str):
        s = _remove_control_chars_and_whitespace(inp)
        result = int(s, 16)
    else:
        raise RuntimeError("Input 'inp' is of the incorrect type.")

    # Check that the returned integer can fit into 'num_bits'.
    assert result < (2**num_bits)

    return result


def random_or_hexvalue(dict_obj: dict, key: str, num_bits: int) -> bool:
    """Convert hex value at "key" to an integer or draw a random number.

    If the value is set to '<random>', generate a new randomized value
    with width 'num_bits'.
    This assumes the RNG ('sp') has been externally seeded.

    Raises:
        RuntimeError: if the existing value cannot be converted to an int.

    Returns:
        True if a new random number was drawn for the value at "key", otherwise False.
    """

    # Initialize to default if this key does not exist.
    dict_obj.setdefault(key, '0x0')
    val = dict_obj[key]

    logger.info(f'random_or_hexvalue(): val = {val}')

    # If the number is already an integer, nothing to do.
    if isinstance(val, int):
        return False

    # If '<random>', draw a new random number of 'num_bits' size.
    elif val == '<random>':
        dict_obj[key] = sp.getrandbits(num_bits)
        return True

    # Otherwise attempt to convert this value to an int.
    else:
        dict_obj[key] = _try_convert_hex_str(val, num_bits)
        return False


def vmem_permutation_string(data_perm) -> Union[str, list[str]]:
    """Check VMEM permutation format and expand the ranges."""

    if not isinstance(data_perm, str):
        raise TypeError()

    if not data_perm:
        return ""

    # Check the format first.
    pattern = r"^((?:\[[0-9]+:[0-9]+\])+(?:,\[[0-9]+:[0-9]+\])*)"
    match = re.fullmatch(pattern, data_perm)
    if match is None:
        raise ValueError()
    # Expand the ranges.
    expanded_perm = []
    groups = match.groups()
    for group in groups[0].split(","):
        k1, k0 = [int(x) for x in group[1:-1].split(":")]
        if k1 > k0:
            expanded_perm = list(range(k0, k1 + 1)) + expanded_perm
        else:
            expanded_perm = list(range(k0, k1 - 1, -1)) + expanded_perm

    return expanded_perm

