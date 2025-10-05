# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("//rules:autogen.bzl", "autogen_stamp_include")
load("//rules:stamp.bzl", "stamp_flag")
load("//rules/opentitan:defs.bzl", "OPENTITAN_PLATFORM")

package(default_visibility = ["//visibility:public"])

config_setting(
    name = "opentitan_platform",
    values = {"platforms": OPENTITAN_PLATFORM},
)

# See stamp.bzl for explanation.
stamp_flag(name = "stamp_flag")

# This target provides a C header containing all stamping variables.
#
#  By default, or when building with --nostamp, this rule produces an empty
#  C header file.
#
#  When building with --stamp, this rule will output a C header like the
#  following example:
#    #define BAZEL_BUILD_SCM_REVISION_SHORT 0d6b3555
#    #define BAZEL_BUILD_SCM_STATUS clean
#    #define BAZEL_BUILD_TIMESTAMP 1743189267
#    ...
#
# To avoid rebuilding to all dependents as transitive header, this generated
# file should be included in srcs instead of deps.
autogen_stamp_include(
    name = "autogen_stamp_include",
)

###########################
# AUTOGEN GAZELLE TARGETS #
###########################

bzl_library(
    name = "autogen",
    srcs = ["autogen.bzl"],
    deps = [
        ":doxygen",
        ":stamp",
        "//hw/top:defs",
        "//rules/opentitan:util",
    ],
)

bzl_library(
    name = "certificates",
    srcs = ["certificates.bzl"],
    deps = [
        "//rules/opentitan:toolchain",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "const",
    srcs = ["const.bzl"],
    deps = ["@bazel_skylib//lib:structs"],
)

bzl_library(
    name = "doxygen",
    srcs = ["doxygen.bzl"],
    deps = ["//hw/top:defs"],
)

bzl_library(
    name = "extensions",
    srcs = ["extensions.bzl"],
    deps = ["@bazel_tools//tools/build_defs/repo:local.bzl"],
)

bzl_library(
    name = "fusesoc",
    srcs = ["fusesoc.bzl"],
    deps = [
        "@bazel_skylib//lib:dicts",
        "@bazel_skylib//rules:common_settings",
        "@nonhermetic//:env.bzl",
    ],
)

bzl_library(
    name = "lc",
    srcs = ["lc.bzl"],
    deps = ["@bazel_skylib//rules:common_settings"],
)

bzl_library(
    name = "linker",
    srcs = ["linker.bzl"],
    deps = [
        "@rules_cc//cc:action_names_bzl",
        "@rules_cc//cc:find_cc_toolchain_bzl",
        "@rules_cc//cc/common",
    ],
)

bzl_library(
    name = "manifest",
    srcs = ["manifest.bzl"],
    deps = [":const"],
)

bzl_library(
    name = "otbn",
    srcs = ["otbn.bzl"],
    deps = [
        ":rv",
        "@rules_cc//cc:find_cc_toolchain_bzl",
        "@rules_cc//cc/common",
    ],
)

bzl_library(
    name = "otp",
    srcs = ["otp.bzl"],
    deps = [
        ":const",
        ":stamp",
        "//hw/top:defs",
        "//rules/opentitan:toolchain",
        "@bazel_skylib//lib:new_sets",
        "@bazel_skylib//rules:common_settings",
    ],
)

bzl_library(
    name = "quality",
    srcs = ["quality.bzl"],
    deps = [
        ":host",
        ":rv",
        "//rules/opentitan:toolchain.bzl",
        "@bazel_skylib//lib:shell",
        "@rules_cc//cc:action_names_bzl",
        "@rules_cc//cc:find_cc_toolchain_bzl",
        "@rules_cc//cc/common",
    ],
)

bzl_library(
    name = "rom_e2e",
    srcs = ["rom_e2e.bzl"],
    deps = [
        ":const",
        "@bazel_skylib//lib:structs",
    ],
)

bzl_library(
    name = "signing",
    srcs = ["signing.bzl"],
    deps = [
        ":host",
        ":rv",
        "//rules/opentitan:providers",
        "//rules/opentitan:toolchain",
        "//rules/opentitan:util",
        "@bazel_skylib//lib:paths",
    ],
)

bzl_library(
    name = "tock",
    srcs = ["tock.bzl"],
    deps = [
        ":rv",
        "@rules_cc//cc:action_names_bzl",
        "@rules_cc//cc:find_cc_toolchain_bzl",
        "@rules_cc//cc/common",
    ],
)

bzl_library(
    name = "ujson",
    srcs = ["ujson.bzl"],
    deps = [
        "@rules_cc//cc:find_cc_toolchain_bzl",
        "@rules_cc//cc/common",
    ],
)

bzl_library(
    name = "actions",
    srcs = ["actions.bzl"],
)

bzl_library(
    name = "bitstreams",
    srcs = ["bitstreams.bzl"],
)

bzl_library(
    name = "cross_platform",
    srcs = ["cross_platform.bzl"],
)

bzl_library(
    name = "files",
    srcs = ["files.bzl"],
)

bzl_library(
    name = "host",
    srcs = ["host.bzl"],
)

bzl_library(
    name = "nonhermetic",
    srcs = ["nonhermetic.bzl"],
)

bzl_library(
    name = "repo",
    srcs = ["repo.bzl"],
)

bzl_library(
    name = "rust",
    srcs = ["rust.bzl"],
)

bzl_library(
    name = "rv",
    srcs = ["rv.bzl"],
)

bzl_library(
    name = "stamp",
    srcs = ["stamp.bzl"],
)
