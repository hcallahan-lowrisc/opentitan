# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

package(default_visibility = ["//visibility:public"])

# Use --config=nix to select a platform which meets these constraints

py_binary(
    name = "hello",
    srcs = ["hello.py"],
    main = "hello.py",
    exec_compatible_with = [
        "@io_tweag_rules_nixpkgs//nixpkgs/constraints:support_nix",
    ],
    target_compatible_with = [
        "@io_tweag_rules_nixpkgs//nixpkgs/constraints:support_nix",
    ],
)

filegroup(
    name = "build-script",
    srcs = [
        "build-docs.sh"
    ],
)

sh_library(
    name = "sh-lib",
    srcs = ["lib.sh"],
)

load("@rules_sh//sh:sh.bzl", "sh_binaries")
sh_binaries(
    name = "build-docs-tools",
    srcs = [
        "@doxygen//:doxygen",
        # "@mdbook//:mdbook",
        "@crate_index//:mdbook__mdbook",
        "@hugo//:hugo",
    ]
)

# load("@aspect_bazel_lib//lib:run_binary.bzl", "run_binary")

genrule(
    name = "build-docs-gen",
    srcs = [
        ":build-script",
        "//:mdbook_files",
        "//doc/guides/getting_started:mdbook_files_gettingstarted",
        "//hw:all_files",
        "//sw:all_files",
        "//sw/device/silicon_creator/manuf/data:all_files",
        "//sw/device/silicon_creator/rom/data:all_files",
        "//site:files",
        "//util/doxygen:files",
        "//util:mdbook_preprocessors",
        "//util:all_files",
    ],
    tools = [ ":sh-lib" ],
    toolchains = [":build-docs-tools"], # Gives us _BUILD_DOCS_TOOLS_PATH
    cmd = """
. $(execpath :sh-lib)

set -euo pipefail
export PATH="$$(make_all_absolute "$(_BUILD_DOCS_TOOLS_PATH)"):$$PATH"
$(location :build-script) build > $@
""",
    outs = [ "out.txt" ],
)

load (":defs.bzl", "custom_rule")

custom_rule(
    name = "custom_rule",
    tools = ":build-docs-tools",
    srcs = [
        "//:mdbook_files",
        "//doc/guides/getting_started:mdbook_files_gettingstarted",
        "//hw:all_files",
        "//sw:all_files",
        "//sw/device/silicon_creator/manuf/data:all_files",
        "//sw/device/silicon_creator/rom/data:all_files",
        "//site:files",
        "//util/doxygen:files",
        "//util:mdbook_preprocessors",
        "//util:all_files",
    ],
    build_docs = ":build-script",
)
