# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@bazel_tools//tools/build_defs/repo:http.bzl",
     "http_archive")

def nixpkgs_repos():
    ######################
    #----- NIXPKGS ------#
    ######################
    # https://github.com/tweag/rules_nixpkgs

    # Import the rules_nixpkgs repository.
    # 420370f6 - Jun 22, 2023
    RULES_NIXPKGS_HASH="420370f64f03ed9c1ff9b5e2994d06c0439cb1f2"
    RULES_NIXPKGS_SHA_OF_HASH="5270e14b2965408f4ea51b2f76774525b086be6f00de0da4082d14a69017c5e4"
    http_archive(
        name = "io_tweag_rules_nixpkgs",
        strip_prefix = "rules_nixpkgs-%s" % RULES_NIXPKGS_HASH,
        urls = [
            "https://github.com/tweag/rules_nixpkgs/archive/%s.tar.gz" % RULES_NIXPKGS_HASH
        ],
        sha256 = RULES_NIXPKGS_SHA_OF_HASH,
    )

