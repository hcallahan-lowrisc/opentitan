# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

package(default_visibility = ["//visibility:public"])

filegroup(
    name = "ec_bin",
    srcs = ["@hyperdebug_firmware//:hyperdebug/ec.bin"],
)

exports_files([
    "hyperdebug/ec.bin",
])

bzl_library(
    name = "extensions",
    srcs = ["extensions.bzl"],
    deps = ["@bazel_tools//tools/build_defs/repo:http.bzl"],
)
