# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@io_tweag_rules_nixpkgs//nixpkgs:repositories.bzl",
     "rules_nixpkgs_dependencies")

def nixpkgs_deps():
    # Import the transitive dependencies of rules_nixpkgs.
    rules_nixpkgs_dependencies()
