#!/usr/bin/env bash
#
# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Helper script that reads a file from stdin and replaces every tab character
# with at most eight spaces (i.e. what smart tabs would render it as at an
# eight-space tab.

set -e

expand -t 8 <&0
