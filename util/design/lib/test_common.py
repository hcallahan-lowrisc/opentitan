# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

import pytest
from pytest_mock import MockerFixture
from hamcrest import assert_that, calling, equal_to, raises

import common

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
    ('001100', [0, 1, 2, 3, 4, 5], '001100'),
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
