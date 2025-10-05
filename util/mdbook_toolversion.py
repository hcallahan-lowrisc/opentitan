#!/usr/bin/env python3
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
import json
import sys
import re
from pathlib import Path

from mdbook import utils as md_utils
sys.path.insert(0, str(Path(__file__).parents[1] / "hw"))
import check_tool_requirements  # noqa: E402

# We are looking to match on the following example strings
# {{#tool-version verible }}
TOOLVERSION_PATTERN = re.compile(r'\{\{#tool-version\s+(?P<version>.+?)\s*\}\}')


def gen_toolversion_md(context: dict, book: dict) -> None:
    tool_requirements = check_tool_requirements.read_tool_requirements()

    for chapter in md_utils.chapters(book):
        # Add in the minimum tool version(s)
        chapter['content'] = TOOLVERSION_PATTERN.sub(
            repl=lambda m: tool_requirements.get(m.group('version')).min_version,
            string=chapter['content'])


if __name__ == "__main__":
    # First preprocessor invocation - check if renderer is supported
    md_utils.supports_html_only(sys.argv)
    # Second preprocessor invocation - book json passed via stdin, updated content output to stdout
    with md_utils.Mdbook_Context(sys.stdin) as (context, book):
        gen_toolversion_md(context, book)
