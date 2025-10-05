# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load(":defs.bzl", "TESTS", "rv_compliance_test")

package(default_visibility = ["//visibility:public"])

[[rv_compliance_test(test, arch) for test in tests] for arch, tests in TESTS.items()]

bzl_library(
    name = "defs",
    srcs = ["defs.bzl"],
    deps = [
        "//rules/opentitan:defs",
        "@bazel_skylib//lib:dicts",
    ],
)

bzl_library(
    name = "extensions",
    srcs = ["extensions.bzl"],
    deps = ["@bazel_tools//tools/build_defs/repo:http.bzl"],
)
