//
//  RenderedHTMLImporter.swift
//  EXP [design]
//
//  E1's browser-neutral seam. WebKit produces a bounded, Codable snapshot;
//  this mapper turns that snapshot into editable EXP geometry without needing
//  a live browser. Keeping extraction and mapping separated is what lets the
//  checked-in fixtures test fidelity deterministically.
//

import AppKit
import Foundation
import CoreGraphics

// MARK: - Browser snapshot

nonisolated struct RenderedHTMLViewport: Codable, Equatable, Sendable {
    var name: String
    var width: CGFloat
    var renderHeight: CGFloat
}

nonisolated struct RenderedHTMLTextFragment: Codable, Equatable, Sendable {
    var text: String
    /// A direct DOM text node may wrap onto several lines. The browser owns the
    /// line breaks; EXP uses their union rather than laying the string out anew.
    var rects: [CGRect]
    var style: RenderedHTMLComputedStyle
    /// Position in the element's `childNodes`, including text and element nodes.
    /// Element-only paths cannot reconstruct inline rich-text order by themselves.
    var domIndex: Int? = nil
}

nonisolated struct RenderedHTMLElement: Codable, Equatable, Sendable {
    var tagName: String
    var path: String
    var rect: CGRect
    var style: RenderedHTMLComputedStyle
    var attributes: [String: String] = [:]
    var textFragments: [RenderedHTMLTextFragment] = []
    var children: [RenderedHTMLElement] = []
    var domIndex: Int? = nil
    /// Browser-decoded pixels for replaced elements (`img`) or self-contained
    /// markup for inline SVG. Keeping this on the element means the pure mapper
    /// never needs filesystem or browser access.
    var renderedAsset: RenderedHTMLAsset? = nil
    /// Original bytes for a single local CSS `background-image: url(...)`.
    /// Populated by the trusted-folder capture after the read-only DOM pass.
    var backgroundAsset: RenderedHTMLAsset? = nil

    var dataEXPID: UUID? {
        attributes["data-exp-id"].flatMap(UUID.init(uuidString:))
    }

    var displayName: String {
        if let authored = attributes["data-exp-name"], !authored.isEmpty { return authored }
        if let id = attributes["id"], !id.isEmpty { return "\(tagName.lowercased())#\(id)" }
        if let classes = attributes["class"],
           let first = classes.split(whereSeparator: \Character.isWhitespace).first {
            return "\(tagName.lowercased()).\(first)"
        }
        if tagName.lowercased() == "img", let alt = attributes["alt"], !alt.isEmpty {
            return alt
        }
        return tagName.lowercased()
    }
}

nonisolated struct RenderedHTMLAsset: Codable, Equatable, Sendable {
    var mimeType: String
    /// Codable's JSON representation is base64, matching the extraction script.
    var data: Data
    var naturalWidth: CGFloat
    var naturalHeight: CGFloat
    /// The browser's resolved source lets the local capture replace a canvas
    /// preview with original SVG markup from the trusted folder.
    var sourceURL: String? = nil
}

/// Fixed computed-style allowlist from HTML-IMPORT-CONTRACT.md §3. Strings are
/// intentional: they preserve exactly what WebKit resolved and make unknown or
/// newer CSS values reportable instead of decode-fatal.
nonisolated struct RenderedHTMLComputedStyle: Codable, Equatable, Sendable {
    var display: String = "block"
    var visibility: String = "visible"
    var position: String = "static"
    var overflowX: String = "visible"
    var overflowY: String = "visible"

    var backgroundColor: String = "rgba(0, 0, 0, 0)"
    var backgroundImage: String = "none"
    var backgroundRepeat: String = "repeat"
    var backgroundSize: String = "auto"
    var backgroundPosition: String = "0% 0%"
    var color: String = "rgb(0, 0, 0)"
    var opacity: String = "1"

    var borderTopWidth: String = "0px"
    var borderRightWidth: String = "0px"
    var borderBottomWidth: String = "0px"
    var borderLeftWidth: String = "0px"
    var borderTopColor: String = "rgb(0, 0, 0)"
    var borderRightColor: String = "rgb(0, 0, 0)"
    var borderBottomColor: String = "rgb(0, 0, 0)"
    var borderLeftColor: String = "rgb(0, 0, 0)"
    var borderTopLeftRadius: String = "0px"
    var borderTopRightRadius: String = "0px"
    var borderBottomRightRadius: String = "0px"
    var borderBottomLeftRadius: String = "0px"

    var outlineColor: String = "rgb(0, 0, 0)"
    var outlineStyle: String = "none"
    var outlineWidth: String = "0px"
    var outlineOffset: String = "0px"

    var boxShadow: String = "none"
    var transform: String = "none"
    var filter: String = "none"
    var mixBlendMode: String = "normal"
    var zIndex: String = "auto"

    var fontFamily: String = ""
    var fontSize: String = "16px"
    var fontWeight: String = "400"
    var fontStyle: String = "normal"
    var lineHeight: String = "normal"
    var letterSpacing: String = "normal"
    var textAlign: String = "start"
    var textDecorationLine: String = "none"
    var textTransform: String = "none"
}

nonisolated struct RenderedHTMLSnapshot: Codable, Equatable, Sendable {
    static let formatVersion = 1

    var version: Int = Self.formatVersion
    var sourceName: String
    var sourceURL: String
    var title: String
    var viewport: RenderedHTMLViewport
    var documentHeight: CGFloat
    var root: RenderedHTMLElement
    var capturedNodeCount: Int? = nil
    var devicePixelRatio: Double? = nil
    var mediaQueryMatches: [String] = []
    var notes: [String] = []
    /// Bounded, JSON-safe metadata exposed by a recognized rendered runtime.
    /// Ordinary local HTML leaves this nil.
    var runtimeMetadata: [String: String]? = nil
}

// MARK: - Extraction script

/// The production payload producer. The WebKit/session layer supplies the
/// source and viewport metadata; the script only reads the already-rendered DOM.
/// It never fetches, mutates, clicks, submits, or navigates.
nonisolated enum RenderedHTMLExtractionScript {
    static func source(sourceName: String, sourceURL: String,
                       viewport: RenderedHTMLViewport,
                       maximumNodes: Int = 15_000) -> String {
        let metadata: [String: Any] = [
            "sourceName": sourceName,
            "sourceURL": sourceURL,
            "viewport": ["name": viewport.name,
                         "width": viewport.width,
                         "renderHeight": viewport.renderHeight],
            "maximumNodes": maximumNodes
        ]
        let data = try? JSONSerialization.data(withJSONObject: metadata)
        let json = data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return javascript.replacingOccurrences(of: "__EXP_METADATA__", with: json)
    }

    private static let javascript = #"""
    (() => {
      "use strict";
      const metadata = __EXP_METADATA__;
      const styleNames = [
        "display", "visibility", "position", "overflowX", "overflowY",
        "backgroundColor", "backgroundImage", "backgroundRepeat", "backgroundSize",
        "backgroundPosition", "color", "opacity",
        "borderTopWidth", "borderRightWidth", "borderBottomWidth", "borderLeftWidth",
        "borderTopColor", "borderRightColor", "borderBottomColor", "borderLeftColor",
        "borderTopLeftRadius", "borderTopRightRadius", "borderBottomRightRadius", "borderBottomLeftRadius",
        "outlineColor", "outlineStyle", "outlineWidth", "outlineOffset",
        "boxShadow", "transform", "filter", "mixBlendMode", "zIndex",
        "fontFamily", "fontSize", "fontWeight", "fontStyle", "lineHeight",
        "letterSpacing", "textAlign", "textDecorationLine", "textTransform"
      ];
      // CoreGraphics' Codable shape is [[x,y],[width,height]]. Match it here so
      // the live WebKit payload and JSONEncoder-built fixtures use one decoder.
      const rect = r => [[r.x, r.y], [r.width, r.height]];
      const style = (el, pseudo = null) => {
        const cs = getComputedStyle(el, pseudo);
        const result = {};
        styleNames.forEach(name => result[name] = cs[name] || "");
        return result;
      };
      const attributes = el => {
        const keep = new Set(["id", "class", "role", "alt", "href", "title", "src",
                              "type", "multiple", "size", "scope", "value", "min", "max",
                              "step", "list", "disabled", "checked", "selected",
                              "data-exp-id", "data-exp-name", "data-exp-instance-id"]);
        const result = {};
        Array.from(el.attributes || []).forEach(attr => {
          if (keep.has(attr.name) || attr.name.startsWith("aria-")) result[attr.name] = attr.value;
        });
        if (el instanceof HTMLImageElement) {
          result["data-exp-resolved-src"] = el.currentSrc || el.src || "";
        }
        return result;
      };
      const bytesToBase64 = bytes => {
        let binary = "";
        for (let offset = 0; offset < bytes.length; offset += 0x8000) {
          binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
        }
        return btoa(binary);
      };
      const singleMaskSource = cs => {
        const maskImage = cs.maskImage || cs.webkitMaskImage || "none";
        if (!maskImage.startsWith("url(") || !maskImage.endsWith(")")) return null;
        let source = maskImage.slice(4, -1).trim();
        if ((source.startsWith('"') && source.endsWith('"'))
            || (source.startsWith("'") && source.endsWith("'"))) {
          source = source.slice(1, -1);
        }
        return source;
      };
      const dataSVGMaskAsset = (cs, width, height) => {
        const source = singleMaskSource(cs);
        if (!source) return null;
        if (!source.toLowerCase().startsWith("data:image/svg+xml")) return null;
        try {
          const comma = source.indexOf(",");
          if (comma < 0) return null;
          const header = source.slice(0, comma).toLowerCase();
          const payload = source.slice(comma + 1);
          let markup;
          if (header.includes(";base64")) {
            const binary = atob(payload);
            if (binary.length > 262144) return null;
            const bytes = Uint8Array.from(binary, character => character.charCodeAt(0));
            markup = new TextDecoder().decode(bytes);
          } else {
            markup = decodeURIComponent(payload);
            if (new TextEncoder().encode(markup).length > 262144) return null;
          }
          const document = new DOMParser().parseFromString(markup, "image/svg+xml");
          const root = document.documentElement;
          if (!root || root.localName !== "svg"
              || document.querySelector("parsererror")) return null;
          root.querySelectorAll("script,foreignObject").forEach(node => node.remove());
          [root, ...root.querySelectorAll("*")].forEach(node => {
            Array.from(node.attributes || []).forEach(attr => {
              if (/^on/i.test(attr.name)) node.removeAttribute(attr.name);
              if ((attr.name === "href" || attr.name === "xlink:href")
                  && attr.value && !attr.value.startsWith("#")
                  && !attr.value.startsWith("data:")) node.removeAttribute(attr.name);
            });
          });
          root.setAttribute("xmlns", "http://www.w3.org/2000/svg");
          root.setAttribute("width", String(Math.max(1, width)));
          root.setAttribute("height", String(Math.max(1, height)));
          root.setAttribute("fill", cs.backgroundColor || cs.color || "black");
          const colored = new XMLSerializer().serializeToString(root);
          return {mimeType: "image/svg+xml",
            data: bytesToBase64(new TextEncoder().encode(colored)),
            naturalWidth: Math.max(1, width), naturalHeight: Math.max(1, height),
            sourceURL: source};
        } catch (_) { return null; }
      };
      const roundedRect = (ctx, width, height, cs) => {
        const radius = value => {
          if (!value) return 0;
          if (value.endsWith("%")) return Math.min(width, height) * parseFloat(value) / 100;
          return Math.max(0, parseFloat(value) || 0);
        };
        const tl = radius(cs.borderTopLeftRadius), tr = radius(cs.borderTopRightRadius);
        const br = radius(cs.borderBottomRightRadius), bl = radius(cs.borderBottomLeftRadius);
        ctx.beginPath();
        ctx.moveTo(tl, 0); ctx.lineTo(width - tr, 0); ctx.quadraticCurveTo(width, 0, width, tr);
        ctx.lineTo(width, height - br); ctx.quadraticCurveTo(width, height, width - br, height);
        ctx.lineTo(bl, height); ctx.quadraticCurveTo(0, height, 0, height - bl);
        ctx.lineTo(0, tl); ctx.quadraticCurveTo(0, 0, tl, 0); ctx.closePath(); ctx.clip();
      };
      const renderedAsset = el => {
        const bounds = el.getBoundingClientRect();
        const maskAsset = dataSVGMaskAsset(
          getComputedStyle(el), bounds.width, bounds.height);
        if (maskAsset) return maskAsset;
        if (el instanceof HTMLImageElement && el.complete && el.naturalWidth > 0
            && bounds.width > 0 && bounds.height > 0) {
          try {
            const width = Math.min(8192, Math.max(1, Math.ceil(bounds.width)));
            const height = Math.min(8192, Math.max(1, Math.ceil(bounds.height)));
            const canvas = document.createElement("canvas");
            canvas.width = width; canvas.height = height;
            const ctx = canvas.getContext("2d");
            roundedRect(ctx, width, height, getComputedStyle(el));
            ctx.drawImage(el, 0, 0, width, height);
            const encoded = canvas.toDataURL("image/png").split(",")[1];
            if (encoded) return {mimeType: "image/png", data: encoded,
              naturalWidth: width, naturalHeight: height, sourceURL: el.currentSrc || el.src || null};
          } catch (_) { /* fall through to the local-resource catalog */ }
        }
        if (el instanceof SVGSVGElement) {
          try {
            const clone = el.cloneNode(true);
            clone.setAttribute("xmlns", "http://www.w3.org/2000/svg");
            clone.setAttribute("width", String(Math.max(1, bounds.width)));
            clone.setAttribute("height", String(Math.max(1, bounds.height)));
            const originals = [el, ...el.querySelectorAll("*")];
            const copies = [clone, ...clone.querySelectorAll("*")];
            const presentation = ["fill", "fill-opacity", "stroke", "stroke-opacity",
              "stroke-width", "stroke-linecap", "stroke-linejoin", "opacity",
              "color", "font-family", "font-size", "font-weight", "font-style"];
            originals.forEach((original, index) => {
              const cs = getComputedStyle(original);
              presentation.forEach(name => {
                const value = cs.getPropertyValue(name);
                if (value && (!value.includes("url(") || value.includes("url(\"#")
                    || value.includes("url('#") || value.includes("url(#"))) {
                  copies[index].style.setProperty(name, value);
                }
              });
              Array.from(copies[index].attributes || []).forEach(attr => {
                if (/^on/i.test(attr.name)) copies[index].removeAttribute(attr.name);
                if ((attr.name === "href" || attr.name === "xlink:href")
                    && attr.value && !attr.value.startsWith("#")
                    && !attr.value.startsWith("data:")) {
                  try {
                    const resolved = new URL(attr.value, document.baseURI);
                    const local = resolved.protocol === location.protocol
                      && resolved.host === location.host;
                    if (local) copies[index].setAttribute(attr.name, resolved.href);
                    else copies[index].removeAttribute(attr.name);
                  } catch (_) { copies[index].removeAttribute(attr.name); }
                }
              });
            });
            clone.querySelectorAll("script,foreignObject").forEach(node => node.remove());
            const markup = new XMLSerializer().serializeToString(clone);
            return {mimeType: "image/svg+xml", data: bytesToBase64(new TextEncoder().encode(markup)),
              naturalWidth: Math.max(1, bounds.width), naturalHeight: Math.max(1, bounds.height),
              sourceURL: null};
          } catch (_) { return null; }
        }
        return null;
      };
      const directText = el => Array.from(el.childNodes || [])
        .map((node, domIndex) => ({node, domIndex}))
        .filter(item => item.node.nodeType === Node.TEXT_NODE && /\S/.test(item.node.nodeValue || ""))
        .map(item => {
          const node = item.node;
          const range = document.createRange();
          range.selectNodeContents(node);
          return {text: node.nodeValue, rects: Array.from(range.getClientRects()).map(rect),
                  style: style(el), domIndex: item.domIndex};
        })
        .filter(item => item.rects.length > 0);
      const clipsAxis = value => value === "hidden" || value === "clip"
        || value === "scroll" || value === "auto";
      const isFullyClipped = (el, sourceBounds = null) => {
        const bounds = sourceBounds || el.getBoundingClientRect();
        let left = bounds.left, top = bounds.top;
        let right = bounds.right, bottom = bounds.bottom;
        for (let ancestor = el.parentElement; ancestor; ancestor = ancestor.parentElement) {
          const cs = getComputedStyle(ancestor);
          const clipX = clipsAxis(cs.overflowX);
          const clipY = clipsAxis(cs.overflowY);
          if (!clipX && !clipY) continue;
          const box = ancestor.getBoundingClientRect();
          const clipLeft = box.left + ancestor.clientLeft;
          const clipTop = box.top + ancestor.clientTop;
          const clipRight = clipLeft + ancestor.clientWidth;
          const clipBottom = clipTop + ancestor.clientHeight;
          if (clipX) { left = Math.max(left, clipLeft); right = Math.min(right, clipRight); }
          if (clipY) { top = Math.max(top, clipTop); bottom = Math.min(bottom, clipBottom); }
          if (!(right > left && bottom > top)) return true;
        }
        return false;
      };
      let nodeCount = 0;
      let nodeLimitReached = false;
      const pseudoSnapshot = (el, pseudo, path) => {
        const cs = getComputedStyle(el, pseudo);
        if (!cs || cs.display === "none" || cs.visibility === "hidden"
            || parseFloat(cs.opacity || "1") <= 0) return null;
        const generatedText = (() => {
          const content = (cs.content || "").trim();
          if (!content || content === "none" || content === "normal") return "";
          if (content.startsWith('"') && content.endsWith('"')) {
            try { return JSON.parse(content); } catch (_) { return content.slice(1, -1); }
          }
          if (content.startsWith("'") && content.endsWith("'")) return content.slice(1, -1);
          return "";
        })();
        const hasBackground = cs.backgroundImage !== "none"
          || !/^rgba?\(\s*0\s*,\s*0\s*,\s*0\s*,\s*0\s*\)$/.test(cs.backgroundColor)
             && cs.backgroundColor !== "transparent";
        const hasBorder = [cs.borderTopWidth, cs.borderRightWidth,
          cs.borderBottomWidth, cs.borderLeftWidth].some(value => (parseFloat(value) || 0) > 0);
        const hasOutline = cs.outlineStyle !== "none" && (parseFloat(cs.outlineWidth) || 0) > 0;
        const hasShadow = cs.boxShadow && cs.boxShadow !== "none";
        if (!generatedText && !hasBackground && !hasBorder && !hasOutline && !hasShadow) return null;
        const base = el.getBoundingClientRect();
        const containing = cs.position === "fixed"
          ? {x: 0, y: 0, width: innerWidth, height: innerHeight} : base;
        const length = (value, reference) => {
          if (!value || value === "auto") return null;
          if (value.endsWith("%")) return reference * (parseFloat(value) || 0) / 100;
          return parseFloat(value);
        };
        const left = length(cs.left, containing.width);
        const right = length(cs.right, containing.width);
        const top = length(cs.top, containing.height);
        const bottom = length(cs.bottom, containing.height);
        let width = length(cs.width, containing.width);
        let height = length(cs.height, containing.height);
        if (width === null && left !== null && right !== null) width = containing.width - left - right;
        if (height === null && top !== null && bottom !== null) height = containing.height - top - bottom;
        width = width === null ? base.width : width;
        height = height === null ? base.height : height;
        let x = left !== null ? containing.x + left
          : (right !== null ? containing.x + containing.width - right - width : base.x);
        let y = top !== null ? containing.y + top
          : (bottom !== null ? containing.y + containing.height - bottom - height : base.y);
        // Static pseudo-elements participate in their parent's layout but have
        // no DOM box API. Reconstruct their flex position from the already-laid-
        // out in-flow siblings and resolved margins. This keeps generated labels
        // such as a switch's `::after { content: "Off" }` beside its thumb instead
        // of stacking both at the parent's origin.
        const parentStyle = getComputedStyle(el);
        if (cs.position === "static"
            && (parentStyle.display === "flex" || parentStyle.display === "inline-flex")) {
          const direction = parentStyle.flexDirection || "row";
          const horizontal = direction.startsWith("row");
          const reversed = direction.endsWith("reverse");
          const flow = Array.from(el.children || []).map(child => ({
            child, cs: getComputedStyle(child), bounds: child.getBoundingClientRect()
          })).filter(item => item.cs.display !== "none" && item.cs.visibility !== "hidden"
            && item.cs.position !== "absolute" && item.cs.position !== "fixed"
            && item.bounds.width > 0 && item.bounds.height > 0);
          if (flow.length) {
            const placeAfter = pseudo === "::after" ? !reversed : reversed;
            if (horizontal) {
              if (placeAfter) {
                x = Math.max(...flow.map(item => item.bounds.right
                  + (parseFloat(item.cs.marginRight) || 0))) + (parseFloat(cs.marginLeft) || 0);
              } else {
                x = Math.min(...flow.map(item => item.bounds.left
                  - (parseFloat(item.cs.marginLeft) || 0)))
                  - (parseFloat(cs.marginRight) || 0) - width;
              }
            } else if (placeAfter) {
              y = Math.max(...flow.map(item => item.bounds.bottom
                + (parseFloat(item.cs.marginBottom) || 0))) + (parseFloat(cs.marginTop) || 0);
            } else {
              y = Math.min(...flow.map(item => item.bounds.top
                - (parseFloat(item.cs.marginTop) || 0)))
                - (parseFloat(cs.marginBottom) || 0) - height;
            }
          }
          const alignment = cs.alignSelf && cs.alignSelf !== "auto"
            ? cs.alignSelf : parentStyle.alignItems;
          if (horizontal) {
            if (alignment === "center") y = base.y + (base.height - height) / 2;
            else if (alignment === "flex-end" || alignment === "end") y = base.bottom - height;
            else y = base.y + (parseFloat(cs.marginTop) || 0);
          } else {
            if (alignment === "center") x = base.x + (base.width - width) / 2;
            else if (alignment === "flex-end" || alignment === "end") x = base.right - width;
            else x = base.x + (parseFloat(cs.marginLeft) || 0);
          }
        }
        // Pseudo-elements do not expose getBoundingClientRect(). Apply their
        // resolved CSS transform to the reconstructed box so translated switch
        // thumbs and other generated paint land where the browser drew them.
        if (cs.transform && cs.transform !== "none") {
          try {
            const matrix = new DOMMatrixReadOnly(cs.transform);
            const originValues = (cs.transformOrigin || "0 0").split(/\s+/);
            const originX = parseFloat(originValues[0]) || 0;
            const originY = parseFloat(originValues[1]) || 0;
            const corners = [[0, 0], [width, 0], [width, height], [0, height]].map(point => {
              const transformed = matrix.transformPoint(
                new DOMPoint(point[0] - originX, point[1] - originY));
              const divisor = transformed.w && transformed.w !== 1 ? transformed.w : 1;
              return {x: transformed.x / divisor + originX,
                      y: transformed.y / divisor + originY};
            });
            const transformedLeft = Math.min(...corners.map(point => point.x));
            const transformedTop = Math.min(...corners.map(point => point.y));
            const transformedRight = Math.max(...corners.map(point => point.x));
            const transformedBottom = Math.max(...corners.map(point => point.y));
            x += transformedLeft;
            y += transformedTop;
            width = transformedRight - transformedLeft;
            height = transformedBottom - transformedTop;
          } catch (_) { /* retain the untransformed reconstruction and report it */ }
        }
        if (!(width > 0 && height > 0)) return null;
        nodeCount += 1;
        const pseudoRect = rect({x, y, width, height});
        const maskImage = cs.maskImage || cs.webkitMaskImage || "none";
        const maskSource = singleMaskSource(cs);
        const maskAsset = dataSVGMaskAsset(cs, width, height);
        const pseudoAttributes = {"data-exp-name": `${el.tagName.toLowerCase()}${pseudo}`};
        if (maskImage !== "none") {
          pseudoAttributes["data-exp-mask-image"] = maskAsset
            ? "editable-data-svg" : "unsupported";
          if (maskSource) pseudoAttributes["data-exp-mask-source"] = maskSource;
        }
        return {tagName: pseudo, path, rect: pseudoRect,
          style: style(el, pseudo), attributes: pseudoAttributes,
          textFragments: generatedText
            ? [{text: generatedText, rects: [pseudoRect], style: style(el, pseudo), domIndex: null}]
            : [],
          children: [], domIndex: null, renderedAsset: maskAsset};
      };
      const walk = (el, path, domIndex = null) => {
        nodeCount += 1;
        const children = [];
        let elementIndex = 0;
        Array.from(el.childNodes || []).forEach((child, childNodeIndex) => {
          if (child.nodeType !== Node.ELEMENT_NODE) return;
          const childStyle = getComputedStyle(child);
          // The rendered-import boundary does not map display:none/hidden
          // subtrees. Skipping them here also prevents Storybook's large
          // offscreen preparing/docs shells from exhausting the node budget
          // before late body portals such as dialogs and popovers.
          if (childStyle.display === "none" || childStyle.visibility === "hidden"
              || isFullyClipped(child)) return;
          if (nodeCount >= metadata.maximumNodes) { nodeLimitReached = true; return; }
          children.push(walk(child, `${path}.${elementIndex}`, childNodeIndex));
          elementIndex += 1;
        });
        ["::before", "::after"].forEach((pseudo, index) => {
          if (nodeCount >= metadata.maximumNodes) { nodeLimitReached = true; return; }
          const snapshot = pseudoSnapshot(el, pseudo, `${path}.p${index}`);
          if (!snapshot) return;
          const z = parseInt(snapshot.style.zIndex || "0", 10);
          if (Number.isFinite(z) && z < 0) children.unshift(snapshot);
          else children.push(snapshot);
        });
        const ownBounds = el.getBoundingClientRect();
        let elementRect = rect(ownBounds);
        // `display: contents` and framework portal mounts can have no box of
        // their own while containing visible fixed/absolute descendants. Give
        // that editable wrapper the union of its rendered children instead of
        // discarding the whole subtree in the native mapper.
        if (!(ownBounds.width > 0 && ownBounds.height > 0)) {
          const visibleChildren = children.filter(child =>
            child.style.display !== "none" && child.style.visibility !== "hidden"
            && child.rect[1][0] > 0 && child.rect[1][1] > 0);
          if (visibleChildren.length) {
            const left = Math.min(...visibleChildren.map(child => child.rect[0][0]));
            const top = Math.min(...visibleChildren.map(child => child.rect[0][1]));
            const right = Math.max(...visibleChildren.map(child => child.rect[0][0] + child.rect[1][0]));
            const bottom = Math.max(...visibleChildren.map(child => child.rect[0][1] + child.rect[1][1]));
            elementRect = rect({x: left, y: top, width: right - left, height: bottom - top});
          }
        }
        const elementStyle = getComputedStyle(el);
        const elementMaskImage = elementStyle.maskImage
          || elementStyle.webkitMaskImage || "none";
        const elementMaskSource = singleMaskSource(elementStyle);
        const elementMaskAsset = dataSVGMaskAsset(
          elementStyle, ownBounds.width, ownBounds.height);
        const elementAttributes = attributes(el);
        if (elementMaskImage !== "none") {
          elementAttributes["data-exp-mask-image"] = elementMaskAsset
            ? "editable-data-svg" : "unsupported";
          if (elementMaskSource) {
            elementAttributes["data-exp-mask-source"] = elementMaskSource;
          }
        }
        return {
          tagName: el.tagName.toLowerCase(), path, rect: elementRect,
          style: style(el), attributes: elementAttributes, textFragments: directText(el),
          children, domIndex, renderedAsset: renderedAsset(el)
        };
      };
      const mediaQueryMatches = [];
      const mediaSeen = new Set();
      const inspectRules = rules => Array.from(rules || []).forEach(rule => {
        if (rule.type === CSSRule.MEDIA_RULE) {
          const condition = rule.conditionText || rule.media.mediaText || "";
          const row = `${condition} => ${matchMedia(condition).matches}`;
          if (!mediaSeen.has(row)) { mediaSeen.add(row); mediaQueryMatches.push(row); }
          inspectRules(rule.cssRules);
        } else if (rule.cssRules) {
          inspectRules(rule.cssRules);
        }
      });
      const notes = [];
      Array.from(document.styleSheets || []).forEach(sheet => {
        try { inspectRules(sheet.cssRules); }
        catch (error) { notes.push(`Stylesheet could not be inspected: ${sheet.href || "inline"}`); }
      });
      const body = document.body || document.documentElement;
      const bodyStyle = body ? getComputedStyle(body) : null;
      const bodyBottom = body ? body.getBoundingClientRect().bottom
        + (parseFloat(bodyStyle.marginBottom) || 0) : 0;
      const fixedBottom = body ? Array.from(body.querySelectorAll("*")).reduce((maximum, el) => {
        const cs = getComputedStyle(el);
        if (cs.position !== "fixed" || cs.display === "none"
            || cs.visibility === "hidden" || parseFloat(cs.opacity || "1") <= 0) return maximum;
        const bounds = el.getBoundingClientRect();
        return bounds.width > 0 && bounds.height > 0
          ? Math.max(maximum, bounds.bottom) : maximum;
      }, 0) : 0;
      const rootSnapshot = walk(body, "0");
      // A shrink-wrapped body can contain a viewport-sized ordinary descendant
      // (Storybook's preview root is one real example). scrollHeight is not a
      // trustworthy rendered bound, but every visible captured rectangle is.
      // Include their recursive bottom so the artboard cannot crop retained
      // artwork while still allowing genuinely short documents to stay short.
      const visibleTreeBottom = snapshot => {
        if (!snapshot || snapshot.style.display === "none"
            || snapshot.style.visibility === "hidden"
            || parseFloat(snapshot.style.opacity || "1") <= 0) return 0;
        const ownBottom = snapshot.rect[0][1] + snapshot.rect[1][1];
        return (snapshot.children || []).reduce((maximum, child) =>
          Math.max(maximum, visibleTreeBottom(child)), ownBottom);
      };
      return JSON.stringify({
        version: 1,
        sourceName: metadata.sourceName || document.title || "HTML import",
        sourceURL: metadata.sourceURL || location.href,
        title: document.title || metadata.sourceName || "HTML import",
        viewport: metadata.viewport,
        documentHeight: Math.max(bodyBottom, fixedBottom, visibleTreeBottom(rootSnapshot),
          document.documentElement.getBoundingClientRect().height),
        root: rootSnapshot,
        capturedNodeCount: nodeCount,
        devicePixelRatio: window.devicePixelRatio || 1,
        mediaQueryMatches,
        notes: notes.concat(nodeLimitReached
          ? [`Node limit reached; only the first ${metadata.maximumNodes} DOM elements were captured.`]
          : [])
      });
    })();
    """#
}

// MARK: - Pure snapshot mapper

@MainActor
struct RenderedHTMLImporter {
    static let artboardGap: CGFloat = 120

    func read(snapshotData: [Data],
              context: InteropContext = InteropContext()) throws -> InteropImportResult {
        try context.report(.decoding, completed: 0, total: snapshotData.count,
                           detail: "Reading browser snapshots")
        let decoder = JSONDecoder()
        let snapshots = try snapshotData.enumerated().map { index, data in
            if context.cancellation.isCancelled { throw InteropCodecError.cancelled }
            do {
                let snapshot = try decoder.decode(RenderedHTMLSnapshot.self, from: data)
                guard snapshot.version == RenderedHTMLSnapshot.formatVersion else {
                    throw InteropCodecError.unreadablePackage(
                        "rendered HTML snapshot version \(snapshot.version) is unsupported")
                }
                try context.report(.decoding, completed: index + 1, total: snapshotData.count,
                                   detail: snapshot.viewport.name)
                return snapshot
            } catch let error as InteropCodecError {
                throw error
            } catch {
                throw InteropCodecError.unreadablePackage(
                    "a rendered HTML snapshot was invalid: \(String(reflecting: error))")
            }
        }
        return try map(snapshots, context: context)
    }

    func map(_ snapshots: [RenderedHTMLSnapshot],
             context: InteropContext = InteropContext()) throws -> InteropImportResult {
        guard !snapshots.isEmpty else { throw InteropCodecError.noUsableArtwork }
        var report = InteropImportReport(format: .renderedHTML,
                                         sourceName: snapshots[0].sourceName)
        var page = CanvasPage(name: snapshots[0].sourceName)
        var nextX: CGFloat = 0
        let entryPath = URL(string: snapshots[0].sourceURL)?.lastPathComponent
            ?? snapshots[0].sourceURL
        var bridge = CodeBridgeManifest(
            connector: "local-html",
            source: CodeBridgeSource(displayName: snapshots[0].sourceName,
                                     entryPath: entryPath),
            baseline: CodeBridgeBaseline(
                snapshotVersion: RenderedHTMLSnapshot.formatVersion,
                metadata: ["viewportCount": String(snapshots.count)]),
            metadata: [
                "renderBoundary": "static-dom",
                "scriptPolicy": "preserve-opaque-no-writeback"
            ])

        for (index, snapshot) in snapshots.enumerated() {
            if context.cancellation.isCancelled { throw InteropCodecError.cancelled }
            try context.report(.mapping, completed: index, total: snapshots.count,
                               detail: snapshot.viewport.name)

            let width = max(1, snapshot.viewport.width)
            let height = max(1, snapshot.documentHeight)
            let boardOrigin = CGPoint(x: nextX, y: 0)
            let boardName = "\(snapshot.title.isEmpty ? snapshot.sourceName : snapshot.title) — \(snapshot.viewport.name)"
            let maximumNotedMediaQueries = 20
            let notedQueries = snapshot.mediaQueryMatches.prefix(maximumNotedMediaQueries)
            let omittedQueries = max(0, snapshot.mediaQueryMatches.count - notedQueries.count)
            let responsive = snapshot.mediaQueryMatches.isEmpty ? "" :
                "\nResolved media queries (\(snapshot.mediaQueryMatches.count)):\n"
                + notedQueries.joined(separator: "\n")
                + (omittedQueries > 0 ? "\n… \(omittedQueries) additional matches omitted from Notes." : "")
            let notes = "Rendered HTML import from \(snapshot.sourceURL) at \(Int(width)) × \(Int(snapshot.viewport.renderHeight)) CSS px. Responsive rules were resolved into this static artboard.\(responsive)"
            let artboard = Artboard(name: boardName,
                                    frame: CGRect(origin: boardOrigin,
                                                  size: CGSize(width: width, height: height)),
                                    notes: notes,
                                    background: backgroundPaint(snapshot.root.style))
            page.artboards.append(artboard)
            bridge.bindings.append(CodeBridgeBinding(
                expArtboardID: artboard.id,
                externalID: "viewport:\(snapshot.viewport.name)",
                externalKind: "rendered-viewport",
                sourcePath: entryPath,
                confidence: 1,
                ownership: "source",
                observedProperties: ["geometry", "background", "responsive-state"],
                writableProperties: [],
                metadata: [
                    "viewportName": snapshot.viewport.name,
                    "viewportWidth": String(Double(width)),
                    "renderHeight": String(Double(snapshot.viewport.renderHeight))
                ]))
            report.mapped("Artboard")

            let renderedBounds = visibleRenderedBounds(snapshot.root)
            let leftOverflow = max(0, -renderedBounds.minX)
            let rightOverflow = max(0, renderedBounds.maxX - width)
            if leftOverflow > 0.5 || rightOverflow > 0.5 {
                let sides = [leftOverflow > 0.5
                                 ? String(Int(ceil(leftOverflow))) + "px left" : nil,
                             rightOverflow > 0.5
                                 ? String(Int(ceil(rightOverflow))) + "px right" : nil]
                    .compactMap { $0 }.joined(separator: " and ")
                report.add(.information, .exact, category: "Viewport overflow",
                           message: "The rendered source extends " + sides
                               + " beyond this selected viewport. EXP retained the measured source geometry instead of inventing a responsive reflow.",
                           location: snapshot.viewport.name)
            }

            if let root = mapElement(snapshot.root, parentOrigin: .zero,
                                     boardOrigin: boardOrigin,
                                     ancestorTags: [],
                                     artboardID: artboard.id,
                                     viewportName: snapshot.viewport.name,
                                     sourcePath: entryPath,
                                     bindings: &bridge.bindings,
                                     report: &report) {
                page.nodes.append(root)
            }
            if !snapshot.notes.isEmpty {
                report.add(.information, .approximate, category: "Browser render",
                           message: snapshot.notes.joined(separator: " "),
                           location: snapshot.viewport.name)
            }
            if let runtimeMetadata = snapshot.runtimeMetadata {
                for (key, value) in runtimeMetadata {
                    bridge.source.metadata[key] = value
                }
            }
            if let ratio = snapshot.devicePixelRatio, abs(ratio - 1) > 0.001 {
                report.add(.information, .approximate, category: "Browser scale",
                           message: "WebKit rendered at device pixel ratio \(ratio). Geometry remains in CSS pixels; resolution-dependent assets may differ from a 1× browser.",
                           location: snapshot.viewport.name)
            }
            nextX += width + Self.artboardGap
        }

        try context.report(.finishing, completed: snapshots.count, total: snapshots.count,
                           detail: report.summary)
        return InteropImportResult(payload: InteropImportPayload(pages: [page]),
                                   report: report, codeBridges: [bridge])
    }

    private func visibleRenderedBounds(_ element: RenderedHTMLElement) -> CGRect {
        guard element.style.display != "none", element.style.visibility != "hidden",
              element.rect.width > 0, element.rect.height > 0 else { return .null }
        return element.children.reduce(element.rect) { bounds, child in
            let childBounds = visibleRenderedBounds(child)
            return childBounds.isNull ? bounds : bounds.union(childBounds)
        }
    }

    private func mapElement(_ element: RenderedHTMLElement,
                            parentOrigin: CGPoint,
                            boardOrigin: CGPoint,
                            ancestorTags: [String],
                            artboardID: UUID,
                            viewportName: String,
                            sourcePath: String,
                            bindings: inout [CodeBridgeBinding],
                            report: inout InteropImportReport) -> Node? {
        guard element.style.display != "none", element.style.visibility != "hidden",
              element.rect.width > 0, element.rect.height > 0 else { return nil }

        let origin = element.rect.origin
        let localFrame = CGRect(x: origin.x - parentOrigin.x + boardOrigin.x,
                                y: origin.y - parentOrigin.y + boardOrigin.y,
                                width: element.rect.width, height: element.rect.height)
        let semantics = nodeSemantics(for: element, ancestorTags: ancestorTags,
                                      report: &report)
        if let asset = element.renderedAsset {
            let svgSource = editableSVGSource(asset)
            if let source = svgSource,
               let imported = SVGImporter.importGroup(from: source),
               imported.frame.width > 0, imported.frame.height > 0 {
                let sx = localFrame.width / imported.frame.width
                let sy = localFrame.height / imported.frame.height
                var vector = SelectionTransform.scaled(imported, about: .zero,
                                                       sx: sx, sy: sy)
                vector.id = element.dataEXPID ?? vector.id
                vector.name = element.displayName
                vector.frame = localFrame
                vector.opacity = cssNumber(element.style.opacity) ?? 1
                vector.blendMode = blendMode(element.style.mixBlendMode)
                vector.semantics = semantics
                report.mapped(element.attributes["data-exp-mask-image"]?.hasPrefix("editable") == true
                    ? "Editable SVG mask" : "Editable SVG")
                reportSVGFeatures(source, location: element.path, report: &report)
                return recordingBinding(for: vector, element: element,
                                        artboardID: artboardID,
                                        viewportName: viewportName,
                                        sourcePath: sourcePath,
                                        bindings: &bindings)
            }
            if let data = displayableImageData(asset.data) {
                if svgSource != nil {
                    report.add(.information, .approximate, category: "SVG fallback",
                               message: "This SVG did not yield supported native geometry, so EXP retained its rendered pixels.",
                               location: element.attributes["src"] ?? element.path)
                }
                report.mapped(svgSource == nil ? "Image" : "Raster SVG fallback")
                let node = Node(id: element.dataEXPID ?? UUID(), name: element.displayName,
                                frame: localFrame,
                                opacity: cssNumber(element.style.opacity) ?? 1,
                                blendMode: blendMode(element.style.mixBlendMode),
                                semantics: semantics,
                                content: .image(ImageContent(
                                    data: data,
                                    naturalSize: CGSize(width: max(1, asset.naturalWidth),
                                                        height: max(1, asset.naturalHeight)))))
                return recordingBinding(for: node, element: element,
                                        artboardID: artboardID,
                                        viewportName: viewportName,
                                        sourcePath: sourcePath,
                                        bindings: &bindings)
            }
        }
        var children: [Node] = []
        let backgroundImage = backgroundImageNode(element, report: &report)
        if let surface = surfaceNode(element, backgroundImageHandled: backgroundImage != nil,
                                     report: &report) {
            children.append(surface)
        }
        if let backgroundImage { children.append(backgroundImage) }
        let mergedInlineText = richTextNode(element, report: &report)
        if let mergedInlineText {
            children.append(mergedInlineText)
        } else {
            children.append(contentsOf: element.textFragments.compactMap {
                textNode($0, tagName: element.tagName, parentOrigin: origin, report: &report)
            })
            children.append(contentsOf: element.children.compactMap {
                mapElement($0, parentOrigin: origin, boardOrigin: .zero,
                           ancestorTags: ancestorTags + [element.tagName.lowercased()],
                           artboardID: artboardID, viewportName: viewportName,
                           sourcePath: sourcePath, bindings: &bindings,
                           report: &report)
            })
        }

        let name = element.displayName

        if element.tagName.lowercased() == "img" {
            report.add(.warning, .unsupported, category: "Placeholder",
                       message: "The image box was preserved, but the browser did not provide safely decodable image pixels (the resource may be missing or blocked).",
                       location: element.attributes["src"] ?? element.path)
        }
        if element.style.transform != "none" {
            report.add(.warning, .unsupported, category: "Transform",
                       message: "A CSS transform is present; the measured bounding box was preserved without reconstructing the transform.",
                       location: element.path)
        }
        if element.style.filter != "none" {
            report.add(.warning, .unsupported, category: "Filter",
                       message: "A CSS filter is present; the editable box was preserved without the filter.",
                       location: element.path)
        }
        if element.attributes["data-exp-mask-image"] == "unsupported" {
            report.add(.warning, .unsupported, category: "Mask image",
                       message: "This CSS mask image could not be converted to bounded editable SVG geometry; EXP retained the underlying box paint.",
                       location: element.path)
        }

        if children.count == 1, var only = children.first,
           (mergedInlineText != nil
            || (element.textFragments.isEmpty && element.children.isEmpty)) {
            only.id = element.dataEXPID ?? only.id
            only.name = name
            only.frame = mergedInlineText == nil ? localFrame
                : only.frame.offsetBy(dx: localFrame.minX, dy: localFrame.minY)
            only.opacity = cssNumber(element.style.opacity) ?? 1
            only.blendMode = blendMode(element.style.mixBlendMode)
            only.semantics = semantics
            applyVisuallyHiddenState(to: &only, from: element, report: &report)
            return recordingBinding(for: only, element: element,
                                    artboardID: artboardID,
                                    viewportName: viewportName,
                                    sourcePath: sourcePath,
                                    bindings: &bindings)
        }

        // A text-only semantic element keeps its measured text child (the browser's
        // ink/line-box geometry) and an otherwise transparent wrapper. Put the
        // semantics on the editable text layer rather than making the wrapper the
        // only discoverable semantic object.
        let groupSemantics = semantics
        if children.count == 1, semantics != nil,
           case .text = children[0].content {
            children[0].semantics = semantics
        }
        report.mapped("DOM group")
        var group = Node(id: element.dataEXPID ?? UUID(), name: name, frame: localFrame,
                         opacity: cssNumber(element.style.opacity) ?? 1,
                         blendMode: blendMode(element.style.mixBlendMode),
                         semantics: groupSemantics,
                         content: .group(children: children))
        applyVisuallyHiddenState(to: &group, from: element, report: &report)
        return recordingBinding(for: group, element: element,
                                artboardID: artboardID,
                                viewportName: viewportName,
                                sourcePath: sourcePath,
                                bindings: &bindings)
    }

    /// Common `sr-only` utilities keep meaningful accessibility text in the DOM
    /// while clipping it out of visual layout with a 1×1 absolute box. EXP groups
    /// do not clip children by default, so importing the raw text made those labels
    /// spill across adjacent controls. Retain the layer and text, but mirror the
    /// browser's visual state by making that source-owned layer invisible.
    private func applyVisuallyHiddenState(to node: inout Node,
                                          from element: RenderedHTMLElement,
                                          report: inout InteropImportReport) {
        guard isVisuallyHiddenText(element) else { return }
        node.isVisible = false
        let text = collectedText(in: element)
        node.name = text.isEmpty ? "Visually hidden accessibility content"
            : "Visually hidden: \(String(text.prefix(48)))"
        report.mapped("Visually hidden accessibility text")
        report.add(.information, .exact, category: "Accessibility",
                   message: "Browser-clipped accessibility text was retained as a hidden EXP layer instead of being painted on the canvas.",
                   location: element.path)
    }

    private func isVisuallyHiddenText(_ element: RenderedHTMLElement) -> Bool {
        let clippedValues = Set(["hidden", "clip"])
        let clipped = clippedValues.contains(element.style.overflowX.lowercased())
            && clippedValues.contains(element.style.overflowY.lowercased())
        let positioned = ["absolute", "fixed"].contains(element.style.position.lowercased())
        return positioned && clipped
            && element.rect.width <= 2 && element.rect.height <= 2
            && !collectedText(in: element).isEmpty
    }

    private func collectedText(in element: RenderedHTMLElement) -> String {
        let pieces = element.textFragments.map(\.text)
            + element.children.map { collectedText(in: $0) }
        return normalizedText(pieces.joined(separator: " "))
    }

    // MARK: - Rendered semantics

    /// ARIA role values are fallback token lists. The first recognized concrete
    /// role wins; an unsupported-but-valid role must stop the search rather than
    /// letting EXP skip ahead to a later token it happens to understand.
    private static let concreteARIARoles: Set<String> = [
        "alert", "alertdialog", "application", "article", "banner", "blockquote",
        "button", "caption", "cell", "checkbox", "code", "columnheader",
        "combobox", "complementary", "contentinfo", "definition", "deletion",
        "dialog", "directory", "document", "emphasis", "feed", "figure", "form",
        "generic", "grid", "gridcell", "group", "heading", "img", "insertion",
        "link", "list", "listbox", "listitem", "log", "main", "marquee", "math",
        "menu", "menubar", "menuitem", "menuitemcheckbox", "menuitemradio", "meter",
        "navigation", "none", "note", "option", "paragraph", "presentation",
        "progressbar", "radio", "radiogroup", "region", "row", "rowgroup",
        "rowheader", "scrollbar", "search", "searchbox", "separator", "slider",
        "spinbutton", "status", "strong", "subscript", "superscript", "switch",
        "tab", "table", "tablist", "tabpanel", "term", "textbox", "time", "timer",
        "toolbar", "tooltip", "tree", "treegrid", "treeitem"
    ]

    private enum ExplicitRolePolicy {
        case any
        case allowed(Set<String>)
        case none
        case unverified
    }

    private func nodeSemantics(for element: RenderedHTMLElement,
                               ancestorTags: [String],
                               report: inout InteropImportReport) -> NodeSemantics? {
        let tag = element.tagName.lowercased()
        let implicit = implicitRole(for: element, ancestorTags: ancestorTags)
        let authored = element.attributes["role"]?.trimmingCharacters(
            in: .whitespacesAndNewlines)
        let aria = element.attributes.filter { $0.key.lowercased().hasPrefix("aria-") }
        let explicitToken = authored.flatMap { value in
            value.lowercased().split(whereSeparator: \Character.isWhitespace)
                .map(String.init).first(where: Self.concreteARIARoles.contains)
        }

        var conformance: Bool?
        var effective = implicit.token
        if let authored, !authored.isEmpty {
            guard let explicitToken else {
                report.add(.warning, .unsupported, category: "Semantics",
                           message: "The authored role token list contains no recognized concrete WAI-ARIA 1.2 role. It was retained as source data but not applied.",
                           location: element.path)
                return NodeSemantics(
                    authoredRole: authored, implicitRole: implicit.token,
                    ariaAttributes: aria, sourceTag: tag,
                    explicitRoleConformsToHost: false,
                    headingLevel: headingLevel(element, aria: aria))
            }
            switch explicitRolePolicy(for: element, ancestorTags: ancestorTags) {
            case .any:
                conformance = true
            case .allowed(let roles):
                conformance = roles.contains(explicitToken)
            case .none:
                conformance = false
            case .unverified:
                conformance = nil
            }
            if conformance == false {
                report.add(.warning, .unsupported, category: "Semantics",
                           message: "The authored role ‘\(explicitToken)’ is not allowed on <\(tag)> by ARIA in HTML. EXP retained it as source data and used the host element’s implicit role instead.",
                           location: element.path)
            } else {
                effective = explicitToken
                if conformance == nil {
                    report.add(.information, .approximate, category: "Semantics",
                               message: "The explicit role was retained, but this HTML host is outside E1’s verified ARIA-in-HTML element set, so host conformance is not claimed.",
                               location: element.path)
                }
            }
        }

        let normalizedEffective = effective == "image" ? "img" : effective
        let role = normalizedEffective.flatMap(AriaRole.init(rawValue:))
        if let effective, !["generic", "paragraph", "none", "presentation"].contains(effective),
           role == nil {
            report.add(.information, .unsupported, category: "Semantics",
                       message: "The rendered role ‘\(effective)’ has no native EXP role yet. Its token and ARIA attributes were retained without approximation.",
                       location: element.path)
        } else if role != nil {
            report.mapped("Semantic role")
        }
        if !aria.isEmpty {
            report.mapped("ARIA attribute", count: aria.count)
            report.add(.information, .exact, category: "Semantics",
                       message: "Authored aria-* states and properties were retained as structured, non-executable semantics; EXP did not invent component variants from their current values.",
                       location: element.path)
        }

        let hasMeaningfulImplicit = implicit.token.map {
            !["generic", "paragraph"].contains($0)
        } ?? false
        guard role != nil || hasMeaningfulImplicit || authored?.isEmpty == false || !aria.isEmpty
        else { return nil }
        return NodeSemantics(
            role: role, authoredRole: authored?.isEmpty == false ? authored : nil,
            implicitRole: implicit.token, ariaAttributes: aria, sourceTag: tag,
            explicitRoleConformsToHost: authored?.isEmpty == false ? conformance : nil,
            headingLevel: headingLevel(element, aria: aria))
    }

    private func headingLevel(_ element: RenderedHTMLElement,
                              aria: [String: String]) -> Int? {
        if let value = aria["aria-level"], let level = Int(value), level > 0 {
            return level
        }
        let tag = element.tagName.lowercased()
        guard tag.count == 2, tag.first == "h",
              let level = Int(String(tag.last!)), (1...6).contains(level) else { return nil }
        return level
    }

    private func hasAccessibleName(_ element: RenderedHTMLElement) -> Bool {
        ["aria-label", "aria-labelledby", "title"].contains {
            element.attributes[$0]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
    }

    private func implicitRole(for element: RenderedHTMLElement,
                              ancestorTags: [String]) -> (token: String?, reason: String) {
        let tag = element.tagName.lowercased()
        let sectioning = Set(["article", "aside", "main", "nav", "section"])
        let isNestedLandmark = ancestorTags.contains(where: sectioning.contains)
        switch tag {
        case "a": return (element.attributes["href"] == nil ? "generic" : "link", "host")
        case "article": return ("article", "host")
        case "aside":
            return (isNestedLandmark && !hasAccessibleName(element) ? "generic" : "complementary", "host")
        case "button": return ("button", "host")
        case "dialog": return ("dialog", "host")
        case "div", "span", "body": return ("generic", "host")
        case "figure": return ("figure", "host")
        case "footer": return (isNestedLandmark ? "sectionfooter" : "contentinfo", "ancestry")
        case "form": return (hasAccessibleName(element) ? "form" : "generic", "accessible name")
        case "h1", "h2", "h3", "h4", "h5", "h6": return ("heading", "host")
        case "header": return (isNestedLandmark ? "sectionheader" : "banner", "ancestry")
        case "hgroup": return ("group", "host")
        case "img":
            let alt = element.attributes["alt"]
            return (alt == "" && !hasAccessibleName(element) ? "presentation" : "img", "alternative text")
        case "li":
            return (ancestorTags.last.map { ["ol", "ul", "menu"].contains($0) } == true
                    ? "listitem" : "generic", "parent")
        case "main": return ("main", "host")
        case "menu", "ol", "ul": return ("list", "host")
        case "nav": return ("navigation", "host")
        case "option": return ("option", "host")
        case "output": return ("status", "host")
        case "p": return ("paragraph", "host")
        case "progress": return ("progressbar", "host")
        case "search": return ("search", "host")
        case "section": return (hasAccessibleName(element) ? "region" : "generic", "accessible name")
        case "select":
            let multiple = element.attributes["multiple"] != nil
            let size = Int(element.attributes["size"] ?? "") ?? 0
            return (multiple || size > 1 ? "listbox" : "combobox", "rendering mode")
        case "table": return ("table", "host")
        case "tbody", "thead", "tfoot": return ("rowgroup", "host")
        case "td": return (ancestorTags.contains("table") ? "cell" : nil, "table ancestry")
        case "textarea": return ("textbox", "host")
        case "th":
            if element.attributes["scope"] == "row" { return ("rowheader", "scope") }
            if element.attributes["scope"] == "col" { return ("columnheader", "scope") }
            return (ancestorTags.contains("table") ? "cell" : nil, "table ancestry")
        case "tr": return (ancestorTags.contains("table") ? "row" : nil, "table ancestry")
        case "input":
            switch element.attributes["type"]?.lowercased() ?? "text" {
            case "button", "image", "reset", "submit": return ("button", "input type")
            case "checkbox": return ("checkbox", "input type")
            case "radio": return ("radio", "input type")
            case "number": return ("spinbutton", "input type")
            case "range": return ("slider", "input type")
            case "search": return (element.attributes["list"] == nil ? "searchbox" : "combobox", "input type")
            case "text", "tel", "url", "email":
                return (element.attributes["list"] == nil ? "textbox" : "combobox", "input type")
            default: return (nil, "input type")
            }
        default: return (nil, "unverified host")
        }
    }

    /// Bounded transcription of the current ARIA-in-HTML table for the elements
    /// E1 already reverse-maps. Unknown hosts stay explicit and visibly unverified.
    private func explicitRolePolicy(for element: RenderedHTMLElement,
                                    ancestorTags: [String]) -> ExplicitRolePolicy {
        let tag = element.tagName.lowercased()
        func allowed(_ values: String...) -> ExplicitRolePolicy { .allowed(Set(values)) }
        switch tag {
        case "a" where element.attributes["href"] != nil:
            return allowed("button", "checkbox", "link", "menuitem", "menuitemcheckbox",
                           "menuitemradio", "option", "radio", "switch", "tab", "treeitem")
        case "a", "hgroup", "p", "table", "tbody", "thead", "tfoot", "output":
            return .any
        case "article": return allowed("application", "article", "document", "feed", "main", "none", "presentation", "region")
        case "aside": return allowed("complementary", "feed", "none", "note", "presentation", "region", "search")
        case "button": return allowed("button", "checkbox", "combobox", "gridcell", "link", "menuitem", "menuitemcheckbox", "menuitemradio", "option", "radio", "separator", "slider", "switch", "tab", "treeitem")
        case "dialog": return allowed("dialog", "alertdialog")
        case "div", "span": return .any
        case "figure": return .any
        case "footer": return allowed("contentinfo", "generic", "group", "none", "presentation")
        case "form": return allowed("form", "none", "presentation", "search")
        case "h1", "h2", "h3", "h4", "h5", "h6": return allowed("heading", "none", "presentation", "tab")
        case "header": return allowed("banner", "generic", "group", "none", "presentation")
        case "img": return allowed("button", "checkbox", "img", "image", "link", "math", "menuitem", "menuitemcheckbox", "menuitemradio", "meter", "option", "progressbar", "radio", "scrollbar", "separator", "slider", "switch", "tab", "treeitem")
        case "li" where ancestorTags.last.map({ ["ol", "ul", "menu"].contains($0) }) == true:
            return allowed("listitem")
        case "li": return .any
        case "main": return allowed("main")
        case "menu", "ol", "ul": return allowed("group", "list", "listbox", "menu", "menubar", "none", "presentation", "radiogroup", "tablist", "toolbar", "tree")
        case "nav": return allowed("menu", "menubar", "navigation", "none", "presentation", "tablist")
        case "option": return allowed("option")
        case "progress": return allowed("progressbar")
        case "search": return allowed("form", "group", "none", "presentation", "region", "search")
        case "section": return allowed("alert", "alertdialog", "application", "banner", "complementary", "contentinfo", "dialog", "document", "feed", "generic", "group", "log", "main", "marquee", "navigation", "none", "note", "presentation", "region", "search", "status", "tabpanel")
        case "select": return allowed("combobox", "menu")
        case "textarea": return allowed("textbox")
        case "td": return allowed("cell", "gridcell")
        case "th": return allowed("cell", "columnheader", "gridcell", "rowheader")
        case "tr": return allowed("row")
        default: return .unverified
        }
    }

    /// Record identity without granting write-back authority. DOM paths are a
    /// useful import receipt; an authored data-exp-id is stronger, but even that
    /// remains read-only until a connector supplies an explicit source contract.
    private func recordingBinding(for node: Node,
                                  element: RenderedHTMLElement,
                                  artboardID: UUID,
                                  viewportName: String,
                                  sourcePath: String,
                                  bindings: inout [CodeBridgeBinding]) -> Node {
        let authoredID = element.attributes["data-exp-id"]
        var observed = ["geometry", "visibility", "opacity", "blend-mode"]
        switch node.content {
        case .text:
            observed += ["text", "typography", "semantics"]
        case .image:
            observed += ["asset"]
        case .group:
            observed += ["structure"]
        default:
            observed += ["appearance"]
        }
        var metadata = [
            "viewportName": viewportName,
            "tagName": element.tagName.lowercased(),
            "domPath": element.path
        ]
        if let semantics = node.semantics {
            if let role = semantics.role?.rawValue { metadata["expAriaRole"] = role }
            if let authored = semantics.authoredRole { metadata["authoredRole"] = authored }
            if let implicit = semantics.implicitRole { metadata["implicitRole"] = implicit }
            metadata["ariaAttributeCount"] = String(semantics.ariaAttributes.count)
            metadata["semanticOwnership"] = "source-receipt"
        }
        bindings.append(CodeBridgeBinding(
            expNodeID: node.id,
            expArtboardID: artboardID,
            externalID: authoredID ?? element.path,
            externalKind: authoredID == nil ? "dom-path" : "data-exp-id",
            sourcePath: sourcePath,
            confidence: authoredID == nil ? 0.75 : 1,
            ownership: "source",
            observedProperties: observed,
            writableProperties: [],
            metadata: metadata))
        return node
    }

    /// AppKit can decode SVG, but EXP's placed-image contract is deliberately
    /// raster and self-contained. Normalize browser-captured SVG markup to PNG
    /// once at import so every canvas/export path sees the same safe bytes.
    private func displayableImageData(_ data: Data) -> Data? {
        let safeData = sanitizedSVGData(data) ?? data
        guard let image = NSImage(data: safeData), image.size.width > 0, image.size.height > 0 else {
            return nil
        }
        let prefix = String(decoding: safeData.prefix(64), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard prefix.hasPrefix("<svg") || prefix.hasPrefix("<?xml") else { return safeData }
        let width = min(8192, max(1, Int(ceil(image.size.width))))
        let height = min(8192, max(1, Int(ceil(image.size.height))))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = NSSize(width: width, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: width, height: height)).fill()
        image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
                   from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private func editableSVGSource(_ asset: RenderedHTMLAsset) -> Data? {
        if asset.mimeType.lowercased() == "image/svg+xml" {
            return sanitizedSVGData(asset.data)
        }
        if let source = asset.sourceURL,
           source.lowercased().hasPrefix("data:image/svg+xml") {
            return dataURI(source).flatMap(sanitizedSVGData)
        }
        return nil
    }

    /// The native importer deliberately supports a bounded SVG filter subset.
    /// Report every other primitive by name at the vector layer rather than
    /// silently suggesting the imported SVG is exact.
    private func reportSVGFeatures(_ data: Data, location: String,
                                   report: inout InteropImportReport) {
        guard let document = try? XMLDocument(data: data), let root = document.rootElement(),
              let nodes = try? root.nodes(forXPath: "//*[local-name()='filter']/*") else { return }
        let supported: Set<String> = [
            "feturbulence", "fecolormatrix", "fecomponenttransfer", "fefunca",
            "feblend", "feoffset", "fegaussianblur", "femorphology", "fecomposite",
            "feflood", "femerge", "femergenode"
        ]
        var unsupported = Set(nodes.compactMap { $0.name?.lowercased() }.filter {
            !supported.contains($0)
        })
        // feColorMatrix is native only as the internal channel/alpha stage of
        // EXP's turbulence effects. A general SourceGraphic 4x5 matrix is not
        // silently claimed as supported; it remains the next native SVG-effect
        // addition when a real import requires it.
        let turbulenceResults = Set(nodes.compactMap { node -> String? in
            guard let element = node as? XMLElement,
                  element.name?.lowercased() == "feturbulence" else { return nil }
            return element.attribute(forName: "result")?.stringValue
        })
        for case let matrix as XMLElement in nodes where matrix.name?.lowercased() == "fecolormatrix" {
            let input = matrix.attribute(forName: "in")?.stringValue ?? "SourceGraphic"
            if !turbulenceResults.contains(input) {
                unsupported.insert("feColorMatrix (general 4×5 matrix)")
            }
        }
        let unsupportedNames = unsupported.sorted()
        if !unsupportedNames.isEmpty {
            report.add(.warning, .unsupported, category: "SVG filter",
                       message: "Editable SVG geometry was retained, but these filter primitives still need native EXP effects: \(unsupportedNames.joined(separator: ", ")).",
                       location: location)
        }
    }

    /// SVG is allowed to reference network/file resources. The WebKit pass
    /// blocks those, and this second boundary ensures AppKit cannot re-request
    /// them while rasterizing captured markup or a CSS data image.
    private func sanitizedSVGData(_ data: Data) -> Data? {
        let prefix = String(decoding: data.prefix(128), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard prefix.hasPrefix("<svg") || prefix.hasPrefix("<?xml") else { return nil }
        guard let document = try? XMLDocument(data: data, options: [.nodePreserveAll]),
              let root = document.rootElement(), root.name?.lowercased() == "svg" else { return nil }

        func scrub(_ element: XMLElement) {
            for attribute in element.attributes ?? [] {
                let name = attribute.name?.lowercased() ?? ""
                let value = attribute.stringValue ?? ""
                if name.hasPrefix("on")
                    || (["href", "xlink:href", "src"].contains(name)
                        && !value.isEmpty && !value.hasPrefix("#")
                        && !value.lowercased().hasPrefix("data:"))
                    || (name == "style" && value.lowercased().contains("url(http")) {
                    element.removeAttribute(forName: attribute.name ?? "")
                }
            }
            for child in element.children?.compactMap({ $0 as? XMLElement }) ?? [] {
                let name = child.name?.lowercased() ?? ""
                if name == "script" || name == "foreignobject" { child.detach() }
                else { scrub(child) }
            }
        }
        scrub(root)
        return document.xmlData(options: [.nodeCompactEmptyElement])
    }

    private func surfaceNode(_ element: RenderedHTMLElement,
                             backgroundImageHandled: Bool,
                             report: inout InteropImportReport) -> Node? {
        let fill = paint(backgroundColor: element.style.backgroundColor,
                         backgroundImage: element.style.backgroundImage,
                         backgroundImageHandled: backgroundImageHandled,
                         location: element.path, report: &report)
        let widths = [element.style.borderTopWidth, element.style.borderRightWidth,
                      element.style.borderBottomWidth, element.style.borderLeftWidth]
            .compactMap(cssLength)
        let borderWidth = widths.max() ?? 0
        let borderColors = [element.style.borderTopColor, element.style.borderRightColor,
                            element.style.borderBottomColor, element.style.borderLeftColor]
            .compactMap(cssColor)
        var borderColor = borderColors.first ?? .clear
        let outlineWidth = element.style.outlineStyle == "none"
            ? 0 : cssLength(element.style.outlineWidth) ?? 0
        let usesOutline = borderWidth <= 0 && outlineWidth > 0
        if usesOutline {
            borderColor = cssColor(element.style.outlineColor) ?? .black
        }
        let hasFill = fill?.representativeColor.a ?? 0 > 0 || fill?.isGradient == true
        let isImagePlaceholder = element.tagName.lowercased() == "img"
            && !hasFill && borderWidth == 0
        guard hasFill || borderWidth > 0 || outlineWidth > 0
                || element.style.boxShadow != "none"
                || isImagePlaceholder else { return nil }

        if Set(widths.map { ($0 * 1_000).rounded() }).count > 1 {
            report.add(.warning, .approximate, category: "Border",
                       message: "Different per-side border widths were reduced to one editable border.",
                       location: element.path)
        }
        if borderWidth > 0 && outlineWidth > 0 {
            report.add(.warning, .approximate, category: "Outline",
                       message: "A CSS border and outline share this box; EXP retained the border because one editable shape supports one outline.",
                       location: element.path)
        } else if usesOutline {
            report.mapped("Outline")
            if abs(cssLength(element.style.outlineOffset) ?? 0) > 0.001 {
                report.add(.information, .approximate, category: "Outline",
                           message: "The CSS outline was retained as an outside EXP stroke without its separate outline offset.",
                           location: element.path)
            }
        }
        let radii = CornerRadii(
            topLeft: cssRadius(element.style.borderTopLeftRadius, in: element.rect.size),
            topRight: cssRadius(element.style.borderTopRightRadius, in: element.rect.size),
            bottomRight: cssRadius(element.style.borderBottomRightRadius, in: element.rect.size),
            bottomLeft: cssRadius(element.style.borderBottomLeftRadius, in: element.rect.size))
        let perCorner = radii.isUniform ? nil : radii
        if isImagePlaceholder { borderColor = RGBAColor(r: 0.45, g: 0.47, b: 0.52, a: 1) }
        let shape = RectangleShape(fill: isImagePlaceholder
                                       ? .solid(RGBAColor(r: 0.9, g: 0.91, b: 0.94, a: 1))
                                       : fill ?? .clear,
                                   cornerRadius: radii.topLeft,
                                   stroke: borderColor,
                                   strokeWidth: isImagePlaceholder ? 1
                                       : (usesOutline ? outlineWidth : borderWidth),
                                   strokeAlignment: usesOutline ? .outside : .inside,
                                   cornerRadii: perCorner)
        let effects = shadowEffects(element.style.boxShadow,
                                    location: element.path, report: &report)
        report.mapped("Box")
        return Node(name: "Background",
                    frame: CGRect(origin: .zero, size: element.rect.size),
                    effects: effects, isAbsoluteInAutoLayout: true,
                    content: .rectangle(shape))
    }

    /// Preserve a single CSS image layer while leaving the containing box, text,
    /// and descendants editable. SVG tiles become native geometry inside an
    /// editable mask group; raster sources keep the bounded pixel fallback.
    private func backgroundImageNode(_ element: RenderedHTMLElement,
                                     report: inout InteropImportReport) -> Node? {
        guard let url = singleBackgroundURL(element.style.backgroundImage) else { return nil }
        let source = element.backgroundAsset?.data ?? dataURI(url)
        guard let source else { return nil }
        if let svg = sanitizedSVGData(source),
           let imported = SVGImporter.importGroup(from: svg),
           let vector = editableSVGBackground(imported, size: element.rect.size,
                                              style: element.style,
                                              location: element.path, report: &report) {
            report.mapped("Editable SVG background")
            reportSVGFeatures(svg, location: element.path, report: &report)
            return vector
        }
        guard
              let png = renderedBackground(source: source, size: element.rect.size,
                                           style: element.style) else { return nil }
        report.mapped("Background image")
        return Node(name: "Background image",
                    frame: CGRect(origin: .zero, size: element.rect.size),
                    isAbsoluteInAutoLayout: true,
                    content: .image(ImageContent(data: png,
                        naturalSize: element.rect.size)))
    }

    private func editableSVGBackground(_ imported: Node, size: CGSize,
                                       style: RenderedHTMLComputedStyle,
                                       location: String,
                                       report: inout InteropImportReport) -> Node? {
        guard size.width > 0, size.height > 0,
              imported.frame.width > 0, imported.frame.height > 0 else { return nil }
        let tileSize = backgroundTileSize(style.backgroundSize,
                                          natural: imported.frame.size,
                                          container: size)
        guard tileSize.width > 0, tileSize.height > 0 else { return nil }
        let origin = backgroundTileOrigin(style.backgroundPosition,
                                          tile: tileSize, container: size)
        let repeatValue = style.backgroundRepeat.lowercased()
        let repeatsX = repeatValue == "repeat" || repeatValue == "repeat-x"
            || repeatValue.hasPrefix("repeat ")
        let repeatsY = repeatValue == "repeat" || repeatValue == "repeat-y"
            || repeatValue.hasSuffix(" repeat")
        var startX = origin.x
        var startY = origin.y
        if repeatsX { while startX > 0 { startX -= tileSize.width } }
        if repeatsY { while startY > 0 { startY -= tileSize.height } }
        let endX = repeatsX ? size.width : origin.x + tileSize.width
        let endY = repeatsY ? size.height : origin.y + tileSize.height

        let sx = tileSize.width / imported.frame.width
        let sy = tileSize.height / imported.frame.height
        var base = SelectionTransform.scaled(imported, about: .zero, sx: sx, sy: sy)
        base.frame.size = tileSize
        var tiles: [Node] = []
        var y = startY
        while y < endY, tiles.count <= 1_024 {
            var x = startX
            while x < endX, tiles.count <= 1_024 {
                var tile = Document.duplicatingNode(base)
                tile.name = "SVG tile"
                tile.frame.origin = CGPoint(x: x, y: y)
                tiles.append(tile)
                if !repeatsX { break }
                x += tileSize.width
            }
            if !repeatsY { break }
            y += tileSize.height
        }
        guard !tiles.isEmpty else { return nil }
        if tiles.count > 1_024 {
            report.add(.warning, .unsupported, category: "SVG background",
                       message: "This repeating SVG background requires more than 1,024 editable tiles; EXP used the bounded raster fallback.",
                       location: location)
            return nil
        }

        let radii = CornerRadii(
            topLeft: cssRadius(style.borderTopLeftRadius, in: size),
            topRight: cssRadius(style.borderTopRightRadius, in: size),
            bottomRight: cssRadius(style.borderBottomRightRadius, in: size),
            bottomLeft: cssRadius(style.borderBottomLeftRadius, in: size))
        let maskShape = RectangleShape(fill: .white, cornerRadius: radii.topLeft,
                                       strokeWidth: 0,
                                       cornerRadii: radii.isUniform ? nil : radii)
        let mask = Node(name: "Background clip",
                        frame: CGRect(origin: .zero, size: size),
                        isMaskShape: true, content: .rectangle(maskShape))
        return Node(name: "Background image",
                    frame: CGRect(origin: .zero, size: size),
                    isAbsoluteInAutoLayout: true, isMask: true,
                    content: .group(children: [mask] + tiles))
    }

    private func cssRadius(_ raw: String, in size: CGSize) -> CGFloat {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.hasSuffix("%"), let percent = Double(value.dropLast()) {
            return min(size.width, size.height) * CGFloat(percent) / 100
        }
        return cssLength(value) ?? 0
    }

    private func singleBackgroundURL(_ raw: String) -> String? {
        let layers = splitTopLevel(raw)
        guard layers.count == 1 else { return nil }
        let value = layers[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.lowercased().hasPrefix("url("), value.hasSuffix(")") else { return nil }
        return String(value.dropFirst(4).dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    private func dataURI(_ raw: String) -> Data? {
        guard raw.lowercased().hasPrefix("data:image/"),
              let comma = raw.firstIndex(of: ",") else { return nil }
        let header = raw[..<comma].lowercased()
        let payload = String(raw[raw.index(after: comma)...])
        if header.contains(";base64") { return Data(base64Encoded: payload) }
        guard let decoded = payload.removingPercentEncoding else { return nil }
        return Data(decoded.utf8)
    }

    private func renderedBackground(source: Data, size: CGSize,
                                    style: RenderedHTMLComputedStyle) -> Data? {
        let safeSource = sanitizedSVGData(source) ?? source
        guard let image = NSImage(data: safeSource), image.size.width > 0, image.size.height > 0,
              size.width > 0, size.height > 0 else { return nil }
        let pixelWidth = min(8192, max(1, Int(ceil(size.width))))
        let pixelHeight = min(8192, max(1, Int(ceil(size.height))))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixelWidth, pixelsHigh: pixelHeight,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        bitmap.size = NSSize(width: pixelWidth, height: pixelHeight)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        NSColor.clear.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)).fill()

        let target = CGSize(width: pixelWidth, height: pixelHeight)
        let tile = backgroundTileSize(style.backgroundSize,
                                      natural: image.size, container: target)
        let origin = backgroundTileOrigin(style.backgroundPosition,
                                          tile: tile, container: target)
        let repeatValue = style.backgroundRepeat.lowercased()
        let repeatsX = repeatValue == "repeat" || repeatValue == "repeat-x"
            || repeatValue.hasPrefix("repeat ")
        let repeatsY = repeatValue == "repeat" || repeatValue == "repeat-y"
            || repeatValue.hasSuffix(" repeat")
        var startX = origin.x
        var startY = origin.y
        if repeatsX { while startX > 0 { startX -= tile.width } }
        if repeatsY { while startY > 0 { startY -= tile.height } }
        let endX = repeatsX ? target.width : origin.x + tile.width
        let endY = repeatsY ? target.height : origin.y + tile.height
        var y = startY
        while y < endY, tile.height > 0 {
            var x = startX
            while x < endX, tile.width > 0 {
                image.draw(in: NSRect(x: x, y: target.height - y - tile.height,
                                      width: tile.width, height: tile.height),
                           from: .zero, operation: .sourceOver, fraction: 1,
                           respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
                if !repeatsX { break }
                x += tile.width
            }
            if !repeatsY { break }
            y += tile.height
        }
        NSGraphicsContext.restoreGraphicsState()
        return bitmap.representation(using: .png, properties: [:])
    }

    private func backgroundTileSize(_ raw: String, natural: CGSize,
                                    container: CGSize) -> CGSize {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "cover" || value == "contain" {
            let x = container.width / natural.width
            let y = container.height / natural.height
            let scale = value == "cover" ? max(x, y) : min(x, y)
            return CGSize(width: max(1, natural.width * scale),
                          height: max(1, natural.height * scale))
        }
        let parts = value.split(whereSeparator: \Character.isWhitespace).map(String.init)
        func dimension(_ token: String?, natural: CGFloat, container: CGFloat) -> CGFloat? {
            guard let token, token != "auto" else { return nil }
            if token.hasSuffix("%"), let percent = Double(token.dropLast()) {
                return max(1, container * CGFloat(percent) / 100)
            }
            return cssLength(token).map { max(1, $0) }
        }
        let width = dimension(parts.first, natural: natural.width, container: container.width)
        let height = dimension(parts.dropFirst().first, natural: natural.height,
                               container: container.height)
        if let width, let height { return CGSize(width: width, height: height) }
        if let width { return CGSize(width: width, height: width * natural.height / natural.width) }
        if let height { return CGSize(width: height * natural.width / natural.height, height: height) }
        return natural
    }

    private func backgroundTileOrigin(_ raw: String, tile: CGSize,
                                      container: CGSize) -> CGPoint {
        let parts = raw.lowercased().split(whereSeparator: \Character.isWhitespace).map(String.init)
        func position(_ token: String?, free: CGFloat) -> CGFloat {
            guard let token else { return 0 }
            switch token {
            case "left", "top": return 0
            case "center": return free / 2
            case "right", "bottom": return free
            default:
                if token.hasSuffix("%"), let percent = Double(token.dropLast()) {
                    return free * CGFloat(percent) / 100
                }
                return cssLength(token) ?? 0
            }
        }
        return CGPoint(x: position(parts.first, free: container.width - tile.width),
                       y: position(parts.dropFirst().first,
                                   free: container.height - tile.height))
    }

    private func textNode(_ fragment: RenderedHTMLTextFragment,
                          tagName: String,
                          parentOrigin: CGPoint,
                          report: inout InteropImportReport) -> Node? {
        let visibleText = normalizedText(fragment.text)
        guard !visibleText.isEmpty, let first = fragment.rects.first else { return nil }
        let bounds = fragment.rects.dropFirst().reduce(first) { $0.union($1) }
        let style = fragment.style
        let fontSize = cssLength(style.fontSize) ?? 16
        let (lineHeight, lineHeightUnit) = importedLineHeight(style.lineHeight)
        let font = resolvedFont(style.fontFamily, size: fontSize,
                                weight: style.fontWeight, style: style.fontStyle)
        if let unavailable = font.unavailablePrimary {
            report.add(.information, .approximate, category: "Typography",
                       message: "The CSS font ‘\(unavailable)’ was unavailable; EXP used the next installed fallback, ‘\(font.displayName)’.")
        }
        let run = TextRun(string: visibleText,
                          fontName: font.postScriptName,
                          fontSize: fontSize,
                          color: cssColor(style.color) ?? .black,
                          underline: style.textDecorationLine.contains("underline"))
        let align: TextAlign
        switch style.textAlign {
        case "center": align = .center
        case "right", "end": align = .right
        default: align = .left
        }
        let textCase: TextCase
        switch style.textTransform {
        case "uppercase": textCase = .upper
        case "lowercase": textCase = .lower
        case "capitalize": textCase = .title
        default: textCase = .none
        }
        let content = TextContent(runs: [run], align: align,
                                  lineHeight: lineHeight, lineHeightUnit: lineHeightUnit,
                                  tracking: cssLength(style.letterSpacing) ?? 0,
                                  box: .fixed, textCase: textCase,
                                  contentRole: textRole(tagName))
        if style.fontWeight != "400" && style.fontWeight != "normal"
            || style.fontStyle != "normal" {
            report.add(.information, .approximate, category: "Typography",
                       message: "CSS font weight/style was mapped to the closest installed face in the resolved family.")
        }
        report.mapped("Text")
        // Range.getClientRects() reports glyph/ink rectangles, not the complete
        // CSS line boxes. Their union already contains the inter-line offsets, so
        // add the missing leading symmetrically around the measured inline box.
        // Feeding the tight union
        // directly to TextKit made a 5 × 24px paragraph 114pt tall instead of 120,
        // excluding its last line. A 1pt vertical tolerance handles TextKit's
        // exact-boundary exclusion without changing browser-measured placement.
        // CoreText measured the same Helvetica-Bold headings up to 1.77pt wider
        // than WebKit, so retain a bounded 2pt width tolerance after rounding.
        let measuredLineHeight = fragment.rects.map(\.height).max() ?? bounds.height
        let sourceLineHeight = lineHeightInPixels(
            lineHeight, unit: lineHeightUnit, fontSize: fontSize,
            autoFallback: measuredLineHeight)
        let missingLineLeading = max(0, sourceLineHeight - measuredLineHeight)
        let fullLineBoxHeight = bounds.height + missingLineLeading
        let lineBoxTopAdjustment = missingLineLeading / 2
        let browserWidth = ceil(bounds.width) + 2
        let nativeWidth = fragment.rects.count == 1
            ? nativeSingleLineWidth(content) ?? browserWidth : browserWidth
        var textWidth = max(browserWidth, nativeWidth)
        let browserHeight = ceil(max(bounds.height, fullLineBoxHeight)) + 1
        // When a browser webfont is unavailable to AppKit, the installed
        // fallback can wrap a multiline paragraph one line earlier. Preserve
        // the browser's measured line count when a small bounded widening is
        // sufficient; otherwise retain the width and grow the native box so no
        // characters are silently excluded.
        if fragment.rects.count > 1,
           nativeTextLayoutHeight(content, width: textWidth) > browserHeight {
            let maximumWidth = browserWidth + min(80, max(16, browserWidth * 0.1))
            if nativeTextLayoutHeight(content, width: maximumWidth) <= browserHeight {
                var low = browserWidth
                var high = maximumWidth
                for _ in 0..<10 {
                    let candidate = (low + high) / 2
                    if nativeTextLayoutHeight(content, width: candidate) <= browserHeight {
                        high = candidate
                    } else {
                        low = candidate
                    }
                }
                textWidth = ceil(high)
            }
        }
        let widthDifference = textWidth - browserWidth
        let xAdjustment: CGFloat
        switch align {
        case .left: xAdjustment = 0
        case .center: xAdjustment = widthDifference / 2
        case .right: xAdjustment = widthDifference
        }
        let nativeHeight = nativeTextLayoutHeight(content, width: textWidth)
        return Node(name: String(visibleText.prefix(40)),
                    frame: CGRect(x: bounds.minX - parentOrigin.x - xAdjustment,
                                  y: bounds.minY - parentOrigin.y - lineBoxTopAdjustment,
                                  width: textWidth,
                                  height: max(browserHeight, nativeHeight + 1)),
                    content: .text(content))
    }

    private struct InlineTextSegment {
        var text: String
        var style: RenderedHTMLComputedStyle
        var attributes: [String: String]
        var tagName: String
        var forcedBreak = false
    }

    /// Merge a CSS block's inline-only descendants into the rich runs EXP already
    /// supports. Nested block/layout elements keep the normal node-tree mapping;
    /// this deliberately targets paragraphs/headings split by `a`/`strong`/`em`.
    private func richTextNode(_ element: RenderedHTMLElement,
                              report: inout InteropImportReport) -> Node? {
        let containerTags: Set<String> = [
            "p", "h1", "h2", "h3", "h4", "h5", "h6",
            "blockquote", "figcaption", "caption", "dt", "dd", "label"
        ]
        guard containerTags.contains(element.tagName.lowercased()),
              !element.children.isEmpty,
              element.children.allSatisfy(inlineTextTreeIsMergeable),
              let segments = orderedInlineSegments(element),
              segments.count > 1 else { return nil }

        var runs: [TextRun] = []
        var started = false
        var pendingSpace = false
        var sawForcedBreak = false
        for segment in segments {
            if segment.forcedBreak {
                if !runs.isEmpty { runs[runs.count - 1].string.append("\n") }
                pendingSpace = false
                started = false
                sawForcedBreak = true
                continue
            }

            var collapsed = ""
            for character in segment.text {
                if character.isWhitespace {
                    pendingSpace = true
                } else {
                    if pendingSpace, started { collapsed.append(" ") }
                    collapsed.append(character)
                    pendingSpace = false
                    started = true
                }
            }
            guard !collapsed.isEmpty else { continue }
            collapsed = transformed(collapsed, by: segment.style.textTransform)

            let size = cssLength(segment.style.fontSize) ?? 16
            let font = resolvedFont(segment.style.fontFamily, size: size,
                                    weight: segment.style.fontWeight,
                                    style: segment.style.fontStyle)
            if let unavailable = font.unavailablePrimary {
                report.add(.information, .approximate, category: "Typography",
                           message: "The CSS font ‘\(unavailable)’ was unavailable; EXP used the next installed fallback, ‘\(font.displayName)’.")
            }
            if segment.style.fontWeight != "400"
                && segment.style.fontWeight != "normal"
                || segment.style.fontStyle != "normal" {
                report.add(.information, .approximate, category: "Typography",
                           message: "CSS font weight/style was mapped to the closest installed face in the resolved family.")
            }
            let run = TextRun(
                string: collapsed,
                fontName: font.postScriptName,
                fontSize: size,
                color: cssColor(segment.style.color) ?? .black,
                underline: segment.style.textDecorationLine.contains("underline"),
                linkURL: segment.attributes["href"])
            append(run, mergingEquivalentStyleIn: &runs)

            if segment.attributes["href"]?.isEmpty == false {
                report.add(.information, .exact, category: "Semantics",
                           message: "An inline link destination was retained on its rich-text run for semantic handoff.",
                           location: element.path)
            }
        }
        guard !runs.isEmpty else { return nil }

        let parentTracking = cssLength(element.style.letterSpacing) ?? 0
        if segments.contains(where: {
            !$0.forcedBreak
                && abs((cssLength($0.style.letterSpacing) ?? 0) - parentTracking) > 0.001
        }) {
            report.add(.information, .approximate, category: "Typography",
                       message: "Different inline letter-spacing values were reduced to the paragraph's tracking value.",
                       location: element.path)
        }
        let fontSize = cssLength(element.style.fontSize) ?? runs[0].fontSize
        let (lineHeight, lineHeightUnit) = importedLineHeight(element.style.lineHeight)
        let align: TextAlign
        switch element.style.textAlign {
        case "center": align = .center
        case "right", "end": align = .right
        default: align = .left
        }
        let content = TextContent(runs: runs, align: align,
                                  lineHeight: lineHeight, lineHeightUnit: lineHeightUnit,
                                  tracking: parentTracking, box: .fixed,
                                  textCase: .none,
                                  contentRole: textRole(element.tagName))
        if sawForcedBreak {
            report.add(.information, .exact, category: "Typography",
                       message: "An HTML line break was retained inside one rich text box.",
                       location: element.path)
        }
        report.mapped("Text")
        let browserWidth = ceil(element.rect.width) + 2
        let sourceLineHeight = lineHeightInPixels(
            lineHeight, unit: lineHeightUnit, fontSize: fontSize,
            autoFallback: fontSize)
        let nativeWidth = !content.plainString.contains("\n")
            && element.rect.height <= sourceLineHeight * 1.5
            ? nativeSingleLineWidth(content) ?? browserWidth : browserWidth
        let textWidth = max(browserWidth, nativeWidth)
        let textHeight = max(ceil(element.rect.height) + 1,
                             nativeTextLayoutHeight(content, width: textWidth) + 1)
        let widthDifference = textWidth - browserWidth
        let xAdjustment: CGFloat
        switch align {
        case .left: xAdjustment = 0
        case .center: xAdjustment = widthDifference / 2
        case .right: xAdjustment = widthDifference
        }
        return Node(name: String(content.plainString.prefix(40)),
                    frame: CGRect(x: -xAdjustment, y: 0,
                                  width: textWidth,
                                  height: textHeight),
                    content: .text(content))
    }

    /// Browser Range rectangles reflect the source webfont's ink. EXP must lay
    /// the same string out with the resolved installed fallback, which can be a
    /// few points wider. Widen only true single-line boxes so native TextKit does
    /// not clip glyphs or show an overflow badge; wrapped browser lines retain
    /// their captured width and line breaks.
    private func nativeSingleLineWidth(_ content: TextContent) -> CGFloat? {
        guard !content.plainString.contains("\n") else { return nil }
        let attributed = nativeAttributedString(content)
        guard attributed.length > 0 else { return nil }
        return ceil(attributed.size().width) + 2
    }

    private func nativeTextLayoutHeight(_ content: TextContent,
                                        width: CGFloat) -> CGFloat {
        guard width > 1 else { return 1 }
        let attributed = nativeAttributedString(content)
        guard attributed.length > 0 else { return 1 }
        let bounds = attributed.boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading])
        return max(1, ceil(bounds.height))
    }

    private func nativeAttributedString(_ content: TextContent)
        -> NSMutableAttributedString {
        let paragraph = NSMutableParagraphStyle()
        switch content.align {
        case .left: paragraph.alignment = .left
        case .center: paragraph.alignment = .center
        case .right: paragraph.alignment = .right
        }
        switch content.lineHeightUnit {
        case .auto:
            paragraph.lineHeightMultiple = 0
        case .multiple:
            paragraph.lineHeightMultiple = content.lineHeight
        case .px:
            paragraph.minimumLineHeight = content.lineHeight
            paragraph.maximumLineHeight = content.lineHeight
        case .em:
            let height = content.lineHeight * content.firstRun.fontSize
            paragraph.minimumLineHeight = height
            paragraph.maximumLineHeight = height
        }
        let attributed = NSMutableAttributedString()
        for run in content.runs {
            let lower = run.fontName.lowercased()
            let reloadable = !run.fontName.hasPrefix(".")
                ? NSFont(name: run.fontName, size: run.fontSize) : nil
            var font = reloadable ?? NSFont.systemFont(ofSize: run.fontSize)
            if reloadable == nil {
                let manager = NSFontManager.shared
                if lower.contains("bold") {
                    font = manager.convert(font, toHaveTrait: .boldFontMask)
                }
                if lower.contains("italic") || lower.contains("oblique") {
                    font = manager.convert(font, toHaveTrait: .italicFontMask)
                }
            }
            attributed.append(NSAttributedString(
                string: content.textCase.apply(run.string),
                attributes: [.font: font, .paragraphStyle: paragraph,
                             .kern: content.tracking]))
        }
        return attributed
    }

    private func inlineTextTreeIsMergeable(_ element: RenderedHTMLElement) -> Bool {
        if element.tagName.lowercased() == "br" { return true }
        guard element.style.display == "inline" || element.style.display == "contents",
              !hasInlineBoxDecoration(element),
              element.children.allSatisfy(inlineTextTreeIsMergeable) else { return false }
        return true
    }

    private func hasInlineBoxDecoration(_ element: RenderedHTMLElement) -> Bool {
        if element.style.backgroundImage != "none" { return true }
        if (cssColor(element.style.backgroundColor)?.a ?? 0) > 0 { return true }
        if element.style.boxShadow != "none" { return true }
        return [element.style.borderTopWidth, element.style.borderRightWidth,
                element.style.borderBottomWidth, element.style.borderLeftWidth]
            .contains { (cssLength($0) ?? 0) > 0 }
    }

    private func orderedInlineSegments(_ element: RenderedHTMLElement)
        -> [InlineTextSegment]? {
        struct OrderedPart {
            var index: Int
            var segments: [InlineTextSegment]
        }
        var parts: [OrderedPart] = []
        for fragment in element.textFragments {
            guard let index = fragment.domIndex else { return nil }
            parts.append(OrderedPart(
                index: index,
                segments: [InlineTextSegment(text: fragment.text,
                                             style: fragment.style,
                                             attributes: element.attributes,
                                             tagName: element.tagName)]))
        }
        for child in element.children {
            guard let index = child.domIndex else { return nil }
            if child.tagName.lowercased() == "br" {
                parts.append(OrderedPart(
                    index: index,
                    segments: [InlineTextSegment(text: "", style: child.style,
                                                 attributes: child.attributes,
                                                 tagName: child.tagName,
                                                 forcedBreak: true)]))
            } else {
                guard let childSegments = orderedInlineSegments(child) else { return nil }
                parts.append(OrderedPart(index: index, segments: childSegments))
            }
        }
        return parts.sorted { $0.index < $1.index }.flatMap(\.segments)
    }

    private func transformed(_ text: String, by cssTransform: String) -> String {
        switch cssTransform {
        case "uppercase": return text.localizedUppercase
        case "lowercase": return text.localizedLowercase
        case "capitalize": return text.localizedCapitalized
        default: return text
        }
    }

    private func append(_ run: TextRun, mergingEquivalentStyleIn runs: inout [TextRun]) {
        if !runs.isEmpty {
            let prior = runs[runs.count - 1]
            if prior.fontName == run.fontName,
               prior.fontSize == run.fontSize,
               prior.color == run.color,
               prior.underline == run.underline,
               prior.linkURL == run.linkURL {
                runs[runs.count - 1].string += run.string
                return
            }
        }
        runs.append(run)
    }

    private func backgroundPaint(_ style: RenderedHTMLComputedStyle) -> Paint {
        if let gradient = gradient(style.backgroundImage) { return gradient }
        return .solid(cssColor(style.backgroundColor) ?? .white)
    }

    private func paint(backgroundColor: String, backgroundImage: String,
                       backgroundImageHandled: Bool,
                       location: String,
                       report: inout InteropImportReport) -> Paint? {
        if let gradient = gradient(backgroundImage) {
            report.mapped("Gradient")
            return gradient
        }
        if !backgroundImageHandled && backgroundImage != "none" && !backgroundImage.isEmpty {
            report.add(.warning, .unsupported, category: "Background image",
                       message: "The CSS background image is not yet editable; the resolved background color was kept.",
                       location: location)
        }
        return cssColor(backgroundColor).map(Paint.solid)
    }

    private func gradient(_ raw: String) -> Paint? {
        guard raw.lowercased().hasPrefix("linear-gradient("), raw.hasSuffix(")") else { return nil }
        let body = String(raw.dropFirst("linear-gradient(".count).dropLast())
        let parts = splitTopLevel(body)
        guard parts.count >= 3 else { return nil }
        let angleText = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        guard angleText.hasSuffix("deg"),
              let cssAngle = Double(angleText.dropLast(3).trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let stops: [GradientStop] = parts.dropFirst().enumerated().compactMap { index, rawStop in
            guard let color = cssColor(rawStop) else { return nil }
            let percent = rawStop.range(of: #"(-?[0-9.]+)%\s*$"#, options: .regularExpression)
                .flatMap { Double(rawStop[$0].dropLast().trimmingCharacters(in: .whitespaces)) }
            let fallback = Double(index) / Double(max(1, parts.count - 2))
            return GradientStop(color: color, position: min(1, max(0, (percent ?? fallback * 100) / 100)))
        }
        guard stops.count >= 2 else { return nil }
        var expAngle = cssAngle - 90
        while expAngle < 0 { expAngle += 360 }
        while expAngle >= 360 { expAngle -= 360 }
        return .gradient(GradientFill(kind: .linear, stops: stops, angle: expAngle))
    }

    private func shadowEffects(_ raw: String, location: String,
                               report: inout InteropImportReport) -> [Effect] {
        guard raw != "none", !raw.isEmpty else { return [] }
        let shadows = splitTopLevel(raw)
        if shadows.count > 1 {
            report.add(.warning, .approximate, category: "Shadow",
                       message: "Multiple CSS shadows were reduced to the first editable shadow.",
                       location: location)
        }
        let first = shadows[0]
        let kind: Effect.Kind = first.contains("inset") ? .innerShadow : .dropShadow
        let color = cssColor(first) ?? RGBAColor(r: 0, g: 0, b: 0, a: 0.33)
        let scrubbed = first
            .replacingOccurrences(of: #"rgba?\([^)]*\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "inset", with: "")
        let values = scrubbed.split(whereSeparator: \Character.isWhitespace).compactMap {
            cssLength(String($0))
        }
        guard values.count >= 2 else { return [] }
        report.mapped("Shadow")
        return [Effect(kind: kind, color: color, dx: values[0], dy: values[1],
                       blur: values.count > 2 ? values[2] : 0,
                       spread: values.count > 3 ? values[3] : 0)]
    }

    private func textRole(_ rawTag: String) -> TextContentRole {
        switch rawTag.lowercased() {
        case "p": return .paragraph
        case "h1": return .heading1
        case "h2": return .heading2
        case "h3": return .heading3
        case "h4": return .heading4
        case "h5": return .heading5
        case "h6": return .heading6
        default: return .plain
        }
    }

    private func normalizedText(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct ResolvedFont {
        var postScriptName: String
        var displayName: String
        var unavailablePrimary: String?
    }

    /// CSS exposes an ordered fallback list, while `getComputedStyle` retains an
    /// unavailable first family. WebKit rendered with the next installed face;
    /// choosing that same candidate prevents EXP from silently reflowing with SF.
    private func resolvedFont(_ raw: String, size: CGFloat,
                              weight: String, style: String) -> ResolvedFont {
        let candidates = splitTopLevel(raw).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }.filter { !$0.isEmpty }
        let manager = NSFontManager.shared
        let wantsBold = weight.lowercased() == "bold"
            || (Double(weight).map { $0 >= 600 } ?? false)
        let wantsItalic = style.lowercased() == "italic"
            || style.lowercased() == "oblique"
        var unavailablePrimary: String?

        for (index, candidate) in candidates.enumerated() {
            let lower = candidate.lowercased()
            let base: NSFont?
            switch lower {
            case "sans-serif", "system-ui", "-apple-system", "blinkmacsystemfont":
                base = .systemFont(ofSize: size)
            case "serif":
                base = NSFont(name: "Times New Roman", size: size)
                    ?? NSFont(name: "Times", size: size)
            case "monospace":
                base = NSFont(name: "Menlo", size: size)
                    ?? .monospacedSystemFont(ofSize: size, weight: .regular)
            default:
                base = NSFont(name: candidate, size: size)
                    ?? manager.font(withFamily: candidate, traits: [], weight: 5,
                                    size: size)
            }
            guard var selected = base else {
                if index == 0 { unavailablePrimary = candidate }
                continue
            }
            if wantsBold { selected = manager.convert(selected, toHaveTrait: .boldFontMask) }
            if wantsItalic { selected = manager.convert(selected, toHaveTrait: .italicFontMask) }
            return ResolvedFont(postScriptName: selected.fontName,
                                displayName: selected.familyName ?? candidate,
                                unavailablePrimary: index > 0 ? unavailablePrimary : nil)
        }

        var fallback = NSFont.systemFont(ofSize: size)
        if wantsBold { fallback = manager.convert(fallback, toHaveTrait: .boldFontMask) }
        if wantsItalic { fallback = manager.convert(fallback, toHaveTrait: .italicFontMask) }
        return ResolvedFont(postScriptName: fallback.fontName,
                            displayName: fallback.familyName ?? "System",
                            unavailablePrimary: candidates.first)
    }

    private func cssNumber(_ raw: String) -> Double? {
        Double(raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func cssLength(_ raw: String) -> CGFloat? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "normal" || value == "auto" { return nil }
        let stripped = value.hasSuffix("px") ? String(value.dropLast(2)) : value
        return Double(stripped).map { CGFloat($0) }
    }

    /// Preserve CSS line-height semantics instead of turning `normal` into an
    /// invented fixed pixel value. `getComputedStyle` normally resolves authored
    /// lengths/multipliers to px; the extra branches keep synthetic/older
    /// snapshots honest when they retain the authored unit.
    private func importedLineHeight(_ raw: String)
        -> (value: CGFloat, unit: LineHeightUnit) {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value.isEmpty || value == "normal" || value == "auto" {
            // 1.3 is only the seed shown if the user later changes Auto to ×.
            // Auto itself ignores this number and uses the resolved font metrics.
            return (1.3, .auto)
        }
        if value.hasSuffix("px"), let number = Double(value.dropLast(2)) {
            return (CGFloat(number), .px)
        }
        if value.hasSuffix("em"), let number = Double(value.dropLast(2)) {
            return (CGFloat(number), .em)
        }
        if value.hasSuffix("%"), let number = Double(value.dropLast()) {
            return (CGFloat(number) / 100, .multiple)
        }
        if let number = Double(value) {
            return (CGFloat(number), .multiple)
        }
        return (1.3, .auto)
    }

    private func lineHeightInPixels(_ value: CGFloat, unit: LineHeightUnit,
                                    fontSize: CGFloat,
                                    autoFallback: CGFloat) -> CGFloat {
        switch unit {
        case .auto: return autoFallback
        case .multiple, .em: return value * fontSize
        case .px: return value
        }
    }

    private func cssColor(_ raw: String) -> RGBAColor? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if value == "transparent" { return .clear }
        if value.hasPrefix("#") {
            let hex = String(value.dropFirst())
            guard hex.count == 6 || hex.count == 8,
                  let bits = UInt64(hex, radix: 16) else { return nil }
            let hasAlpha = hex.count == 8
            let shift = hasAlpha ? 8 : 0
            return RGBAColor(r: Double((bits >> (16 + shift)) & 0xff) / 255,
                             g: Double((bits >> (8 + shift)) & 0xff) / 255,
                             b: Double((bits >> shift) & 0xff) / 255,
                             a: hasAlpha ? Double(bits & 0xff) / 255 : 1)
        }
        guard let open = value.firstIndex(of: "("), let close = value.firstIndex(of: ")"),
              value[..<open].hasSuffix("rgb") || value[..<open].hasSuffix("rgba") else { return nil }
        let parts = value[value.index(after: open)..<close]
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count >= 3 else { return nil }
        func channel(_ part: String) -> Double? {
            if part.hasSuffix("%") { return Double(part.dropLast()).map { $0 / 100 } }
            return Double(part).map { $0 / 255 }
        }
        guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
        let a = parts.count > 3 ? Double(parts[3]) ?? 1 : 1
        return RGBAColor(r: min(1, max(0, r)), g: min(1, max(0, g)),
                         b: min(1, max(0, b)), a: min(1, max(0, a)))
    }

    private func splitTopLevel(_ raw: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        for character in raw {
            if character == "(" { depth += 1 }
            if character == ")" { depth = max(0, depth - 1) }
            if character == "," && depth == 0 {
                result.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func blendMode(_ raw: String) -> BlendMode {
        switch raw {
        case "multiply": return .multiply
        case "screen": return .screen
        case "overlay": return .overlay
        case "darken": return .darken
        case "lighten": return .lighten
        case "color-dodge": return .colorDodge
        case "color-burn": return .colorBurn
        case "soft-light": return .softLight
        case "hard-light": return .hardLight
        case "difference": return .difference
        case "exclusion": return .exclusion
        case "hue": return .hue
        case "saturation": return .saturation
        case "color": return .color
        case "luminosity": return .luminosity
        default: return .normal
        }
    }
}
