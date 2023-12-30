#!/usr/bin/env python3
# Copyright lowRISC contributors.
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
from pathlib import Path, PurePath

from mdbook import difgen
from mdbook import utils as md_utils


def main() -> None:
    md_utils.supports_html_only()

    # load both the context and the book from stdin
    context, book = json.load(sys.stdin)
    book_root = Path(context["root"])

    try:
        site_url = PurePath(context["config"]["output"]["html"]["site-url"])
    except KeyError:
        site_url = PurePath("/")

    try:
        preproc_cfg = context["config"]["preprocessor"]["doxygen"]
        xml_dir = Path(preproc_cfg["xml-dir"])
        html_url = preproc_cfg["html-url"]
        dif_src_regex = re.compile(preproc_cfg["dif-src-py-regex"])
    except KeyError:
        sys.exit(
            "mdbook_doxygen.py requires are set in the book.toml configuration.\n"
            "\tpreprocessor.reggen.xml-dir -- The build directory where the API_XML output has been generated.\n"
            "\tpreprocessor.reggen.html-url -- The final url where Doxygen's html output is hosted.\n"
            "\tpreprocessor.reggen.dif-src-py-regex -- A regex for identifying dif files.\n"
        )
    combined_xml = difgen.get_combined_xml(xml_dir)

    header_files = set()
    for chapter in md_utils.chapters(book["sections"]):
        src_path = chapter["source_path"]
        if src_path is None or dif_src_regex.search(src_path) is None:
            continue

        file_name = Path(src_path).name

        buffer = io.StringIO()
        buffer.write(f"# {file_name}\n")
        difgen.gen_listing_html(
            html_url=html_url,
            combined_xml=combined_xml,
            dif_header=str(src_path),
            dif_listings_html=buffer)
        buffer.write(
            "\n<details><summary>\nGenerated from <a href=\"{}\">{}</a></summary>\n"
            .format(
                site_url / src_path,
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

    for chapter in md_utils.chapters(book["sections"]):
        if chapter["source_path"] is None:
            continue
        page_path = Path(chapter["source_path"]).parent

        chapter["content"] = md_utils.change_link_ext(
            header_files,
            chapter["content"],
            "_h.html",
            book_root,
            page_path,
        )

    # dump the book into stdout
    print(json.dumps(book))


if __name__ == "__main__":
    main()
