# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

load("@rules_pkg//pkg:mappings.bzl", "pkg_files")

package(default_visibility = ["//visibility:public"])

exports_files(glob(["*.h"]))

pkg_files(
    name = "package",
    srcs = glob(["*.h"]),
    prefix = "crypto/include/freestanding",
)
