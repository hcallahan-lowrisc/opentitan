# Copyright lowRISC contributors (OpenTitan project).
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
r"""
Class describing simulation results
"""

import collections
import re
import uuid

from Testplan import Result

_REGEX_REMOVE = [
    # Remove UVM time.
    re.compile(r'@\s+[\d.]+\s+[np]s: '),
    re.compile(r'\[[\d.]+\s+[np]s\] '),
    # Remove assertion time.
    re.compile(r'\(time [\d.]+ [PF]S\) '),
    # Remove leading spaces.
    re.compile(r'^\s+'),
    # Remove extra white spaces.
    re.compile(r'\s+(?=\s)'),
]

_REGEX_STRIP = [
    # Strip TB instance name.
    re.compile(r'[\w_]*top\.\S+\.(\w+)'),
    # Strip assertion.
    re.compile(r'(?<=Assertion )\S+\.(\w+)'),
]

# Regular expression for a separator: EOL or some of punctuation marks.
_SEPARATOR_RE = '($|[ ,.:;])'

_REGEX_STAR = [
    # Replace hex numbers with 0x (needs to be called before other numbers).
    re.compile(r'0x\s*[\da-fA-F]+'),
    # Replace hex numbers with 'h (needs to be called before other numbers).
    re.compile(r'\'h\s*[\da-fA-F]+'),
    # Floating point numbers at the beginning of a word, example "10.1ns".
    # (needs to be called before other numbers).
    re.compile(r'(?<=[^a-zA-Z0-9])\d+\.\d+'),
    # Replace all isolated numbers. Isolated numbers are numbers surrounded by
    # special symbols, for example ':' or '+' or '_', excluding parenthesis.
    # So a number with a letter or a round bracket on any one side, is
    # considered non-isolated number and is not starred by these expressions.
    re.compile(r'(?<=[^a-zA-Z0-9\(\)])\d+(?=($|[^a-zA-Z0-9\(\)]))'),
    # Replace numbers surrounded by parenthesis after a space and followed by a
    # separator.
    re.compile(r'(?<= \()\s*\d+\s*(?=\)%s)' % _SEPARATOR_RE),
    # Replace hex/decimal numbers after an equal sign or a semicolon and
    # followed by a separator. Uses look-behind pattern which need a
    # fixed width, thus the apparent redundancy.
    re.compile(r'(?<=[\w\]][=:])[\da-fA-F]+(?=%s)' % _SEPARATOR_RE),
    re.compile(r'(?<=[\w\]][=:] )[\da-fA-F]+(?=%s)' % _SEPARATOR_RE),
    re.compile(r'(?<=[\w\]] [=:])[\da-fA-F]+(?=%s)' % _SEPARATOR_RE),
    re.compile(r'(?<=[\w\]] [=:] )[\da-fA-F]+(?=%s)' % _SEPARATOR_RE),
    # Replace decimal number at the beginning of the word.
    re.compile(r'(?<= )\d+(?=\S)'),
    # Remove decimal number at end of the word and before '=' or '[' or
    # ',' or '.' or '('.
    re.compile(r'(?<=\S)\d+(?=($|[ =\[,\.\(]))'),
    # Replace the instance string.
    re.compile(r'(?<=instance)\s*=\s*\S+'),
]


# This affects the bucketizer failure report.
_MAX_UNIQUE_TESTS = 5
_MAX_TEST_RESEEDS = 2

class SimResults:
    '''An object wrapping up a table of results for some tests

    self.table is a list of Result objects, each of which
    corresponds to one or more runs of the test with a given name.

    self.buckets contains a dictionary accessed by the failure signature,
    holding all failing tests with the same signature.
    '''

    def __init__(self, items, results):
        self.table = []
        self.buckets = collections.defaultdict(list)
        self._name_to_row = {}
        for item in items:
            self._add_item(item, results)

    def _add_item(self, item, results):
        '''Recursively add a single item to the table of results'''
        status = results[item]
        if status in ["F", "K"]:
            bucket = self._bucketize(item.launcher.fail_msg.message)
            self.buckets[bucket].append(
                (item, item.launcher.fail_msg.line_number,
                 item.launcher.fail_msg.context))

        # Runs get added to the table directly
        if item.target == "run":
            self._add_run(item, status)

    def _add_run(self, item, status):
        '''Add an entry to table for item'''
        row = self._name_to_row.get(item.name)
        if row is None:
            row = Result(item.name,
                         job_runtime=item.job_runtime,
                         simulated_time=item.simulated_time)
            self.table.append(row)
            self._name_to_row[item.name] = row

        else:
            # Record the max job_runtime of all reseeds.
            if item.job_runtime > row.job_runtime:
                row.job_runtime = item.job_runtime
                row.simulated_time = item.simulated_time

        if status == 'P':
            row.passing += 1
        row.total += 1

    def _bucketize(self, fail_msg):
        bucket = fail_msg
        # Remove stuff.
        for regex in _REGEX_REMOVE:
            bucket = regex.sub('', bucket)
        # Strip stuff.
        for regex in _REGEX_STRIP:
            bucket = regex.sub(r'\g<1>', bucket)
        # Replace with '*'.
        for regex in _REGEX_STAR:
            bucket = regex.sub('*', bucket)
        return bucket


    def create_md_bucket_report(self, add_repro_html_buttons: bool = False) -> str:
        """Creates a markdown report based on all added failure buckets.

        The buckets are sorted by descending number of failures. Within
        buckets this also group tests by unqualified name, and just a few
        failures are shown per unqualified name.

        Returns:
          A markdown string to be embedded into report.
        """

        def indent_by(level):
            return " " * (4 * level)

        def create_failure_message(test, line, context) -> list[str]:
            # First print the qualified name of the test
            message = [f"{indent_by(2)}* {test.qual_name}\\"]

            # Print the path to the logfile containng the failure, including a linenumber if present
            log_msg = ""
            if line:
                log_msg = f"{indent_by(2)}  Line {line}, in log {test.get_log_path()}"
            else:
                log_msg = f"{indent_by(2)}  Log {test.get_log_path()}"

            message.append(log_msg)

            if add_repro_html_buttons:
                # Append an HTML button to the above log_msg
                # This button hooks some inline javascript in the report to copy the reproduction
                # command to the clipboard. See utils::md_results_to_html() for the javascript.

                repro_cmd = test.create_repro_command()
                repro_button_id = uuid.uuid4()

                repro_button_attributes = " ".join([
                  f"id='{repro_button_id}'",
                  "class='btn'",
                  f"onclick='copyContent(\"{repro_button_id}\")'",
                  f"repro_cmd='{repro_cmd}'",
                ])
                repro_button_element = f"  <button {repro_button_attributes}>Click to copy repro</button>"

                # Append to previous line, so the button appears inline with the logfile name
                message[-1] += repro_button_element

            # Print the logfile context around the failing line if present
            if context:
                message.append("")
                context_lines = [f"{indent_by(4)}{c.rstrip()}" for c in context
                                 if (c != "\n")] # Drop empty lines from the context
                message.extend(context_lines)

            return message

        fail_msgs = ["\n## Failure Buckets", ""]

        by_tests = sorted(self.buckets.items(),
                          key=lambda i: len(i[1]),
                          reverse=True)

        # Loop over all buckets
        for bucket, tests in by_tests:
            fail_msgs.append(f"* `{bucket}` has {len(tests)} failures:")

            # Reduce all failures in the bucket to a unique entry for each test
            unique_tests = collections.defaultdict(list)
            for (test, line, context) in tests:
                unique_tests[test.name].append((test, line, context))

            # Loop over the unqiue tests with failures in this bucket...
            for name, test_reseeds in list(unique_tests.items())[:_MAX_UNIQUE_TESTS]:

                msg = f"{indent_by(1)}* Test {name} has {len(test_reseeds)} failures."
                fail_msgs.append(msg)

                # Up to a maximum of _MAX_TEST_RESEEDS, print a short summary for each failing seed
                for test, line, context in test_reseeds[:_MAX_TEST_RESEEDS]:
                    msg_lines = create_failure_message(test, line, context)
                    fail_msgs.extend(msg_lines)

                # If there are too manu failing seeds and we have to truncate the list, and a
                # "..and more failures" message to show this
                if len(test_reseeds) > _MAX_TEST_RESEEDS:
                    msg = f"{indent_by(2)}* ... and {len(test_reseeds) - _MAX_TEST_RESEEDS} more failures."
                    fail_msgs.append(msg)

            # If there are too many unique tests with this failure mode, also truncate the list...
            if len(unique_tests) > _MAX_UNIQUE_TESTS:
                msg = f"{indent_by(1)}* ... and {len(unique_tests) - _MAX_UNIQUE_TESTS} more tests."
                fail_msgs.append(msg)

        # Return as a string
        return "\n".join(fail_msgs)
