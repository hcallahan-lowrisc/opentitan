# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("//rules/tests:const_unittest.bzl", "const_test_suite")
load("//rules/tests:otp_unittest.bzl", "otp_test_suite")

const_test_suite()

otp_test_suite()

bzl_library(
    name = "const_unittest",
    srcs = ["const_unittest.bzl"],
    visibility = ["//visibility:public"],
    deps = [
        "//rules:const",
        "@bazel_skylib//lib:sets",
        "@bazel_skylib//lib:unittest",
    ],
)

bzl_library(
    name = "otp_unittest",
    srcs = ["otp_unittest.bzl"],
    visibility = ["//visibility:public"],
    deps = [
        "//rules:otp",
        "@bazel_skylib//lib:unittest",
    ],
)
