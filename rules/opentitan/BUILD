# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")
load("@stardoc//stardoc:stardoc.bzl", "stardoc")
load("//rules/opentitan:toolchain.bzl", "LOCALTOOLS_TOOLCHAIN", "localtools_toolchain")

package(default_visibility = ["//visibility:public"])

localtools_toolchain(
    name = "localtools_impl",
)

toolchain_type(
    name = "localtools_type",
)

toolchain(
    name = "localtools",
    toolchain = ":localtools_impl",
    toolchain_type = LOCALTOOLS_TOOLCHAIN,
)

filegroup(
    name = "doc_files",
    srcs = glob(["**/*.md"]),
)

stardoc(
    name = "cc-doc",
    out = "cc.md",
    input = "cc.bzl",
    deps = [
        ":cc",
    ],
)

stardoc(
    name = "ci-doc",
    out = "ci.md",
    input = "ci.bzl",
    deps = [
        ":ci",
    ],
)

stardoc(
    name = "defs-doc",
    out = "defs.md",
    input = "defs.bzl",
    deps = [
        ":defs",
    ],
)

stardoc(
    name = "exec_env-doc",
    out = "exec_env.md",
    input = "exec_env.bzl",
    deps = [
        ":exec_env",
    ],
)

stardoc(
    name = "fpga-doc",
    out = "fpga.md",
    input = "fpga.bzl",
    deps = [
        ":fpga",
    ],
)

stardoc(
    name = "hw-doc",
    out = "hw.md",
    input = "hw.bzl",
    deps = [
        ":hw",
    ],
)

stardoc(
    name = "keyutils-doc",
    out = "keyutils.md",
    input = "keyutils.bzl",
    deps = [
        ":keyutils",
    ],
)

stardoc(
    name = "legacy-doc",
    out = "legacy.md",
    input = "legacy.bzl",
    deps = [
        ":legacy",
    ],
)

stardoc(
    name = "manual-doc",
    out = "manual.md",
    input = "manual.bzl",
    deps = [
        ":manual",
    ],
)

stardoc(
    name = "providers-doc",
    out = "providers.md",
    input = "providers.bzl",
    deps = [
        ":providers",
    ],
)

stardoc(
    name = "qemu-doc",
    out = "qemu.md",
    input = "qemu.bzl",
    deps = [
        ":qemu",
    ],
)

stardoc(
    name = "silicon-doc",
    out = "silicon.md",
    input = "silicon.bzl",
    deps = [
        ":silicon",
    ],
)

stardoc(
    name = "sim_dv-doc",
    out = "sim_dv.md",
    input = "sim_dv.bzl",
    deps = [
        ":sim_dv",
    ],
)

stardoc(
    name = "sim_verilator-doc",
    out = "sim_verilator.md",
    input = "sim_verilator.bzl",
    deps = [
        ":sim_verilator",
    ],
)

stardoc(
    name = "splice-doc",
    out = "splice.md",
    input = "splice.bzl",
    deps = [
        ":splice",
    ],
)

stardoc(
    name = "static_library-doc",
    out = "static_library.md",
    input = "static_library.bzl",
    deps = [
        ":static_library",
    ],
)

stardoc(
    name = "toolchain-doc",
    out = "toolchain.md",
    input = "toolchain.bzl",
    deps = [
        ":toolchain",
    ],
)

stardoc(
    name = "transform-doc",
    out = "transform.md",
    input = "transform.bzl",
    deps = [
        ":transform",
    ],
)

stardoc(
    name = "util-doc",
    out = "util.md",
    input = "util.bzl",
    deps = [
        ":util",
    ],
)

###########################
# AUTOGEN GAZELLE TARGETS #
###########################

bzl_library(
    name = "cc",
    srcs = ["cc.bzl"],
    deps = [
        ":providers",
        ":toolchain",
        "@lowrisc_opentitan//rules:rv",
        "@lowrisc_opentitan//rules:signing",
        "@lowrisc_opentitan//rules/opentitan:exec_env",
        "@lowrisc_opentitan//rules/opentitan:transform",
        "@lowrisc_opentitan//rules/opentitan:util",
        "@rules_cc//cc:action_names_bzl",
        "@rules_cc//cc:find_cc_toolchain_bzl",
        "@rules_cc//cc/common",
    ],
)

bzl_library(
    name = "ci",
    srcs = ["ci.bzl"],
    deps = ["@bazel_skylib//lib:sets"],
)

bzl_library(
    name = "defs",
    srcs = ["defs.bzl"],
    deps = [
        ":cc",
        ":ci",
        ":fpga",
        ":hw",
        ":keyutils",
        ":manual",
        ":qemu",
        ":silicon",
        ":sim_dv",
        ":sim_verilator",
        "//hw/top:defs",
        "//rules:rv",
        "@bazel_skylib//lib:sets",
        "@provisioning_exts//:cfg",
    ],
)

bzl_library(
    name = "exec_env",
    srcs = ["exec_env.bzl"],
    deps = [
        ":toolchain",
        "@bazel_skylib//lib:types",
        "@lowrisc_opentitan//rules/opentitan:providers",
        "@lowrisc_opentitan//rules/opentitan:util",
    ],
)

bzl_library(
    name = "fpga",
    srcs = ["fpga.bzl"],
    deps = [
        ":exec_env",
        ":toolchain",
        "@lowrisc_opentitan//rules/opentitan:providers",
        "@lowrisc_opentitan//rules/opentitan:transform",
        "@lowrisc_opentitan//rules/opentitan:util",
    ],
)

bzl_library(
    name = "hw",
    srcs = ["hw.bzl"],
    deps = ["//rules:host"],
)

bzl_library(
    name = "keyutils",
    srcs = ["keyutils.bzl"],
    deps = [
        "//rules:const",
        "//rules:signing",
        "@bazel_skylib//lib:structs",
    ],
)

bzl_library(
    name = "legacy",
    srcs = ["legacy.bzl"],
    deps = [
        "@lowrisc_opentitan//hw/top:defs",
        "@lowrisc_opentitan//rules:rv",
        "@lowrisc_opentitan//rules/opentitan:defs",
        "@lowrisc_opentitan//rules/opentitan:transform",
    ],
)

bzl_library(
    name = "qemu",
    srcs = ["qemu.bzl"],
    deps = [
        ":exec_env",
        ":toolchain",
        "@lowrisc_opentitan//rules/opentitan:providers",
        "@lowrisc_opentitan//rules/opentitan:util",
    ],
)

bzl_library(
    name = "silicon",
    srcs = ["silicon.bzl"],
    deps = [
        ":exec_env",
        ":toolchain",
        "@lowrisc_opentitan//rules/opentitan:providers",
        "@lowrisc_opentitan//rules/opentitan:transform",
        "@lowrisc_opentitan//rules/opentitan:util",
    ],
)

bzl_library(
    name = "sim_dv",
    srcs = ["sim_dv.bzl"],
    deps = [
        ":exec_env",
        ":toolchain",
        "@lowrisc_opentitan//rules/opentitan:providers",
        "@lowrisc_opentitan//rules/opentitan:transform",
        "@lowrisc_opentitan//rules/opentitan:util",
    ],
)

bzl_library(
    name = "sim_verilator",
    srcs = ["sim_verilator.bzl"],
    deps = [
        ":exec_env",
        ":toolchain",
        "@lowrisc_opentitan//rules/opentitan:providers",
        "@lowrisc_opentitan//rules/opentitan:transform",
        "@lowrisc_opentitan//rules/opentitan:util",
    ],
)

bzl_library(
    name = "splice",
    srcs = ["splice.bzl"],
    deps = [
        ":exec_env",
        ":providers",
        ":toolchain",
        ":util",
        "@bazel_skylib//lib:dicts",
        "@nonhermetic//:env.bzl",
    ],
)

bzl_library(
    name = "static_library",
    srcs = ["static_library.bzl"],
    deps = [
        "@lowrisc_opentitan//rules:rv",
        "@rules_cc//cc:action_names_bzl",
        "@rules_cc//cc:find_cc_toolchain_bzl",
        "@rules_cc//cc/common",
    ],
)

bzl_library(
    name = "toolchain",
    srcs = ["toolchain.bzl"],
    deps = ["//rules:host"],
)

bzl_library(
    name = "transform",
    srcs = ["transform.bzl"],
    deps = [
        "//rules:actions",
        "@bazel_skylib//lib:paths",
        "@bazel_skylib//rules:common_settings",
        "@lowrisc_opentitan//rules/opentitan:util",
        "@rules_cc//cc:action_names_bzl",
        "@rules_cc//cc:find_cc_toolchain_bzl",
        "@rules_cc//cc/common",
    ],
)

bzl_library(
    name = "manual",
    srcs = ["manual.bzl"],
)

bzl_library(
    name = "providers",
    srcs = ["providers.bzl"],
)

bzl_library(
    name = "util",
    srcs = ["util.bzl"],
)
