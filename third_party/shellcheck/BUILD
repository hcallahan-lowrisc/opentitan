# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

package(default_visibility = ["//visibility:private"])

# This runnable alias points to the shellcheck executable.
alias(
    name = "shellcheck",
    actual = "@shellcheck//:shellcheck",
    visibility = ["//quality:__pkg__"],
)

bzl_library(
    name = "extensions",
    srcs = ["extensions.bzl"],
    deps = ["@bazel_tools//tools/build_defs/repo:http.bzl"],
)
