#!/usr/bin/env python3
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""mdbook preprocessor that adds an overview to linked header files.

This overview holds links to the generated doxygen api documentation
as well as the actual file.
"""
import io
import json
import re
import sys
from pathlib import Path

from mdbook import difgen
from mdbook import utils as md_utils

SRCTREE_TOP = Path(__file__).parents[1].resolve()


def gen_doxygen_md(context: dict, book: dict) -> None:

    # First, get the preprocessor configuration options from book.toml
    try:
        preproc_cfg = context["config"]["preprocessor"]["doxygen"]
        out_dir = SRCTREE_TOP / preproc_cfg["out-dir"]
        html_out_dir = "/" + preproc_cfg["html-out-dir"]
        dif_src_regex = re.compile(preproc_cfg["dif-src-py-regex"])
    except KeyError:
        sys.exit(
            "mdbook_doxygen.py requires are set in the book.toml configuration.\n"
            "\tpreprocessor.reggen.out-dir -- Doxygen's output directory.\n"
            "\tpreprocessor.reggen.html-out-dir -- Doxygen's html out directory.\n"
            "\tpreprocessor.reggen.dif-src-py-regex -- A regex for identifying dif files.\n"
        )

    combined_xml = difgen.get_combined_xml(out_dir / 'api-xml')

    header_files = set()
    for chapter in md_utils.chapters(book):
        src_path = chapter["source_path"]
        if dif_src_regex.search(src_path) is None:
            continue

        file_name = Path(src_path).name

        buffer = io.StringIO()
        buffer.write(f"# {file_name}\n")
        difgen.gen_listing_html(html_out_dir, combined_xml, src_path, buffer)
        buffer.write(
            "\n<details><summary>\nGenerated from <a href=\"{}\">{}</a></summary>\n"
            .format(
                file_name,
                file_name,
            ),
        )
        buffer.write("\n```c\n{}\n```\n".format(chapter["content"]))
        buffer.write("</details>")
        chapter["content"] = buffer.getvalue()

        # Rewrite path so `dif_*.h` files don't collide with `dif_*.md` files.
        if Path(chapter["path"]).suffix == ".h":
            chapter["path"] = str(Path(chapter["path"]).with_suffix(""))
        chapter["path"] = chapter["path"] + "_h.html"

        header_files.add(Path(src_path))

    for chapter in md_utils.chapters(book):
        src_path = Path(chapter["source_path"])
        page_path = src_path.parent

        chapter["content"] = md_utils.change_link_ext(
            header_files,
            chapter["content"],
            "_h.html",
            Path(context["root"]),
            page_path,
        )


if __name__ == "__main__":
    # First preprocessor invocation - check if renderer is supported
    md_utils.supports_html_only(sys.argv)
    # Second preprocessor invocation - book json passed via stdin, updated content output to stdout
    with md_utils.Mdbook_Context(sys.stdin) as (context, book):
        gen_doxygen_md(context, book)
