# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

import pytest
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
    ('0xa', 16, "8'h10"),
    ('0x12345678', 16, "36'h3_05419896"),
    ('0x3838383838383838383', 64, "92'h1659309_94849066_74946947"),

    # Input string without the '0x' decorator
    ('a', 16, "8'h10"),
    ('12345678', 16, "36'h3_05419896"),
    ('3838383838383838383', 64, "92'h1659309_94849066_74946947"),

    # Multi line output (i.e. wrapping due to 'limit')
    ('0x66666666', 2, "8'h17,\n  8'h17,\n  8'h98,\n  8'h69,\n  8'h18"),
    ('0x1234567812345678', 8,
       "12'h131,\n  32'h17684651,\n  32'h73141112"),
    ('0x4848595960601221233234434554', 32,
       "8'h14,\n  128'h66065571_37933872_43946778_15166292"),
    ('0xb5ec66efe1fb7d3393dbaf8596279a7e6150e8d6691960fc1ab0d49fc6820c114bf6560ce605d75416c3db010e962a60ab335d5d375e3021d6702049', 64,
       "68'h2_21843458_15064031,\n  256'h84668764_94670308_04631812_31953035_70655036_06106877_89376508_08469879,\n  256'h52294239_94815873_05391186_79008623_37774288_68873584_92037217_41279305"),
]

class TestBlockify:
    """Test the method common.blockify()"""

    @staticmethod
    @pytest.mark.parametrize(("s", "limit", "expected"), blockify_checks)
    def test_blockify(
        s: str,
        limit: int,
        expected: str,
    ) -> None:
        assert_that(common.blockify(s, limit), equal_to(expected))


