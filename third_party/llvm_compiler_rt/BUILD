# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("//rules/opentitan:defs.bzl", "OPENTITAN_CPU")

package(default_visibility = ["//visibility:public"])

cc_library(
    name = "llvm_compiler_rt",
    srcs = ["@llvm_compiler_rt//:srcs"],
    deps = [
        "//sw/device/lib/base:memory",
        "@llvm_compiler_rt//:hdrs",
    ],
)

bzl_library(
    name = "extensions",
    srcs = ["extensions.bzl"],
    deps = ["@bazel_tools//tools/build_defs/repo:http.bzl"],
)
