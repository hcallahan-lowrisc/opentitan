# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
${gencmd}

load("@bazel_skylib//:bzl_library.bzl", "bzl_library")

exports_files(glob(["*.hjson"]))
