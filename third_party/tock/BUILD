# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@rules_python//python/entry_points:py_console_script_binary.bzl", "py_console_script_binary")

package(default_visibility = ["//visibility:public"])

py_console_script_binary(
    name = "tockloader",
    pkg = "@ot_python_deps//tockloader",
)

bzl_library(
    name = "extensions",
    srcs = ["extensions.bzl"],
    deps = [
        "//rules:repo",
        "//rules:rust",
        "@bazel_tools//tools/build_defs/repo:http.bzl",
    ],
)
