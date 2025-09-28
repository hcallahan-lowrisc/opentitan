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


