# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Common utilities used by mdbook pre-processors."""

import json
import sys
import re
from os import path
from io import TextIOWrapper
from typing import List, Any, Dict, Generator, Set
from pathlib import Path

# regex for a markdown link
# e.g.
#  - [the dev dependencies](docs.md#appendix)
#     <-----link_text---->  <-url-><-frag-->
LINK_PATTERN_STR = r"\[(?P<link_text>.*?)\]\((?P<url>[^#\?\)]*)(?P<frag>.*?)\)"
LINK_PATTERN = re.compile(LINK_PATTERN_STR)


def change_link_ext(
        file_list: Set[Path],
        content: str,
        new_suffix: str,
        book_root: Path,
        page_path: Path,
) -> str:
    """Update all links in a markdown string pointing to a set of paths to have a new extension suffix.

    This function is intended to supplement preprocessors which take a non-markdown source
    file and transform it in some way into markdown that is then rendered by mdbook.
    Inline links in non-generated markdown can use the non-markdown source-file as the
    url link-target (often just a file in the tree), and this function can then re-write
    the url in these links to now point into the generated content.

    Args
        file_list (Set[Path]):  A set of paths of link-targets that should be rewritten.
        content (str):          The raw markdown page content.
        new_suffix (str):       The new suffix for all links to be modified.
        book_root (Path):       The path of the book root.
        page_path (Path):       The path of the parent-page of the provided content.

    Returns
        A modified version of 'content' with all links matching the above criteria
        replaced with their new values.
    """

    def suffix_swap(m: re.Match) -> str:
        unmodified_match = m.group(0)

        # Try to get the 
        # - If it’s impossible, a ValueError is raised (e.g. not a local link)
        #   ... so just return the entire unomdified link re match.
        try:
            link_path = (book_root / page_path / m.group('url')).resolve()
            book_relative_path = link_path.relative_to(book_root)
        except ValueError:
            return unmodified_match

        # If the calculated relative path matches one of the files we passed as
        # requiring their links to be updated, then update the link string.
        if book_relative_path not in file_list:
            # Just return the entire unomdified link re match.
            return unmodified_match
        else:
            # Return a new .md link string with the modified extension
            url_root, _ = path.splitext(m.group('url'))
            new_link = "[{}]({}{}{})".format(
                m.group('link_text'),
                url_root,
                new_suffix,
                m.group('frag'),
            )
            return new_link

    return LINK_PATTERN.sub(suffix_swap, content)


def supports_html_only(argv: list[str]) -> None:
    """Handle the first preprocessor execution phase by indicating support for the HTML renderer only.

    https://rust-lang.github.io/mdBook/for_developers/preprocessors.html#hooking-into-mdbook
    """
    if len(argv) > 2:
        if (argv[1], argv[2]) == ("supports", "html"):
            sys.exit(0)
        else:
            sys.exit(1)


def chapters(book: Dict[str, Any], ignore_draft: bool = True) -> Generator[Dict[str, Any], None, None]:
    """Recursively yields all chapters objects in a mdbook object passed to the preprocessor stdin as JSON.

    This function is useful for preprocessors which may modify a chapter's content.

    https://docs.rs/mdbook/latest/mdbook/book/struct.Chapter.html
    """
    # If the input is a top-level Book (containing the field 'sections'), then return sections (a list of BookItems).
    # Otherwise, we have been passed an existing chapter/book to recurse into, which contains a 'sub_items' field.
    items = book.get("sections") or book.get("sub_items")
    chapters_list = (item.get("Chapter") for item in items)

    for chapter in chapters_list:
        if not chapter:
            continue

        # Before yielding the chapter, recurse into and yield the sub_chapters first (if there any any)
        for sub_chapter in chapters(chapter):
            yield sub_chapter

        # Only draft chapers can have an empty 'source_path' field.
        # We typically want to exclude these, as they have no content.
        if ignore_draft and not chapter["source_path"]:
            continue

        yield chapter


class Mdbook_Context():
    """With-context handler to simplify implementations of mdbook preprocessors.

    Example:

    ```python
    if __name__ == "__main__":
        # First preprocessor invocation - check if renderer is supported
        md_utils.supports_html_only(sys.argv)
        # Second preprocessor invocation - book json passed via stdin, updated content output to stdout
        with md_utils.Mdbook_Context(sys.stdin) as (context, book):
            # Modify the content/structure of 'book' to insert stardoc-generated .md
            gen_stardoc_md(context, book)
    ```
    """

    def __init__(self, mdbook_preprocessor_stdin: TextIOWrapper) -> None:
        self.stdin = mdbook_preprocessor_stdin

    def __enter__(self) -> tuple[dict, dict]:
        # Load both the context and the current book content from stdin
        self.context, self.book = json.load(self.stdin)
        # Return the parsed struct as two dicts for the with-context logic to modify.
        return (self.context, self.book)

    def __exit__(self, type, value, traceback) -> None:
        # Dump the updated book content back to stdout
        print(json.dumps(self.book))
