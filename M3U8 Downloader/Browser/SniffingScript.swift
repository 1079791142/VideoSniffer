import Foundation

/// The script injected into every frame of the browser to detect media URLs.
///
/// Every hook is wrapped in `try`/`catch` so a broken hook can never take a
/// page down. Only absolute `http(s)` URLs are reported; `blob:` and `data:`
/// URLs are ignored because they cannot be fetched outside the page — the
/// underlying playlist or file is usually visible in `fetch`/XHR traffic.
/// The message shape is `{ url, kind, pageURL }` on the `videoSniffer`
/// handler; `SniffMessageHandler` treats it as untrusted data.
nonisolated enum SniffingScript {
    static let source = #"""
    (function () {
        "use strict";
        if (window.__videoSnifferInstalled) { return; }
        window.__videoSnifferInstalled = true;

        var MAX_URL_LENGTH = 4096;
        var reported = Object.create(null);

        function isHTTPURL(value) {
            return typeof value === "string"
                && value.length > 0
                && value.length <= MAX_URL_LENGTH
                && /^https?:\/\//i.test(value);
        }

        function kindFor(url) {
            var lower = url.toLowerCase();
            if (lower.indexOf("m3u8") !== -1) { return "hls"; }
            if (/\.(mp4|m4s|m4v|mov|webm)([?#]|$)/.test(lower)) { return "file"; }
            return null;
        }

        function absolutize(value) {
            try {
                if (typeof value !== "string" || value.length === 0) { return null; }
                return new URL(value, window.location.href).href;
            } catch (error) {
                return null;
            }
        }

        function report(rawValue) {
            try {
                var absolute = absolutize(rawValue);
                if (!absolute || !isHTTPURL(absolute)) { return; }
                var kind = kindFor(absolute);
                if (!kind || reported[absolute]) { return; }
                reported[absolute] = true;

                var bridge = window.webkit && window.webkit.messageHandlers
                    && window.webkit.messageHandlers.videoSniffer;
                if (!bridge) { return; }
                bridge.postMessage({
                    url: absolute,
                    kind: kind,
                    pageURL: window.location.href
                });
            } catch (error) {
            }
        }

        function collect(root) {
            try {
                var nodes = [];
                if (root && root.nodeType === 1 && root.matches
                    && root.matches("video, source")) {
                    nodes.push(root);
                }
                if (root && root.querySelectorAll) {
                    nodes.push.apply(nodes, root.querySelectorAll("video, source"));
                }
                for (var index = 0; index < nodes.length; index++) {
                    var node = nodes[index];
                    if (node.currentSrc) { report(node.currentSrc); }
                    if (node.getAttribute) { report(node.getAttribute("src")); }
                }
            } catch (error) {
            }
        }

        try {
            var originalFetch = window.fetch;
            if (typeof originalFetch === "function") {
                window.fetch = function (input) {
                    try {
                        if (typeof input === "string") {
                            report(input);
                        } else if (input && typeof input.url === "string") {
                            report(input.url);
                        }
                    } catch (error) {
                    }
                    return originalFetch.apply(this, arguments);
                };
            }
        } catch (error) {
        }

        try {
            var originalOpen = XMLHttpRequest.prototype.open;
            if (typeof originalOpen === "function") {
                XMLHttpRequest.prototype.open = function (method, url) {
                    try {
                        if (typeof url === "string") { report(url); }
                    } catch (error) {
                    }
                    return originalOpen.apply(this, arguments);
                };
            }
        } catch (error) {
        }

        try {
            var mediaPrototype = window.HTMLMediaElement && HTMLMediaElement.prototype;
            if (mediaPrototype) {
                var srcDescriptor = Object.getOwnPropertyDescriptor(mediaPrototype, "src");
                if (srcDescriptor && srcDescriptor.get && srcDescriptor.set) {
                    Object.defineProperty(mediaPrototype, "src", {
                        configurable: true,
                        enumerable: srcDescriptor.enumerable,
                        get: function () {
                            try {
                                return srcDescriptor.get.call(this);
                            } catch (error) {
                                return "";
                            }
                        },
                        set: function (value) {
                            try { report(value); } catch (error) {
                            }
                            return srcDescriptor.set.call(this, value);
                        }
                    });
                }

                var originalPlay = mediaPrototype.play;
                if (typeof originalPlay === "function") {
                    mediaPrototype.play = function () {
                        try {
                            if (this.currentSrc) { report(this.currentSrc); }
                            if (this.src) { report(this.src); }
                        } catch (error) {
                        }
                        return originalPlay.apply(this, arguments);
                    };
                }

                var originalLoad = mediaPrototype.load;
                if (typeof originalLoad === "function") {
                    mediaPrototype.load = function () {
                        try {
                            if (this.currentSrc) { report(this.currentSrc); }
                            if (this.src) { report(this.src); }
                        } catch (error) {
                        }
                        return originalLoad.apply(this, arguments);
                    };
                }
            }
        } catch (error) {
        }

        try {
            collect(document);
        } catch (error) {
        }

        try {
            if (typeof MutationObserver === "function" && document.documentElement) {
                var observer = new MutationObserver(function (mutations) {
                    for (var index = 0; index < mutations.length; index++) {
                        var added = mutations[index].addedNodes || [];
                        for (var nodeIndex = 0; nodeIndex < added.length; nodeIndex++) {
                            collect(added[nodeIndex]);
                        }
                    }
                });
                observer.observe(document.documentElement, {
                    childList: true,
                    subtree: true
                });
            }
        } catch (error) {
        }
    })();
    """#
}
