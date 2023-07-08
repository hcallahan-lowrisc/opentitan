# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# If you're planning to add to this file, please read
# //third_party/README.md first.

workspace(name = "lowrisc_opentitan")

######################
#----- NIXPKGS ------#
######################
# https://github.com/tweag/rules_nixpkgs

# Import the rules_nixpkgs repository.
load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
# 420370f6 - Jun 22, 2023
http_archive(
    name = "io_tweag_rules_nixpkgs",
    strip_prefix = "rules_nixpkgs-420370f64f03ed9c1ff9b5e2994d06c0439cb1f2",
    urls = ["https://github.com/tweag/rules_nixpkgs/archive/420370f64f03ed9c1ff9b5e2994d06c0439cb1f2.tar.gz"],
    sha256 = "5270e14b2965408f4ea51b2f76774525b086be6f00de0da4082d14a69017c5e4"
)
# Import the transitive dependencies of rules_nixpkgs.
load("@io_tweag_rules_nixpkgs//nixpkgs:repositories.bzl", "rules_nixpkgs_dependencies")
rules_nixpkgs_dependencies()

# Create "@nixpkgs" as a specific revision of Nixpkgs on GitHub
load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_git_repository")
nixpkgs_git_repository(
    name = "nixpkgs",
    revision = "23.05",
)

###########

# Configure a python toolchain
# load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_python_configure")
# nixpkgs_python_configure(
#     # """Define and register a Python toolchain provided by nixpkgs.
#     #
#     # Creates `nixpkgs_package`s for Python 2 or 3 `py_runtime` instances and a
#     # corresponding `py_runtime_pair` and `toolchain`.
#     #
#     # The toolchain is automatically registered and uses the constraint:
#     # ```
#     # "@io_tweag_rules_nixpkgs//nixpkgs/constraints:support_nix"
#     # ```
#     #
#     # """
#     name = "nixpkgs_python_toolchain",
#     python3_attribute_path = "python39.withPackages(ps: [ ps.flask ])",
#     repository = "@nixpkgs",
# )

# rules_nixpkgs/core/platforms/BUILD.bazel
##########################################
# > platform(
# >     name = "host",
# >     constraint_values = ["@rules_nixpkgs_core//constraints:support_nix"],
# >     parents = ["@local_config_platform//:host"],
# >     visibility = ["//visibility:public"],
# > )
##########################################

# rules_nixpkgs/core/constraints/BUILD.bazel
############################################
# > constraint_setting(name = "nix")
#
# > constraint_value(
# >     name = "support_nix",
# >     constraint_setting = ":nix",
# > )
############################################

# CRT is the Compiler Repository Toolkit.  It contains the configuration for
# the windows compiler.
load("//third_party/crt:repos.bzl", "crt_repos")
crt_repos()
load("@crt//:repos.bzl", "crt_repos")
crt_repos()
load("@crt//:deps.bzl", "crt_deps")
crt_deps()
load("@crt//config:registration.bzl", "crt_register_toolchains")
crt_register_toolchains(riscv32 = True)

# Tools for release automation
load("//third_party/github:repos.bzl", "github_tools_repos")
github_tools_repos()

# Go Toolchain (needed by the Buildifier linter)
load("//third_party/go:repos.bzl", "go_repos")
go_repos()
load("//third_party/go:deps.bzl", "go_deps")
go_deps()

# Various linters
load("//third_party/lint:repos.bzl", "lint_repos")
lint_repos()
load("//third_party/lint:deps.bzl", "lint_deps")
lint_deps()

# Lychee link checker.
load("//third_party/lychee:repos.bzl", "lychee_repos")
lychee_repos()

# Python Toolchain + PIP Dependencies
load("//third_party/python:repos.bzl", "python_repos")
python_repos()
load("//third_party/python:deps.bzl", "python_deps")
python_deps()
load("//third_party/python:pip.bzl", "pip_deps")
pip_deps()

# Google/Bazel dependencies.  This needs to be after Python initialization
# so that our preferred python configuration takes precedence.
load("//third_party/google:repos.bzl", "google_repos")
google_repos()
load("//third_party/google:deps.bzl", "google_deps")
google_deps()

# Rust Toolchain + crates.io Dependencies
load("//third_party/rust:repos.bzl", "rust_repos")
rust_repos()
load("//third_party/rust:deps.bzl", "rust_deps")
rust_deps()

load("@rules_rust//crate_universe:repositories.bzl", "crate_universe_dependencies")
crate_universe_dependencies(bootstrap = True)

load("//third_party/rust/crates:crates.bzl", "crate_repositories")
crate_repositories()

# OpenOCD
load("//third_party/openocd:repos.bzl", "openocd_repos")
openocd_repos()

# Protobuf Toolchain
load("//third_party/protobuf:repos.bzl", "protobuf_repos")
protobuf_repos()
load("//third_party/protobuf:deps.bzl", "protobuf_deps")
protobuf_deps()

# FreeRTOS; used by the OTTF
load("//third_party/freertos:repos.bzl", "freertos_repos")
freertos_repos()

# LLVM Compiler Runtime for Profiling
load("//third_party/llvm_compiler_rt:repos.bzl", "llvm_compiler_rt_repos")
llvm_compiler_rt_repos()

# RISC-V Compliance Tests
load("//third_party/riscv-compliance:repos.bzl", "riscv_compliance_repos")
riscv_compliance_repos()

# CoreMark benchmark
load("//third_party/coremark:repos.bzl", "coremark_repos")
coremark_repos()

# The standard Keccak algorithms
load("//third_party/xkcp:repos.bzl", "xkcp_repos")
xkcp_repos()

# HSM related repositories (SoftHSM2, etc)
load("//third_party/hsm:repos.bzl", "hsm_repos")
hsm_repos()

# Bitstreams from https://storage.googleapis.com/opentitan-bitstreams/
load("//rules:bitstreams.bzl", "bitstreams_repo")
bitstreams_repo(name = "bitstreams")

# Setup for linking in external test hooks.
load("//rules:hooks_setup.bzl", "hooks_setup")
hooks_setup(
    name = "hooks_setup",
    dummy = "sw/device/tests/closed_source",
)

# Declare the external test_hooks repository.
load("@hooks_setup//:repos.bzl", "hooks_repo")
hooks_repo(name = "manufacturer_test_hooks")

# The nonhermetic_repo imports environment variables needed to run vivado.
load("//rules:nonhermetic.bzl", "nonhermetic_repo")
nonhermetic_repo(name = "nonhermetic")

# Binary firmware image for HyperDebug
load("//third_party/hyperdebug:repos.bzl", "hyperdebug_repos")
hyperdebug_repos()

# Bazel skylib library
load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")
bazel_skylib_workspace()



# load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_package")
# nixpkgs_package(
#     name = "hello",
#     repositories = { "nixpkgs": "@nixpkgs//:default.nix" }
# )

# load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
#      "nixpkgs_git_repository",
#      "nixpkgs_package",
#      "nixpkgs_cc_configure")
