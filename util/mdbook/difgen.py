# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0
"""Generate HTML documentation for Device Interface Functions (DIFs)."""

import io
import copy
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

import logging
logger = logging.getLogger(__name__)

def get_combined_xml(doxygen_xml_path: Path) -> ET.Element:
    """
    Turn the Doxygen multi-file XML output into one giant XML file (and parse it
    into a python object), using the provided XLST file.
    """
    xsltproc_args = [
        "xsltproc",
        str(doxygen_xml_path / "combine.xslt"),
        str(doxygen_xml_path / "index.xml"),
    ]

    combined_xml_res = subprocess.run(
        xsltproc_args,
        check=True,
        cwd=str(doxygen_xml_path),
        stdout=subprocess.PIPE,
        universal_newlines=True,
    )
    return ET.fromstring(combined_xml_res.stdout)


def gen_listing_html(
        html_url: str,
        dif_header: Path,
        combined_xml: ET.Element,
        dif_listings_html: io.StringIO) -> None:
    """Create HTML list of DIFs, using the info from the combined xml.

    Raises:
        RuntimeError: Matching data for the given html_url/dif_header args
                      could not be found in the XML.
    """
    # First, select the matching data from within the generated doxygen xml
    # We are effectively querying for matches in the Xpath : //compounddef[@kind="file"]/location/@file
    compound = _get_dif_file_compound(combined_xml, dif_header)
    if compound is None:
        raise RuntimeError(f"Doxygen output not found within XML for {dif_header}")

    file_id = _get_dif_file_id(compound)
    functions = _get_dif_function_info(compound, file_id, html_url)
    if len(functions) == 0:
        raise RuntimeError(f"No DIF functions found within XML for {dif_header}")

    # Generate DIF listing header
    dif_listings_html.write('<p>To use this DIF, include the following C header:</p>')
    dif_listings_html.write('<pre><code class=language-c data-lang=c>')
    dif_listings_html.write('#include "<a href="{}/{}.html">{}</a>"'.format(
        html_url, file_id, dif_header,
    ))
    dif_listings_html.write('</code></pre>\n')

    # Generate DIF function list.
    dif_listings_html.write('<p>This header provides the following device interface functions:</p>')
    dif_listings_html.write('<ul>\n')
    for f in sorted(functions, key=lambda x: x['name']):
        dif_listings_html.write('<li title="{prototype}" id="Dif_{name}">'.format(**f))
        dif_listings_html.write('<a href="{full_url}">'.format(**f))
        dif_listings_html.write('<code>{name}</code>'.format(**f))
        dif_listings_html.write('</a>\n')
        dif_listings_html.write(f['description'])
        dif_listings_html.write('</li>\n')
    dif_listings_html.write('</ul>\n')


# Generate HTML link for single function, using info returned from
# get_difref_info
def gen_difref_html(function_info, difref_html: io.StringIO) -> None:
    difref_html.write('<a href="{full_url}">'.format(**function_info))
    difref_html.write('<code>{name}</code>'.format(**function_info))
    difref_html.write('</a>\n')


def _get_dif_file_compound(combined_xml: ET.Element, dif_header: Path) -> ET.Element:
    for c in combined_xml.findall('compounddef[@kind="file"]'):
        if c.find("location").attrib["file"] == str(dif_header):
            return c
    return None


def _get_dif_file_id(compound: ET.Element) -> str:
    return compound.attrib["id"]


def _get_dif_function_info(compound: ET.Element,
                           file_id: str,
                           html_url: str) -> list[dict]:
    """Returns a list of dicts for each function in the dif.

    Each dict contains useful metadata we can then use to generate additional
    documentation.

    Params:
        compound:
        file_id:
        html_url: /* Not used for lookup, just added into the metadata */
            The directory where the Doxygen-generated HTML files are hosted.
    """
    funcs = compound.find('sectiondef[@kind="func"]')
    if funcs is None:
        return []

    # Collect useful info on each function
    functions = []
    for m in funcs.findall('memberdef[@kind="function"]'):
        func_id = m.attrib['id']
        # Strip refid prefix, which is separated from the funcid by `_1`
        if func_id.startswith(file_id + '_1'):
            # The +2 here is because of the weird `_1` separator
            func_id = func_id[len(file_id) + 2:]
        else:
            # I think this denotes that this function isn't from this file
            continue

        func_info = {}
        func_info["id"] = m.attrib["id"]
        func_info["file_id"] = file_id
        func_info["local_id"] = func_id
        func_info["full_url"] = "{}/{}.html#{}".format(html_url, file_id, func_id)

        func_info["name"] = _get_text_or_empty(m, "name")
        func_info["prototype"] = _get_text_or_empty(
            m, "definition") + _get_text_or_empty(m, "argsstring")
        func_info["description"] = _get_html_or_empty(m,
                                                      "briefdescription/para")

        functions.append(func_info)

    return functions


def _get_html_or_empty(element: ET.Element, xpath: str) -> str:
    """ Get a minimal HTML-rendering of the children in an element.

    element is expected to be a docCmdGroup according to the DoxyGen schema [1],
    but only a very minimal subset of formatting is transferred to semantic
    HTML. However, the tag structure is retained by transforming all tags into
    HTML `span` tags with a class attribute `doxygentag-ORIGINALTAGNAME`. This
    can be used to write CSS targeting specific Doxygen tags and recreate the
    intended formatting.

    In addtion, the following semantic transformations are performed:
    - `computeroutput` is transformed to `code`

    [1] https://github.com/doxygen/doxygen/blob/master/templates/xml/compound.xsd"""
    inner = element.find(xpath)
    # if the element isn't found, return ""
    if inner is None:
        return ""

    # Avoid modifying the passed element argument.
    inner_copy = copy.deepcopy(inner)

    for c in inner_copy.iter():
        c.set('class', 'doxygentag-' + c.tag)
        if c.tag == 'computeroutput':
            c.tag = 'code'
        else:
            c.tag = 'span'

    # Create a string from all subelements
    text = ET.tostring(inner_copy, encoding="unicode", method="html")
    return text or ""


def _get_text_or_empty(element: ET.Element, xpath: str) -> str:
    """ Get all text of an element, without any tags """
    inner = element.find(xpath)
    if inner is None:
        return ""

    return ' '.join([e for e in inner.itertext()]) or ""
