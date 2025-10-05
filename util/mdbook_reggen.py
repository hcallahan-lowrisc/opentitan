#!/usr/bin/env python3
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""mdbook preprocessor that generates interface and register tables for ip blocks.

The preprocessor finds ip configs in SUMMARY.md and converts them into a html document
with tables for hardware interfaces and registers.
"""

import json
import sys
import re
import io
from pathlib import Path
from typing import List

from mdbook import utils as md_utils
from reggen.ip_block import IpBlock
import reggen.gen_cfg_md as gen_cfg_md
import reggen.gen_md as gen_md


def gen_reggen_md(context: dict, book: dict) -> None:
    # First get the regex pattern from the configuration .toml
    try:
        ip_cfg_str = \
            context["config"]["preprocessor"]["reggen"]["ip-cfg-py-regex"]
        ip_cfg_pattern = re.compile(ip_cfg_str)
    except KeyError:
        sys.exit(
            "No RegEx pattern given in book.toml to identify ip block configuration files.\n"
            "Provide regex as preprocessor.reggen.ip-cfg-py-regex .", )

    # List of chapter source paths which are transformed into reggen-generated content.
    cfg_files: List[Path] = []

    # First, find all chapters which have source-paths of IP Block .hjson files.
    for chapter in md_utils.chapters(book):
        src_path = chapter["source_path"]
        if not ip_cfg_pattern.search(src_path):
            continue

        # Add path to list for later link-rewriting step.
        cfg_files.append(Path(src_path))

        # Generate the new markdown page content from the IP Block .hjson.
        buffer = io.StringIO()
        block = IpBlock.from_text(
            txt=chapter["content"],
            param_defaults=[],
            where=f"file at {context['root']}/{chapter['source_path']}")
        buffer.write("# Hardware Interfaces\n")
        gen_cfg_md.gen_cfg_md(block, buffer)
        buffer.write("# Registers\n")
        gen_md.gen_md(block, buffer)
        chapter["content"] = buffer.getvalue()

    # Secondly, we need to go through all book content and rewrite any markdown links
    # to the IP Block .hjson file to now point to the corresponding generated .html file.
    for chapter in md_utils.chapters(book):
        src_dir = Path(chapter["source_path"]).parent

        chapter["content"] = md_utils.change_link_ext(
            cfg_files,
            chapter["content"],
            ".html",
            Path(context["root"]),
            src_dir,
        )


if __name__ == "__main__":
    # First preprocessor invocation - check if renderer is supported
    md_utils.supports_html_only(sys.argv)
    # Second preprocessor invocation - book json passed via stdin, updated content output to stdout
    with md_utils.Mdbook_Context(sys.stdin) as (context, book):
        gen_reggen_md(context, book)
