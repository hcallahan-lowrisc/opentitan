#!/usr/bin/env python3
# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""mdBook preprocessor that inserts bazel stardoc pages into an mdBook.

The preprocessor discovers *.bzl files in SUMMARY.md and builds existing stardoc rule targets
for those pages into markdown which is inserted into the book.
"""

import sys
import re
import io
from pathlib import Path
from typing import List
import subprocess

from mdbook import utils as md_utils

BAZEL_COMMON_CQUERY_FLAGS = ["--ui_event_filters=-info",
                             "--noshow_progress"]

class BazelRunner:
    """A collection of functions useful for running Bazel operations."""

    def __init__(self):
        self.cmd = ""
        self.cwd = ""
        self.cquery_opts_common = BAZEL_COMMON_CQUERY_FLAGS

    def build(self, labels: list[str], opts: list[str] = []) -> None:
        build_cmd = (
            self.cmd,
            "build",
            *labels,
            *opts,
        )
        self._run_cmd(build_cmd)

    def query(self, label: str, opts: list[str]) -> list[str]:
        query_cmd = (
            self.cmd,
            "query",
            label,
            *self.cquery_opts_common,
            *opts,
        )
        return self._run_cmd(query_cmd)

    def cquery(self, label: str, opts: list[str]) -> list[str]:
        cquery_cmd = (
            self.cmd,
            "cquery",
            label,
            *opts,
        )
        return self._run_cmd(cquery_cmd)

    def _run_cmd(self, cmd: list[str]) -> list[str]:
        """Run a single subprocess command.

        Returns:
            Each (non-empty) line of the stdout as a list of strings.
        """

        cmd = [x for x in cmd if x]  # Remove empty strings

        res = subprocess.run(cmd, cwd=self.cwd, capture_output=True, encoding='utf-8', text=True)

        if res.returncode != 0:
            print(res.stdout, flush=True, file=sys.stderr)
            print(res.stderr, flush=True, file=sys.stderr)
            sys.exit(f"_run_cmd -> had a non-zero return code of {res.returncode}.")

        stdout_lines = res.stdout.split('\n')
        return [s for s in stdout_lines if s]


def gen_stardoc_md(context: dict, book: dict) -> None:
    """Add stardoc-built markdown into an mdbook for chapters which point to .bzl files.

    This implementation modifies the mdbook 'book' dict in-place to add the bazel-built stardoc
    markdown to chapters which have .bzl files as their source paths.
    """
    # Setup the bazel runner for building and querying later.
    br = BazelRunner()
    br.cmd = "bazel"
    br.cwd = Path(context['root'])

    # List of chapter source paths (.bzl files) which are transformed into stardoc-generated content.
    cfg_files: List[Path] = []
    # Set of label-chapter pairs for which book chapter content will be replaced with the stardoc markdown.
    build_targets: dict[str, dict] = {}

    # First, iterate over the chapters to find all .bzl files
    for chapter in md_utils.chapters(book):

        # Determine if this chapter is a .bzl file
        src_path = Path(chapter["source_path"])
        if not src_path.suffix == ".bzl":
            continue

        # Add path to list for later link-rewriting step.
        cfg_files.append(src_path)

        # Determine the label of the expected stardoc target for this .bzl file
        build_file = Path(context['root']) / src_path.parent / 'BUILD'
        assert build_file.exists(), "BUILD file expected to contain stardoc target does not exist!"
        stardoc_label = f"//{src_path.parent}:{src_path.stem}-doc"
        # Add it to this dict to be built later
        build_targets[stardoc_label] = chapter

    # Next, build all stardoc markdown files using the list of labels
    # Note. if the expected stardoc target for any .bzl file does not exist, we will fail here.
    br.build(build_targets)

    # Now, get the generated stardoc .md and insert it into the book content
    for label, chapter in build_targets.items():
        # Get the generated .md file built by stardoc
        starlark_list = "[f.path for f in target.files.to_list() if f.path.endswith('.md')]"
        starlark_expr = f"--starlark:expr='\\n'.join({starlark_list})"
        mdfiles = br.cquery(label, ["--output=starlark", starlark_expr])
        assert len(mdfiles) == 1, "More than one file returned from output query."
        mdfile = Path(context['root']) / Path(mdfiles[0])

        # Place the generated .md into the chapter content
        chapter["content"] = mdfile.resolve().read_text()

    # Finally, we need to go through all book content and rewrite any markdown links
    # to the .bzl files to now point to the corresponding generated .html file.
    for chapter in md_utils.chapters(book):
        src_path = Path(chapter["source_path"])
        src_dir = src_path.parent

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
        gen_stardoc_md(context, book)
