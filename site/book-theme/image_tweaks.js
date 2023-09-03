/* Copyright lowRISC contributors. */
/* Licensed under the Apache License, Version 2.0, see LICENSE for details. */
/* SPDX-License-Identifier: Apache-2.0 */


/* https://github.com/midzer/tobii */
// Make all non-svg <img> tags lightboxes using tobii
var init_lightbox = function() {
    let content = document.getElementById("content");

    Array.prototype.forEach.call(
        content.querySelectorAll("img"),
        function(el) {
            if (el.src.includes("badges")) {
                return;
            }
            let lightbox = document.createElement("a");
            lightbox.classList.add("lightbox"); /* https://github.com/midzer/tobii */
            lightbox.href = el.src;
            // Wrap the existing <img> with this new element
            // This wrapper becomes the clickable-overlay to launch the lightbox
            el.parentElement.appendChild(lightbox);
            lightbox.appendChild(el);
        }
    );
    // Initialize the lightbox for raster images
    const tobii = new Tobii();
};

/* https://github.com/shubhamjain/svg-loader */
// Convert linked .svg in <img> tags to inline <svg>
// - Use svg-loader to add the linked .svg files inline
// - Setting the attributes below is what triggers svg-loader
var init_inline_svg = function() {
    let content = document.getElementById("content");

    Array.prototype.forEach.call(
        content.querySelectorAll("img"),
        function(el) {
            // Only apply to <img> tags where src=.*svg
            // Exclude the inline badges
            if (!(el.src.endsWith("svg")) || el.src.includes("badges")) {
                return;
            }
            let svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
            svg.setAttribute("data-src", el.src);
            // before deleting the existing <img>, add new <svg> element before it
            el.parentElement.insertBefore(svg, el);
            el.remove();
        }
    );

};

// Add onload event to:
// - render all wavejson
//   https://wavedrom.com/
// - make all inline <svg> within content pannable+zoomable
//   https://github.com/svgdotjs/svg.panzoom.js
//   https://github.com/svgdotjs/svg.js
var add_onload_event = function() {

    // Handle wavedrom SVG rendering
    window.addEventListener('load', function() {

        // First, render all of the wavejson diagrams
        /* https://wavedrom.com/ */
        WaveDrom.ProcessAll();

        // Finally, make all content <svg>s pan+zoom able
        let content = document.getElementById("content");
        Array.prototype.forEach.call(
            content.querySelectorAll("svg"),
            function(el) {
                // el.style.width = "auto";
                // el.style.height = "auto";
                /* https://github.com/svgdotjs/svg.panzoom.js */
                SVG(el)
                    .panZoom({
                        zoomFactor: 0.1,
                        zoomMin: 0.5,
                    });
            }
        );

    });

};

var image_tweaks = function() {
    init_inline_svg();
    init_lightbox();
    add_onload_event();
};
