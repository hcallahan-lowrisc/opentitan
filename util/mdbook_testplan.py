#!/usr/bin/env python3
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""mdbook preprocessor that generates testplans for the ip blocks.

The preprocessor finds testplans in SUMMARY.md and converts them into a html document.
"""

import json
import sys
import re
import io
from pathlib import Path

from mdbook import utils as md_utils
import dvsim.Testplan as Testplan


def gen_testplan_md(context: dict, book: dict) -> None:
    book_root = Path(context["root"])

    try:
        testplan_str = context["config"]["preprocessor"]["testplan"]["testplan-py-regex"]
        testplan_pattern = re.compile(testplan_str)
    except KeyError:
        sys.exit(
            "No RegEx pattern given in book.toml to identify testplan files.\n"
            "Provide regex as preprocessor.testplan.testplan-py-regex .",
        )

    testplan_files = set()
    for chapter in md_utils.chapters(book):
        src_path = Path(chapter["source_path"])
        if not testplan_pattern.search(str(src_path)):
            continue

        # Testplan prints to stdout, redirect that to stderr for error messages
        from contextlib import redirect_stdout
        with redirect_stdout(sys.stderr):
            plan = Testplan.Testplan(
                book_root / src_path,
                repo_top = book_root)
            buffer = io.StringIO()
            plan.write_testplan_doc(buffer)
            chapter["content"] = buffer.getvalue()

        testplan_files.add(src_path)

    for chapter in md_utils.chapters(book):
        src_path = Path(chapter["source_path"])
        src_dir = src_path.parent

        chapter["content"] = md_utils.change_link_ext(
            testplan_files,
            chapter["content"],
            ".html",
            book_root,
            src_dir,
        )


if __name__ == "__main__":
    # First preprocessor invocation - check if renderer is supported
    md_utils.supports_html_only(sys.argv)
    # Second preprocessor invocation - book json passed via stdin, updated content output to stdout
    with md_utils.Mdbook_Context(sys.stdin) as (context, book):
        gen_testplan_md(context, book)
