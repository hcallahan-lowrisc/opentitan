# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

sh_binary(
    name = "run_test",
    srcs = ["run_test.sh"],
)

bzl_library(
    name = "get-bitstream-fragment-dir",
    srcs = ["get-bitstream-fragment-dir.bzl"],
    visibility = ["//visibility:public"],
)

bzl_library(
    name = "get-bitstream-fragment-files-relative",
    srcs = ["get-bitstream-fragment-files-relative.bzl"],
    visibility = ["//visibility:public"],
)
