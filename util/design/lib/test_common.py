# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

import pytest
from pytest_mock import MockerFixture
from hamcrest import assert_that, calling, equal_to, raises

from typing import Union, Any
import common

################################################################################
#
# TODO
#
# - validate_data_perm_option
# - inverse_permute_bits
# - _try_convert_hex_str
# - random_or_hexvalue
#
################################################################################

# common.get_hd() test vectors
basic_checks = [
    ('0000', '0000', 0),
    ('1111', '1111', 0),
    ('100101', '010100', 3),
]
exception_checks = [
    # Mismatching word lengths
    ('010101', '0101010101', RuntimeError, 'Words are not of equal size'),
    # Forbid prefixed strings ('0b')
    ('10101', '0b101', ValueError, 'Words should not contain the "0b" prefix'),
]


class TestGetHd:
    """Test the method common.get_hd()"""

    @staticmethod
    @pytest.mark.parametrize(("word1", "word2", "expected"), basic_checks)
    def test_get_hd(
        word1: str,
        word2: str,
        expected: int,
    ) -> None:
        """"""
        assert_that(common.get_hd(word1, word2), equal_to(expected))

    @staticmethod
    @pytest.mark.parametrize(("word1", "word2", "exception", "match"), exception_checks)
    def test_get_hd_exceptions(
        word1: str,
        word2: str,
        exception: type[Exception],
        match: str,
    ) -> None:
        """"""
        assert_that(
            calling(common.get_hd).with_args(
                word1=word1,
                word2=word2,
            ),
            raises(exception, match),
        )


# common.blockify() test vectors
blockify_checks = [
    # Single line output
    ('0xa', (1 * 4), 16, "4'ha"),
    ('0x12345678', (8 * 4), 16, "32'h12345678"),
    ('0x3838383838383838383', (18 * 4), 64, "72'h38_38383838_38383838"),

    # Input strings without the '0x' decorator (added back before the refactor, for now)
    ('0xa', (1 * 4), 16, "4'ha"),
    ('0x12345678', (8 * 4), 16, "32'h12345678"),
    ('0x3838383838383838383', (19 * 4), 64, "76'h383_83838383_83838383"),

    # Multi line output (i.e. wrapping due to 'limit')
    ('0x66666666', (8 * 4), 2, "8'h66,\n  8'h66,\n  8'h66,\n  8'h66"),
    ('0x1234567812345678', (16 * 4), 8,
       "32'h12345678,\n  32'h12345678"),
    ('0x4848595960601221233234434554', (28 * 4), 32,
       "112'h4848_59596060_12212332_34434554"),
    ('0xb5ec66efe1fb7d3393dbaf8596279a7e6150e8d6691960fc1ab0d49fc6820c114bf6560ce605d75416c3db010e962a60ab335d5d375e3021d6702049', (120 * 4), 64,
       "224'hb5ec66ef_e1fb7d33_93dbaf85_96279a7e_6150e8d6_691960fc_1ab0d49f,\n  256'hc6820c11_4bf6560c_e605d754_16c3db01_0e962a60_ab335d5d_375e3021_d6702049"),
]

class TestBlockify:
    """Test the method common.blockify()"""

    @staticmethod
    @pytest.mark.parametrize(("s", "size", "limit", "expected"), blockify_checks)
    def test_blockify(
        s: str,
        size: int,
        limit: int,
        expected: str,
    ) -> None:
        assert_that(common.blockify(s, size, limit), equal_to(expected))

def mock_getrandbits(n: int) -> int:
    """Create a mock for random.getrandbits() that is repeatable for testing.

    This mock just uses the builtin random library, but always fixes the PRNG seed.
    """
    import random
    random.seed(0)
    ret = random.getrandbits(n)
    return ret

getrandomdatahexliteral_checks = [
    (4, "4'hd"),
    (32, "32'hd82c07cd"),
    (128, "128'he3e70682_c2094cac_629f6fbe_d82c07cd"),
    (256, "256'hf728b4fa_42485e3a_0a5d2f34_6baa9455_e3e70682_c2094cac_629f6fbe_d82c07cd"),
    (480, "224'h4da5e709_d4713d60_c8a70639_eb1167b3_67a9c378_7c65c1e5_82e2e662,\n  256'hf728b4fa_42485e3a_0a5d2f34_6baa9455_e3e70682_c2094cac_629f6fbe_d82c07cd"),
]

class TestGetRandomDataHexLiteral:
    """"""

    @staticmethod
    @pytest.mark.parametrize(("num_bits", "expected"), getrandomdatahexliteral_checks)
    def test_get_random_data_hex_literal(
            num_bits: int,
            expected: str,
            mocker: MockerFixture) -> None:
        mocker.patch("common.getrandbits", side_effect = mock_getrandbits)
        assert_that(common.get_random_data_hex_literal(num_bits), equal_to(expected))

def mock_shuffle(perm: list[int]) -> list[int]:
    """Create a mock for random.shuffle() that is repeatable for testing.

    This mock just reverses the order of the passed input array.
    """
    return perm.reverse()

getrandompermhexliteral_checks = [
    (4, "8'he4"),
    (16, "64'hfedcba98_76543210"),
    (96, "160'hbf7aedcb_76acd8af_5aad4a74_a8d09f3a_6cc972a4,\n  256'hc88f1a2c_4870a0c0_7ef9ebc7_6e9cb86e_d9ab466c_98b05eb9_6ac56a94_a84e992a,\n  256'h446890a0_3e78e9c3_668c982e_58a94264_88901e38_68c16284_880e1828_40608080"),
]

class TestGetRandomPermHexLiteral:
    """"""

    @staticmethod
    @pytest.mark.parametrize(("numel", "expected"), getrandompermhexliteral_checks)
    def test_get_random_perm_hex_literal(
            numel: int,
            expected: str,
            mocker: MockerFixture) -> None:
        mocker.patch("common.shuffle", side_effect = mock_shuffle)
        assert_that(common.get_random_perm_hex_literal(numel), equal_to(expected))

permutebits_checks = [
    # Basic Checks
    ('01', [1, 0], '10'),
    ('0011', [1, 2, 3, 0], '1001'),
    ('0110', [0, 1, 2, 3], '0110'), # Identity
    ('001100', [0, 1, 2, 3, 4, 5], '001100'), # Identity
    ('010100111111', range(12), '010100111111'),
    ('010100111111', list(range(12))[::-1] , '111111001010'), # Reverse-range
]

class TestPermuteBits:
    """"""

    @staticmethod
    @pytest.mark.parametrize(("bit_str", "permutation", "expected"), permutebits_checks)
    def test_permute_bits(
            bit_str: str,
            permutation: list[int],
            expected: str) -> None:
        assert_that(common.permute_bits(bit_str, permutation), equal_to(expected))


class TestCheckBool:
    """"""

    @staticmethod
    @pytest.mark.parametrize(
        ("x", "expected"),
        [
            (True, True),
            (False, False),
            ("true", True),
            ("True", True),
            ("False", False),
        ]
    )
    def test_check_bool(
            x: Union[bool, str],
            expected: bool) -> None:
        assert_that(common.check_bool(x), equal_to(expected))

    def cb_rte_err(x: str) -> str:
        return f"{x} is not a boolean value, and cannot be coerced."

    @staticmethod
    @pytest.mark.parametrize(
        ("x", "exception", "match"),
        [
            ("Puppuccino", RuntimeError, cb_rte_err("Puppuccino")),
            ("0xbeefca5e", RuntimeError, cb_rte_err("0xbeefca5e")),
            (1441, RuntimeError, cb_rte_err(1441)),
            ([1], RuntimeError, ".* is not a boolean value, and cannot be coerced."),
            ([1, 2, 3], RuntimeError, ".* is not a boolean value, and cannot be coerced."),
        ]
    )
    def test_check_bool_exceptions(
        x: Union[bool, str],
        exception: type[Exception],
        match: str,
    ) -> None:
        """"""
        assert_that(
            calling(common.check_bool).with_args(
                x=x,
            ),
            raises(exception, match),
        )


class TestCheckInt:
    """"""

    @staticmethod
    @pytest.mark.parametrize(
        ("x", "expected"),
        [
            (0, 0),
            (1, 1),
            (1024, 1024),
            ("0", 0),
            ("1", 1),
            ("99", 99),
            ("999", 999),
        ]
    )
    def test_check_int(
            x: Union[int, str],
            expected: int) -> None:
        assert_that(common.check_int(x), equal_to(expected))


    def ci_rte_not_dec(x: str) -> str:
        return f"{x} is a string but not a decimal number."

    def ci_rte_couldnt_convert(x: str) -> str:
        return f"Could not convert {x} to a decimal number using int()."

    @staticmethod
    @pytest.mark.parametrize(
        ("x", "exception", "match"),
        [
            # Not A Decimal Exception
            ("a", RuntimeError, ci_rte_not_dec("a")),
            ("pineapple", RuntimeError, ci_rte_not_dec("pineapple")),
            ("11a2", RuntimeError, ci_rte_not_dec("11a2")),
            ("32'habcdef12", RuntimeError, ci_rte_not_dec("32'habcdef12")),
            # Could Not Convert Exception
            ([1], RuntimeError, "Could not convert .* to a decimal number using int()."),
            (["a"], RuntimeError, "Could not convert .* to a decimal number using int()."),
            ({"a": 1}, RuntimeError, ci_rte_couldnt_convert({"a": 1})),
            ({"a": 1}, RuntimeError, ci_rte_couldnt_convert({"a": 1})),
        ]
    )
    def test_check_int_exceptions(
        x: Union[int, str],
        exception: type[Exception],
        match: str,
    ) -> None:
        """"""
        assert_that(
            calling(common.check_int).with_args(
                x=x,
            ),
            raises(exception, match),
        )


# SECDED matrix used for ECC in OTP
# (This is a standard extended Hamming code for 16bit)
TEST_SECDED_CFG = {
    "data_width" : 16,
    "ecc_width"  : 6,
    "ecc_matrix" : [
        [0, 1, 3, 4, 6, 8, 10, 11, 13, 15], # ECC bit 0
        [0, 2, 3, 5, 6, 9, 10, 12, 13],     # ECC bit 1
        [1, 2, 3, 7, 8, 9, 10, 14, 15],     # ECC bit 2
        [4, 5, 6, 7, 8, 9, 10],             # ECC bit 3
        [11, 12, 13, 14, 15],               # ECC bit 4
        [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20], # Parity bit
    ]
}


class TestEccEncode:
    """"""

    @staticmethod
    @pytest.mark.parametrize(
        ("dataword", "expected"),
        [
            # Basic Checks
            ("0000000000000000", "0000000000000000000000"),
            ("1111111111111111", "0111101111111111111111"),
            # Sample of valid words
            #                      ECC      dataword
            #                     <----><-------------->
            ("0110010010101110", "0010100110010010101110"),
            ("0000011110110100", "1001010000011110110100"),
            ("0011000111010010", "0001110011000111010010"),
            ("0010111001001101", "0010100010111001001101"),
            ("0100000111111000", "0110100100000111111000"),
            ("1010110010000101", "1100011010110010000101"),
            ("1001100110001100", "0101101001100110001100"),
            ("0101001100001111", "1000100101001100001111"),
            ("0111000101100000", "1110010111000101100000"),
            ("0010110001100011", "1010100010110001100011"),
        ]
    )
    def test_ecc_encode(
        dataword: str,
        expected: str,
    ) -> None:
        """"""
        assert_that(common.ecc_encode(TEST_SECDED_CFG, dataword), equal_to(expected))


    @staticmethod
    @pytest.mark.parametrize(
        ("dataword", "exception", "match"),
        [
            # Incorrect Codeword Length as per TEST_SECDED_CFG
            ("0", RuntimeError, f"Invalid codeword length .*"),
            ("1", RuntimeError, f"Invalid codeword length .*"),
            ("0000", RuntimeError, f"Invalid codeword length .*"),
            ("1111", RuntimeError, f"Invalid codeword length .*"),
            ("001011000110000", RuntimeError, f"Invalid codeword length .*"),
            ("00101100011000110", RuntimeError, f"Invalid codeword length .*"),
        ]
    )
    def test_ecc_encode_exceptions(
        dataword: int,
        exception: type[Exception],
        match: str,
    ) -> None:
        """"""
        assert_that(
            calling(common.ecc_encode).with_args(
                secded_cfg=TEST_SECDED_CFG,
                dataword=dataword,
            ),
            raises(exception, match),
        )


TEST_SECDED_CODEWORDS = [
    # <-------------->        DATA
    #                 <---->  ECC
    # Stuck-At
    ("0000000000000000000000", True),
    ("1111111111111111111111", False),
    ("0000000000000000111111", False),
    ("1111111111111111000000", False),
    # Sample of random codewords
    ("0101010101010101010101", False),
    ("1010101010101010101010", False),
    ("1111111111100000000000", False),
    ("0000000000011111111111", False),
    ("1111110000000001111111", False),
    ("0000001111111110000000", False),
    # Sample of generated codewords
    ("0010100110010010101110", True),
    ("1111100111010111101110", True),
    ("1001010000011110110100", True),
    ("1111010000111111111110", True),
    ("0001110011000111010010", True),
    ("0001110111101111111110", True),
    ("0010100010111001001101", True),
    ("1110100011111101101111", True),
    ("0110100100000111111000", True),
    ("0111100101111111111100", True),
]

class TestIsValidCodeword:
    """"""

    @staticmethod
    @pytest.mark.parametrize(("codeword", "expected"), TEST_SECDED_CODEWORDS)
    def test_is_valid_codeword(
        codeword: int,
        expected: bool,
    ) -> None:
        """"""
        assert_that(common.is_valid_codeword(TEST_SECDED_CFG, codeword), equal_to(expected))


    @staticmethod
    @pytest.mark.parametrize(
        ("codeword", "exception", "match"),
        [
            # Incorrect Codeword Length
            ("0000", RuntimeError, f"Invalid codeword length .*"),
            ("1111", RuntimeError, f"Invalid codeword length .*"),
            ("001010011001001010111", RuntimeError, f"Invalid codeword length .*"),
            ("00101001100100101011101", RuntimeError, f"Invalid codeword length .*"),
        ]
    )
    def test_is_valid_codeword_exceptions(
        codeword: int,
        exception: type[Exception],
        match: str,
    ) -> None:
        """"""
        assert_that(
            calling(common.is_valid_codeword).with_args(
                secded_cfg=TEST_SECDED_CFG,
                codeword=codeword,
            ),
            raises(exception, match),
        )


class TestScatterBits:
    """"""

    @staticmethod
    @pytest.mark.parametrize(
        ("mask", "bits", "expected"),
        [
            # Representative example mask + bits
            ("0110010010101110", "00001101", "0110010111101111"),
            ("0110010010101110", "00011110", "0110011111111110"),
            ("0110010010101110", "00100111", "0110110011111111"),
        ]
    )
    def test_scatter_bits(
        mask: str,
        bits: str,
        expected: str,
    ) -> None:
        """"""
        assert_that(common.scatter_bits(mask, bits), equal_to(expected))


    @staticmethod
    @pytest.mark.parametrize(
        ("mask", "bits", "exception", "match"),
        [
            # Too many bits for mask
            ("01", "11", AssertionError, "Mismatching bits size for given mask."),
            ("111111", "111", AssertionError, "Mismatching bits size for given mask."),
            # Too few bits for mask
            ("01", "", AssertionError, "Mismatching bits size for given mask."),
            ("0001", "11", AssertionError, "Mismatching bits size for given mask."),
            ("00011100", "1111", AssertionError, "Mismatching bits size for given mask."),
        ]
    )
    def test_scatter_bits_exceptions(
        mask: str,
        bits: str,
        exception: type[Exception],
        match: str,
    ) -> None:
        """"""
        assert_that(
            calling(common.scatter_bits).with_args(
                mask=mask,
                bits=bits,
            ),
            raises(exception, match),
        )
