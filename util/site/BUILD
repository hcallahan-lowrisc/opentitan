# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

package(default_visibility = ["//visibility:public"])

# Use --config=nix to select a platform which meets these constraints

py_binary(
    name = "hello",
    srcs = ["hello.py"],
    main = "hello.py",
    exec_compatible_with = [
        "@io_tweag_rules_nixpkgs//nixpkgs/constraints:support_nix",
    ],
    target_compatible_with = [
        "@io_tweag_rules_nixpkgs//nixpkgs/constraints:support_nix",
    ],
)
