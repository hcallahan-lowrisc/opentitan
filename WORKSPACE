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
NIXPKGS_HASH="420370f64f03ed9c1ff9b5e2994d06c0439cb1f2"
NIXPKGS_SHA_OF_HASH="5270e14b2965408f4ea51b2f76774525b086be6f00de0da4082d14a69017c5e4"
http_archive(
    name = "io_tweag_rules_nixpkgs",
    strip_prefix = "rules_nixpkgs-%s" % NIXPKGS_HASH,
    urls = [
        "https://github.com/tweag/rules_nixpkgs/archive/%s.tar.gz" % NIXPKGS_HASH
    ],
    sha256 = NIXPKGS_SHA_OF_HASH,
)
# Import the transitive dependencies of rules_nixpkgs.
load("@io_tweag_rules_nixpkgs//nixpkgs:repositories.bzl", "rules_nixpkgs_dependencies")
rules_nixpkgs_dependencies()

# Create "@nixpkgs" as a specific revision of Nixpkgs on GitHub
load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_git_repository", "nixpkgs_local_repository")
nixpkgs_git_repository(
    name = "nixpkgs",
    revision = "23.05",
)

nixpkgs_local_repository(
    name = "nixpkgs-local",
    nix_flake_lock_file = "//:flake.lock",
    nix_file_deps = [
        "//:flake.nix",
        "//:flake.lock",
    ],
)

########################

nix_repos = {
    "nixpkgs": "@nixpkgs",
}


# You can use 'nix_file_deps' to include additional files that are required to also be imported, such
# as the flake.lock file, or additional .nix files that are imported as part of the build.
# load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_local_repository")
# nixpkgs_local_repository(
#     name = "nixpkgs",
#     nix_file = "//:nixpkgs.nix",
#     nix_file_deps = ["//:flake.lock"],
# )

###########

# Configure a python toolchain
load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_python_configure", "nixpkgs_python_repository")
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

UNPACK_SINGLE_BIN_BUILD_FILE = """
filegroup(
    name = "bin",
    srcs = glob([ "**/bin/*" ]),
    )

genrule(
  visibility = ["//visibility:public"],
  name = "unpack_binaries",
  cmd = \"\"\"\
  #!/bin/bash

  # Copy binaries to the output location
  cp external/{bin_path} $(location :{bin_name});

  \"\"\",
  srcs = [ ":bin" ],
  outs = [ "{bin_name}" ],
  )
"""

BUILD_FILE_NIXPACKAGE = """
package(default_visibility = ["//visibility:public"])
filegroup(
    name = "{a}",
    srcs = ["bin/{a}"],
)
"""

load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl", "nixpkgs_package", "nixpkgs_flake_package")
[nixpkgs_package(
    name = a,
    attribute_path = a,
    build_file_content=UNPACK_SINGLE_BIN_BUILD_FILE.format(
        bin_path="{}/bin/{}".format(a,a),
        bin_name=a,
    ),
    repositories = nix_repos
) for a in ["doxygen", "mdbook", "hugo"]]

nixpkgs_package(
    name = "nix-tools",
    repository = "@nixpkgs",
    nix_file = "//:deps.nix"
)
nixpkgs_package(
    name = "nixpkgs-hugo",
    repository = "@nixpkgs",
    attribute_path = "hugo", # Pull this straight from the nixpkgs attribute set
)

############################################

# nixpkgs_flake_package(
#     name = "fpy",
#     nix_flake_file = "//:flake.nix",
#     nix_flake_lock_file = "//:flake.lock",
#     package = "python",
# )

nixpkgs_python_configure(
    name = "fpy_tc",
    repository = "@nixpkgs-local",
    python3_attribute_path = "python3",
    python3_bin_path = "bin/python3",
)

nixpkgs_python_repository(
    name = "fpp",
    repository = "@nixpkgs",
    nix_file = "//:default.nix",
    nix_file_deps = [
        "//:flake.nix",
        "//:flake.lock",
        "//:pyproject.toml",
        "//:poetry.lock",
    ],
)

############################################

load("@bazel_tools//tools/build_defs/repo:http.bzl", "http_archive")
http_archive(
    name = "rules_python_upstream",
    sha256 = "5868e73107a8e85d8f323806e60cad7283f34b32163ea6ff1020cf27abef6036",
    strip_prefix = "rules_python-0.25.0",
    url = "https://github.com/bazelbuild/rules_python/releases/download/0.25.0/rules_python-0.25.0.tar.gz",
)
load("@rules_python_upstream//python:repositories.bzl", "py_repositories")
py_repositories()

# Python Toolchain + PIP Dependencies
load("//third_party/python:repos.bzl", "python_repos")
python_repos()
load("//third_party/python:deps.bzl", "python_deps")
python_deps()
load("//third_party/python:pip.bzl", "pip_deps")
pip_deps()

############################################

# register_toolchains("//:py3-nix")

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

# Shellcheck
load("//third_party/shellcheck:repos.bzl", "shellcheck_repos")
shellcheck_repos()

# Tock dependencies.
load("//third_party/tock/crates:crates.bzl", tock_crate_repositories = "crate_repositories")
tock_crate_repositories()
load("//third_party/tock:repos.bzl", tock_repos="tock_repos")
tock_repos(
    # For developing tock/libtock along side OpenTitan, set these parameters
    # to your local checkout of tock and libtock-rs respectively.
    #tock = "../tock",
    #libtock = "../libtock-rs",
)

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

# Setup for linking in external test hooks for both secure/non-secure
# manufacturer domains.
load("//rules:hooks_setup.bzl", "hooks_setup", "secure_hooks_setup")
hooks_setup(
    name = "hooks_setup",
    dummy = "sw/device/tests/closed_source",
)
secure_hooks_setup(
    name = "secure_hooks_setup",
    dummy = "sw/device/tests/closed_source",
)

# Declare the external test_hooks repositories. One for both manufacturer secure
# and non-secure domains.
load("@hooks_setup//:repos.bzl", "hooks_repo")
load("@secure_hooks_setup//:repos.bzl", "secure_hooks_repo")
hooks_repo(name = "manufacturer_test_hooks")
secure_hooks_repo(name = "secure_manufacturer_test_hooks")

# The nonhermetic_repo imports environment variables needed to run vivado.
load("//rules:nonhermetic.bzl", "nonhermetic_repo")
nonhermetic_repo(name = "nonhermetic")

# Binary firmware image for HyperDebug
load("//third_party/hyperdebug:repos.bzl", "hyperdebug_repos")
hyperdebug_repos()

# Bazel skylib library
load("@bazel_skylib//:workspace.bzl", "bazel_skylib_workspace")
bazel_skylib_workspace()
