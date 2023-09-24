# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
     "nixpkgs_git_repository",
     "nixpkgs_local_repository")

load("@io_tweag_rules_nixpkgs//nixpkgs:nixpkgs.bzl",
     "nixpkgs_python_configure",
     "nixpkgs_python_repository")

def nixpkgs_toolchains():
    # Create "@nixpkgs-local" as a specific revision of Nixpkgs
    nixpkgs_local_repository(
        name = "nixpkgs-local",
        nix_flake_lock_file = "//:flake.lock",
        nix_file_deps = [
            "//:flake.nix",
            "//:flake.lock",
        ],
    )
    nixpkgs_python()

def nixpkgs_python():
    ##########################################
    # Configure a python toolchain
    ##########################################
    nixpkgs_python_configure(
        name = "fpy_tc",
        repository = "@nixpkgs-local",
        python3_attribute_path = "python3",
        python3_bin_path = "bin/python3",
    )

    nixpkgs_python_repository(
        name = "fpp",
        repository = "@nixpkgs-local",
        nix_file = "//:default.nix",
        nix_file_deps = [
            "//:flake.nix",
            "//:flake.lock",
            "//:pyproject.toml",
            "//:poetry.lock",
        ],
    )
    ##########################################
