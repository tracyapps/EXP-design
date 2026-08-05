# Rendered-HTML Import Contract (Chunk E / E0)

Status: **E0 complete 2026-08-01; E1b local-file vertical slice implemented
2026-08-03, with owner visual acceptance pending.** The
contract is owner-accepted, the bounded spike's trust questions are settled, and the
verified §8 element table is complete. E1a now supplies the production snapshot
contract, read-only extraction script, and first browser-neutral editable mapper.
E1b adds the sandbox-correct folder/entry-file UI, non-persistent local-only
`WKWebView` capture, real fixture-2 Phone/Desktop proof, cancellation, and
import-wide node/payload enforcement. The remote Sources/import-session flow is next.
Remaining ARIA state and explicit-role/host decisions stay visibly unverified and
must be checked against WAI-ARIA 1.2 / ARIA in HTML before that mapper reconstructs
semantics. See ROADMAP.md E1 for the live implementation sequence.

## 0. What this is, and what it refuses to claim

EXP imports a **rendered document** — a box tree plus resolved styles plus
authored semantics — and turns it into editable EXP nodes. That is the whole
promise.

It is NOT source-code import. EXP does not recover your components, your CSS
architecture, your class names, your build, or your framework. It does not claim
pixel-perfection. A rendered import is a **lossy read of a faithful render**, and
every loss is named in the Import Report rather than quietly absorbed.

This follows the project's standing rule: a feature earns its place by making the
exported artifact more faithful, not by making the canvas more impressive. An
import that silently guesses is worse than one that imports less and says so.

## 1. Supported input boundary

Owner decision, 2026-07-29:

| Input | Supported | Notes |
|---|---|---|
| Local `.html` file | Yes | Assets resolve relative to the file's directory; the **directory** is the unit of trust. In the sandbox-correct E1b UI the person chooses that folder, then its HTML entry file, so sibling-resource access is explicit rather than inferred from a file-only grant |
| Local folder of `.html` files | Yes | One artboard per file, all on **one** canvas page (§1.1) |
| `http(s)` URL | Yes | Gated by the trust flow in §4–§5 |
| Pasted HTML/CSS fragment | **No** (deferred) | No `<head>`, no font context, ambiguous root box; fidelity would be materially worse and the report mostly caveats |
| React / Vue / Svelte source | **No** | Render to DOM first. Never AST-to-pixels |
| Authenticated pages | **No** — see §6 | No credentials stored, ever |

**Content type is checked before rendering.** Non-HTML responses are rejected up
front with a plain-English reason. Redirects are followed and the **final** URL is
recorded, so an import can never silently describe a different document than the
one requested.

### 1.1 Viewports — one import, several widths

Owner decision, 2026-08-01: **the import sheet offers a multi-select of viewport
widths, not a single choice.** One import of one page can produce phone, tablet, and
desktop artboards together — which is the actual reason a designer reaches for a
rendered import, to see how a responsive component resolves, not to capture one width
and repeat the whole flow twice more.

- Widths come from the existing `ArtboardPreset` list, **filtered to the `Mobile` and
  `Web` groups** (Phone 393, Phone Small 375, Tablet 834, Web 1280, Desktop 1440).
  `Square`, `Story`, `Slide 16:9`, `A4 Portrait`, and `Letter` are page and canvas
  sizes, not browser viewports; offering them would invite a render nobody wants.
  Owner: say so if you want the unfiltered list.
- **Desktop 1440 is pre-selected, and it is the only one pre-selected.** Defaulting to
  three viewports would triple the cost of the common case without being asked.
- Each preset's **height is used for the render, not for the artboard.** `vh`/`dvh`
  units and height media queries resolve against it; the artboard is then cut to
  `preset width × full document height`. The Import Report names the height each
  viewport resolved against, because "why is this `100vh` block 852pt tall" is
  otherwise unanswerable after the fact.
- **CSS geometry is scale-independent, but WebKit's backing device pixel ratio is
  not publicly settable.** Selecting Phone changes layout width, while every measured
  box still maps as 1 CSS px = 1 EXP pt (§3). On a Retina Mac the production spike
  observed `devicePixelRatio == 2`; EXP records and reports the actual value because
  resolution-dependent images/media may select different bytes. It does not use a
  private API to force 1× or silently claim that it did.
- **Responsive behaviour is read, then discarded — owner decision, 2026-08-01.**
  Media queries exist to resolve each viewport's layout and nothing more. EXP nodes
  never carry breakpoints, container queries, fluid rules, or any other live
  responsive behaviour; three viewports produce three independent static artboards,
  not one artboard that reflows. Where a media query materially changed a layout, the
  Import Report says so in prose and the fact can be kept as artboard **notes** text
  — description, not mechanism. Rationale, and it is the project's standing one: EXP
  is a fidelity tool, and responsive behaviour belongs in code, where it is written,
  tested, and shipped. Modelling it on canvas would be building a worse version of
  CSS inside a design tool and would make the exported artifact *less* faithful, not
  more, because the export would then have to invent breakpoint syntax nobody asked
  for. This also bounds E1: the importer never has to decide which of several
  competing rules "wins," because it only ever reads a resolved render.
- **Folder × viewport is a matrix.** Six files at three viewports is eighteen
  artboards on one canvas page — files down, viewports across, so a row reads as one
  document across widths. The sheet states the resulting artboard count before the
  import runs, and the §7 caps apply to the import as a whole, which is exactly when
  they start to bite.

## 2. Browser-engine isolation

`WKWebView`, as pencilled in by V2-INTEROP-PLAN. Isolation rules:

- **Non-persistent data store** (`WKWebsiteDataStore.nonPersistent()`). No
  cookies, `localStorage`, or cache survive an import, and two imports of the same
  URL cannot influence each other.
- **JavaScript enabled, on a leash.** A built prototype frequently needs JS to
  render at all, so refusing it would fail the actual use case. But: a hard render
  deadline (§7), navigation confined to the initial document (any attempt to
  navigate away is blocked and reported), no form submission, no popups or new
  windows, no downloads.
- **The extraction script is injected, never fetched**, so the import's own
  instrumentation is never a network dependency.
- **Local file reads are scoped** to the chosen file's directory through a
  security-scoped resource. A local page cannot pull `../../..` out of `$HOME`.
- The web view is created for the import, used, and torn down.

**Static Storybook transport finding, 2026-08-03.** Ordinary saved HTML works
through EXP's receipt-producing custom scheme, but production Storybook runtimes
commonly bootstrap through ES modules and webpack chunks that WebKit will not
execute reliably on a custom scheme. Storybook therefore uses a narrower local
HTTP compatibility seam: an OS-assigned port bound only to `127.0.0.1`, an
unguessable per-import route token, GET/HEAD only, the same selected-folder
confinement and byte caps, and a content rule that permits only that exact
origin/token prefix while continuing to block every other `http(s)` and `file`
request. The listener and non-persistent web view are destroyed when the import
finishes. Capture additionally waits for Storybook's `sb-show-main` state and a
populated, laid-out `#storybook-root`; error/no-preview/timeout states fail the
story clearly instead of manufacturing an empty one-pixel artboard.

Storybook play functions may mount visible UI outside `#storybook-root` (modals,
popovers, and similar portals). Readiness therefore has to remain stable across
the whole body, and extraction walks all rendered body children. `display:none`
and `visibility:hidden` shells are omitted before they consume the bounded node
budget. A zero-box `display:contents`/portal wrapper receives the union of its
visible children, while visible fixed-position content may extend the artboard to
the render viewport. This preserves the browser result without inventing runtime
interaction behavior in EXP.

**Open mechanism question, to be settled by the §10 spike.** `WKWebView` has no
delegate that reports *subresource* requests — `WKNavigationDelegate` sees navigations
only. That matters because §4's pass 1 has to do two things at once: **block**
everything and **record** what was attempted. Blocking alone is easy
(`WKContentRuleList`), and it is the half that carries the privacy guarantee. Recording
is the open part, and the candidate mechanisms trade off differently:

| Mechanism | Records | Limitation |
|---|---|---|
| `WKContentRuleList` block-all | Nothing | Guarantees the block; gives no manifest |
| Custom scheme (`WKURLSchemeHandler`) serving the document | Every request routed through it | Absolute `http(s)` URLs in the page bypass the scheme entirely |
| Injected instrumentation (`fetch`/XHR/`Image`/element setters) | Script-initiated requests | Blind to markup-declared resources; can be defeated by a page that captures the originals first |
| DOM + CSSOM walk after settle | Declared resources (`src`, `srcset`, `@font-face`, `background-image`) | Blind to anything constructed at runtime |
| `PerformanceObserver` on `resource` entries | Most attempts, including blocked ones | Reporting of blocked entries is not guaranteed across WebKit versions |

**Spike result, 2026-08-01 — measured, not predicted.** The first run of
`scripts/verify_html_import_spike.sh` settles it:

- **The block works.** Fixture 3's pass 1 produced exactly one server request per
  viewport — the document — with every subresource blocked. The privacy guarantee
  holds as written.
- **`D` (DOM walk) is the load-bearing recorder.** 6 of 6 in pass 1, 7 of 8 in pass 2.
  Drop it and the manifest mostly empties.
- **`P` (PerformanceObserver) reports nothing while blocked** — 0 of 6 in pass 1, 5 of
  9 in pass 2. It is a pass-2 cross-check, not a discovery mechanism. The
  version-dependence question above is answered: do not rely on it.
- **`R` (polled resource timing) returns exactly what `P` returns** — the same 0 of 6
  and 5 of 9, every run. They read the same buffer, so **E1 ships one of them, not
  both**. The pair exists here only to establish that the buffer, not the wiring, is
  what omits the font (§4.3).
- **`I` (instrumentation) is load-bearing for exactly one class** — script-initiated
  `fetch`/XHR. It was the *only* recorder that saw `config.json`. Small in count,
  irreplaceable in kind.
- **`C` (CSSOM walk) caught nothing in pass 1** — a blocked stylesheet has no rules
  to walk — and exactly one thing in pass 2, which turned out to be the most
  informative row in the whole run. See §4.1 and §4.2.

**Recorders come in two kinds, and conflating them hides the question that matters.**
`D` and `C` read what the page **declares** it wants. `I` and `P` **observe** what it
actually asked for. In pass 1 nothing is fetched, so every entry is declaration-only
by definition. In pass 2 a resource still listed declaration-only at a given viewport
is one that viewport **never requested**. E1 ships `D` + `I` as the load-bearing pair,
`C` for cross-viewport declaration (§4.2), and `P` as corroboration only.

## 3. DOM / computed-style payload

One injected pass produces a serializable tree. Deliberately a **fixed allowlist**,
not "all computed styles": a real page is thousands of nodes × hundreds of resolved
properties, and serializing everything is how this gets slow enough to abandon.

Per element:

- `tagName`, a stable child-index path, and depth
- `getBoundingClientRect()` in **CSS px** at each selected viewport (§1.1), mapped as
  **1 CSS px = 1 EXP pt** with no guessed geometry scale; the observed WebKit
  `devicePixelRatio` is carried separately and reported when it is not 1 because it
  can affect resolution-dependent resource selection, not layout coordinates
- Inline SVG remains on the editable vector path. A same-folder external
  `<use href="sprite.svg#symbol">` is resolved through the selected-folder resource
  boundary, copied into local `<defs>`, and ID-namespaced (including internal
  `url(#…)`/href references) before native SVG import. Remote/file references stay
  stripped; unsupported SVG features remain reported rather than silently fetched.
- allowlisted computed properties: box (`display`, `position`, `overflow`,
  margin/padding/border widths), paint (`background-color`, `background-image` for
  gradients, `color`, `opacity`), border radii, `box-shadow`, `transform`,
  `filter`, `mix-blend-mode`, `z-index`, and type (`font-family`, `font-size`,
  `font-weight`, `font-style`, `line-height`, `letter-spacing`, `text-align`,
  `text-decoration`, `text-transform`)
- semantics: `role`, `aria-*`, `alt`, `href`, `title`, heading level
- **`data-exp-id` if present** — see below

**Rendered visibility includes accessibility-only content.** A common `sr-only`
pattern is meaningful text inside an absolute/fixed box no larger than 1 × 1 CSS
px with both overflow axes hidden (often with an additional zero `clip`). Because
ordinary EXP groups do not implicitly clip descendants, painting that text would
turn an accessibility implementation detail into overlapping visible copy. The
bounded mapper recognizes that conservative rendered signature, retains the text
and hierarchy as a named hidden EXP layer, and reports the exact preservation. It
does not delete the accessible content or infer invisibility merely from a class
name.

**Document height is not `scrollHeight`.** Spike finding, 2026-08-01: `scrollHeight`
floors at the viewport height, so a page shorter than its viewport reports the
viewport height and the artboard would be cut taller than its content, with trailing
empty space that never existed in the browser. §1.1's "full document height" means
measured content height. The harness reports both so the difference stays visible.

**Text is measured, not re-laid-out.** Each text node reports its own client rects.
EXP places the measured boxes; it does not re-run line breaking and hope the result
matches. Re-laying-out text is the most likely source of "but it looked right in
the browser."

**`data-exp-id` is a real round-trip lever.** EXP's own semantic HTML export
already stamps it on every element. When the importer sees it, it can reunite
imported nodes with their original EXP identity instead of treating the document as
an anonymous stranger. This is what makes the §10 spike measurable rather than
impressionistic.

## 4. Resource trust model — two-pass discovery

Owner decision, 2026-07-29: **subresources blocked by default; the user chooses
which origins to allow, per import.**

### The problem this solves

You cannot list a page's sources without rendering it, and rendering is the thing
being gated. A single "allow remote resources" checkbox would therefore be a blind
decision. So the import runs in two passes.

### Pass 1 — discovery (loads nothing)

Render with **every** subresource blocked, while recording each request the page
attempts: URL, origin, resource type (document · stylesheet · script · font ·
image · media · XHR/fetch), and declared size where available. Nothing is fetched,
so the page receives no data and sends none. The output is a **manifest of what the
page wants**, obtained without granting anything.

**With several viewports selected, pass 1 runs once per viewport and the manifest is
their union.** A responsive page genuinely requests different resources at different
widths — `srcset`, `<picture>`, media-queried `@font-face`, `matchMedia`-driven
scripts — so discovering at one width and rendering at three would hand the designer
a trust list that is quietly incomplete. Each row records **which viewports asked for
it**, so a font only the phone layout pulls is visible as such. Trust is granted **per
session, not per viewport**: allowing an origin allows it at every selected width.
Splitting trust per viewport would multiply the decisions without making any one of
them better informed.

### Trust step

The manifest is presented grouped by **origin** — one row per scheme+host, with a
toggle, expandable to the individual resources beneath (type, size, status). Origin
is the unit a person can reason about; the file list exists to justify the decision,
not to be toggled one by one.

Defaults: **same-origin as the document is pre-allowed; every third-party origin
starts off.**

### 4.1 Iterative trust is the NORMAL path, not an edge case

**Spike finding, 2026-08-01. This upgrades a caveat into a rule.** §4 already said
allowing a script can reveal requests pass 1 never saw. The spike shows the same thing
happens for something far more common than scripts:

**A blocked stylesheet has no rules to walk, so every resource it references is
invisible.** Webfonts declared in `@font-face`, `background-image`, `border-image`,
`mask-image` — none appear in pass 1's manifest, because the CSS that mentions them
was never fetched. And a stylesheet that *is* fetched but is **cross-origin without
CORS** is equally unreadable: `cssRules` throws, so its resources stay invisible even
after its own origin is trusted.

Nearly every real page uses CSS backgrounds or webfonts. So the first trust list a
designer sees is **structurally incomplete for almost every page**, not occasionally.

Three consequences, all binding on E1:

1. **The Import Session UI must present the trust list as a starting point, not a
   complete inventory.** Wording that implies "here is everything the page wants" is
   false on the first pass for the common case. The list grows as trust is granted,
   and the UI has to make that read as expected rather than alarming.
2. **An unreadable stylesheet is itself a manifest row**, naming what it hides:
   "this stylesheet could not be read, so any fonts or images it references are not
   listed." Skipping it silently would hide the resources *and* the reason — the worst
   available outcome, because the designer cannot tell there is a gap at all.
3. **The revisitable session earns its place.** It was justified as a convenience; it
   is load-bearing, because a single-shot trust dialog cannot express a list that is
   knowably incomplete at the moment it is shown.

**Confirmed with a concrete missing file, 2026-08-01.** Fixture 3's `brand.css` was
trusted, fetched, and rendered — and its `cssRules` still threw, because it is
cross-origin without CORS. The webfont it declares (`brand.woff2`) therefore appears
**nowhere in the pass-2 manifest**, despite its own origin being trusted. This is not
a hypothetical: a trusted third-party stylesheet can hide its subresources completely.
The manifest row for an unreadable stylesheet must say so in those terms.

### 4.2 Declared is not requested — and the manifest must say which

**Spike finding, 2026-08-01, second run.** The phone-only `background-image` was
picked up by the CSSOM walk at **both** viewports, because the rule exists in the
stylesheet at both — but the browser only *requested* it at 393, where the media
query matched. Declaration and request are different facts and the first cut of the
manifest could not tell them apart.

Both failure modes are real:

- **Under-listing** hides a resource the designer should get to rule on. Worse.
- **Over-listing** asks the designer to make trust decisions about files the page
  will never fetch at the viewports they chose. Not harmless: it inflates the list,
  and an inflated list is one people stop reading — the exact failure §4's 2,000-entry
  cap exists to avoid.

So the manifest lists declared resources **and attributes them**: which viewports
declared it, which viewports were observed requesting it. A row reading "declared at
both, requested at 393 only" is honest and actionable; either fact alone is not.

This also gives `C` a job worth keeping despite catching almost nothing. A CSSOM walk
sees what a viewport you did **not** select would have requested — so it can warn that
adding a viewport will add resources, before the re-render that would discover them.

### 4.3 The receipt is incomplete, and that is why trust is per ORIGIN

**Spike finding, 2026-08-01, third run — the most important result so far, and it
came from the one check the harness cannot fake.** The fixture's own web server
logged `GET /brand.woff2` at both viewports. That font **appears in no recorder and
in no manifest row.** It was fetched over the network and never listed.

**The cause is established, not guessed.** Two independent readouts of resource
timing — the `PerformanceObserver` and a direct poll of
`performance.getEntriesByType("resource")` — agree exactly: 5 of 9 resources, neither
including the font. So the omission is not a bug in how the observer was wired; the
resource-timing buffer simply does not contain it. `document.fonts` does name the
font, but only as a FAMILY (`"Fixture Brand"`), never a URL — so it can tell you a
font was used and never which file was fetched.

One confound was found and removed rather than argued around: the first font fixture
was a placeholder that could not parse, which left open whether the omission followed
from the parse failure rather than the cross-origin declaration. `brand.woff2` was
replaced with a real, valid woff2 (synthetic, four glyphs, built by the fixture's own
script) and the `h1` made to use it. **Confirmed 2026-08-01:** the FontFaceSet reports
`Fixture Brand — loaded`, the server log still shows `GET /brand.woff2` at both
viewports, and the manifest still does not contain it. A font that loads perfectly is
fetched and never listed. The finding stands unqualified.

Be precise about what did and did not break:

- **The security model held.** The font came from `:8732`, an origin the user had
  trusted. Nothing was fetched from an untrusted origin. No unauthorised byte moved.
- **The receipt did not.** §9 category 7 calls the Sources report "the trust step's
  receipt, readable after the fact." A receipt that omits a file that was fetched is
  not a receipt. The cause is §4.1's: the font is declared inside a cross-origin
  stylesheet whose `cssRules` cannot be read, so nothing in the page's readable
  surface ever names its URL — `document.fonts` exposes the font *family* and never
  the URL it came from.

**This retroactively justifies granting trust per origin rather than per resource.**
Per-resource trust sounds stricter and more respectful of the user, and the spike
shows it would be **unimplementable as an honest promise**: you cannot ask someone to
approve a list of files when files can be fetched that the list can never contain.
Origin-level trust is the finest granularity that can be stated truthfully. The
owner's 2026-07-29 decision was made on readability grounds; it turns out to have
been the only correct one available.

Three requirements follow, and they are not optional:

1. **The Sources report says what it could not enumerate.** Owner decision,
   2026-08-01: **one named row per unreadable stylesheet**, in the Sources pane and in
   the Import Report, reading in substance *"this stylesheet could not be read, so any
   fonts or images it references are not listed."* Located, not general — the row sits
   with the origin it belongs to, so the designer can see which third party the gap
   belongs to. Rejected alternatives, recorded because both are defensible: a standing
   note on every import regardless (maximally honest, but becomes boilerplate people
   stop reading — the same failure the 2,000-entry cap exists to prevent), and
   surfacing it only when a font or image visibly fell back (quieter, but couples a
   privacy-receipt fact to a visual-fidelity trigger, so a hidden tracker pixel would
   go unmentioned). The row appears whenever the stylesheet is unreadable, whether or
   not anything visibly broke.
2. **The manifest never claims completeness anywhere in the UI** — not in a heading,
   a count, or a summary line. "4 origins · 23 resources" is a count of what was
   *seen*, and must read that way.
3. **The E1 test suite keeps a server-log cross-check.** The blind spot was invisible
   to every in-page recorder and only appeared because an independent observer — the
   server — was asked what it actually served. Self-reported completeness is not
   evidence.

### Pass 2 — render (loads only what was allowed)

Re-render with exactly the allowed origins permitted. This pass produces the
preview and the extraction payload.

### What "trust" means here, precisely

Allowing an origin means **"fetch this host's assets anonymously, for this import."**
It does not mean logging in, and it cannot: the data store is non-persistent and no
credentials or cookies are ever sent (§2, §6). The UI must say this, because
"trust" is otherwise a word that promises more than it delivers.

### Two honesty requirements

1. **The manifest is "requests observed during the render window," not a guarantee.**
   Lazy-loaded or interaction-triggered resources may never be requested inside the
   deadline, so they will not appear. The detection mechanism itself has blind spots
   (§2), which is the other half of the same admission. The UI says this rather than
   implying the list is exhaustive.
2. **Allowing a script can reveal requests pass 1 never saw.** A newly-permitted
   script may fetch further origins; those are blocked and *appended to the
   manifest* for the next round. The trust list is therefore **iterative by
   nature** — which is why §5's revisitable session is load-bearing rather than a
   convenience.

### Security details that are not optional

- Show the **full origin**, always. When a host contains non-ASCII characters,
  show the **punycode/ASCII form**, so a homograph (`аpple.com` with a Cyrillic
  `а`) cannot masquerade as a familiar host.
- Show resource **type** per row. A script from an unknown origin is a different
  risk from an image, and the UI should not flatten that.
- **Status is never conveyed by colour alone** — blocked / allowed / failed each
  carry text and a distinct symbol.
- Blocked, failed, and substituted resources all become named Import Report
  entries. Substitutions preserve layout: a remote font falls back to a *named*
  system face; a blocked image becomes a placeholder node that **keeps its measured
  box**.
- No telemetry. Nothing about the imported document is persisted outside the
  resulting `.design`.

### Trust persistence

Owner decision: **per document, opt-in.** Decisions are stored in the `.design` so
"Adjust Import…" reopens with prior choices intact, and they never apply to another
document. There is deliberately **no app-wide allowlist** — a global one quietly
becomes "allow everything" as it grows past the point anyone reads it.

## 5. The Import Session: trust, preview, revisit

A URL import is a **session**, not a one-shot dialog. It has three panes and it can
be reopened.

### Pane 1 — Sources

The §4 trust list. Origin rows, expandable, with counts and totals ("4 origins ·
23 resources · 2 scripts blocked").

### Pane 2 — Preview

A rendered snapshot from pass 2 **for each selected viewport**, switchable through a
keyboard-reachable control labelled with the width in text (not width alone as a
glyph), so the designer can confirm they are importing the right thing before it lands
on canvas — and can see what a blocked origin actually cost them, at each width where
the cost differs.

Beside it, **what the import will produce**: artboard count, node count, text-run
count, and the §9 report categories pre-filled. The preview answers "is this the
right page"; the summary answers "is this worth importing." The summary is also the
preview's text alternative, so the pane is not image-only for assistive technology.

### Pane 3 — Scope

The §1.1 viewport multi-select, pre-selected to Desktop 1440, and — for folder or
multi-page input — which documents to import. The pane shows the resulting artboard
count (`documents × viewports`) live, so a three-viewport folder import cannot arrive
as a surprise.

### Reopening a session

The session persists in the document: input descriptor (URL, or a security-scoped
bookmark for local files), chosen viewports, allowed origins, the manifest as last
discovered, the ids of everything it created, and a content hash of the rendered
payload. **File ▸ Adjust Import…** reopens it with all of that intact.

### What "adjust" does — owner decision, 2026-07-29

**Re-render and replace, with an explicit warning.** Adjusting trust re-runs pass 2
and replaces the previously imported artboards and nodes wholesale, as **one undo
step**. The sheet warns clearly that edits made to imported content since the last
import will be discarded, and names how many nodes will be replaced.

This is a deliberate starting position, not an oversight. Rationale recorded by the
owner: *a clean, predictable import is the priority until there are real use cases
to learn from.* The alternative was considered and is filed rather than lost:

> **Follow-up (not v2.2 scope):** surgical fill — newly-trusted resources fill
> their existing placeholders (missing image lands in the box already holding its
> space; fallback font is replaced) without touching geometry or structure, so
> post-import edits survive. Revisit once the replace-everything flow has been used
> against real pages and the actual failure mode is known. A third option, diffing
> and merging via `data-exp-id`, is the best outcome in theory and a project in its
> own right.

**Changing the viewport selection is an adjust**, on the same terms: adding a width
re-renders and replaces the whole import rather than appending artboards beside the
existing ones. Same warning, same single undo step. Appending only the newly-selected
width is the obvious optimisation and is filed with the surgical-fill follow-up above
rather than built now — same rationale, one predictable behaviour until real use
teaches otherwise.

**Re-importing a URL that already has a session — owner decision, 2026-08-01.** EXP
notices the existing session, says so by name, and **defaults to adjusting it**, with
"Import as new" available in the same sheet. Defaulting to adjust reuses the trust
decisions already made and stops a document quietly accumulating four sessions with
identical names; keeping "import as new" preserves the legitimate case of importing
the same page twice on purpose. The prior session is never replaced without the §5
replacement warning, since adjusting is the destructive path.

### Adjust offers two outcomes — owner decision, 2026-08-01

**Superseding the replace-only position above.** Adjusting an import presents a
choice:

| Outcome | What happens |
|---|---|
| **Replace in place** | As described above — re-render, replace the existing artboards, one undo step, behind the warning |
| **Import as new artboard(s)** | Re-render with the new settings and place the result *beside* the existing import. The original is untouched |

This dissolves a collision rather than resolving it. Manual repairs (§5.1) and any
post-import editing are edits to imported content, so replace-in-place destroys them —
which would make a repair flow quietly temporary. With "import as new," the repaired
artboard simply survives, because nothing overwrote it.

**The cost, stated plainly rather than glossed:** repairs are *not carried forward*
into the new generation. Ten hand-supplied assets means either keeping the old
artboard or re-supplying them on the new one. What the choice buys is that the
decision is the designer's and is visible, instead of an adjust silently eating work.

Consequences for the session model (§5):

- The session records **generations**, not one set of created ids. Each generation
  stores the viewport set and trust set that produced it.
- Each generation is **labelled with what produced it** — viewport, a short trust
  summary, and a sequence number — because two artboards from the same URL otherwise
  look identical and differ only in ways that matter.
- Undo is unchanged: each adjust, either kind, remains one step.
- The canvas can accumulate generations. That is ordinary artboard clutter and is
  cleaned up by deleting artboards; no special mechanism is warranted.

This **supersedes surgical placeholder-fill for the manual-repair case**, which was
its main justification. Surgical fill remains open as an optimisation for the
newly-trusted-resource case, not as a prerequisite for repair.

Because replace-in-place is destructive, the warning remains the load-bearing part of
that path, and it must never be reachable in a way that skips it.

### 5.1 Repair actions — the report is not just a list of regrets

**Owner decision, 2026-08-01, and the governing rule is simple: if a fix takes one or
two steps, the UI offers it.** Every report or manifest row representing a loss
carries an action, so the Import Report reads as *"here is what went wrong and here is
the control that fixes it"* rather than a list of things the designer can only feel bad
about.

§4.3 is why this is necessary rather than a nicety: some resources — a webfont
declared in a cross-origin stylesheet — **cannot be enumerated by any means**. No
amount of cleverness in the importer reaches them. A person with the file on their
disk reaches them immediately. The manual path is not a fallback for when the
automation is weak; for that class it is the only path that exists.

Actions in scope:

- **Copy URL, and copy all unresolved.** The cheapest possible action, works on every
  row type, and is the direct equivalent of a scrape tool's "here are the links I
  found" list.
- **Supply a local file** for a placeholder — an image or font dropped onto the box
  already holding its space. **Drag is never the only way in:** a "Choose file…"
  button sits beside it, because a drag-only affordance is unusable by keyboard and
  by anyone with a motor impairment. This is a hard requirement, not a refinement.
- **Open the source in your own browser.** For an unreadable stylesheet or a blocked
  origin, a button that hands the URL to the user's browser. EXP never fetches it —
  their browser does, under their own session — so the credential-free posture (§6)
  is untouched.
- **Paste stylesheet text.** For a cross-origin stylesheet EXP cannot read, the user
  copies the CSS themselves and pastes it so the importer can resolve what it
  references.

**Why pasting CSS does not contradict §1's refusal of pasted fragments.** The two are
different operations. §1 refuses a pasted fragment as the *root* of an import — no
`<head>`, no font context, no unambiguous root box, so fidelity would be materially
worse and the report mostly caveats. Here a rendered document with a real box tree
already exists; the pasted CSS is **supplementary resolution data for an existing
import**, not a document. That distinction is the whole reason it is admissible.

It carries one honesty requirement: **an import containing hand-supplied CSS or assets
says so in the report.** It is no longer purely what the server served, and a handoff
artifact that quietly blends served and hand-edited sources is exactly the kind of
silent guess §0 refuses.

Accessibility applies to every action here without exception: keyboard-reachable, not
drag-only, never conveyed by colour alone, and labelled in text rather than by icon
alone.

## 6. Why this matters: GitHub, Storybook, and the auth boundary

The owner's reason for wanting web import at all is reaching **online repositories
of design code** — a hosted Storybook, a component gallery, GitHub Pages. That is
worth stating because it sets the target, and because it exposes a boundary this
contract has to be honest about.

**What this enables:**

- A **public** hosted Storybook build — it serves HTML, so it imports (per-story
  artboards are E2, but the transport is the same)
- **GitHub Pages**, or public `raw.githubusercontent.com` HTML
- Any publicly reachable rendered prototype

**What it does not, and should not:**

- **Private repositories and SSO-gated Storybooks.** Reaching those requires
  storing credentials or tokens, which contradicts the no-keys posture the Agent
  Bridge was deliberately designed around (Chunk F: EXP never holds vendor keys).
  Building an OAuth flow and a token store into an import sheet would undo that on
  the quiet.

**The better path for private sources**, and it already exists in this project's
plan: the designer's **own agent** already has repository access. It fetches the
build and hands EXP a local artifact — either plain HTML on disk (§1 local input,
fully supported) or the EXP Source format sketched at the start of the v2.2 agent
work. EXP stays credential-free; the agent does the authenticated part, which is
the thing it is already trusted with.

That is the same division of labour as the Agent Bridge: EXP does not reach out to
services, services and agents reach in.

## 7. Cancellation, progress, and limits

Reuses `InteropCodec`'s existing `InteropContext` progress/`cancel()` plumbing — the
same machinery the XD and Figma importers use, so cancellation behaves identically
across all three. **Both passes are cancellable**, and cancelling either leaves the
document untouched.

Hard limits, each producing a **reported partial import** rather than a failure or a
silent truncation:

| Limit | Initial value | Rationale |
|---|---|---|
| Max nodes | 15,000 | Beyond this the canvas, not the importer, is the bottleneck |
| Render deadline | 10s after `load`, per pass, **per viewport** | An SPA that never settles must not hang the app |
| Max payload | 64 MB serialized | Bounds the JS→Swift bridge |
| Max image dimension | 8192 px | Matches existing raster handling |
| Max manifest entries | 2,000 (union across viewports) | A trust list longer than this cannot be read; on overflow the import degrades to same-origin-only rather than failing — see below |
| Max viewports per import | 5 | The whole filtered §1.1 list; the cap exists so “select all” has a known worst case, not to ration widths |

**Manifest overflow — owner decision, 2026-08-01.** Passing 2,000 entries does not
refuse the import. The trust step switches to **same-origin-only**: every third-party
origin stays blocked with no way to allow it in that session, and the report states
how many requests were never listed (§9 category 8). Refusing outright was considered
and rejected — it turns one legitimately heavy page into a dead end with no path
forward, while same-origin-only still produces a usable, honestly-labelled import. The
reverse risk is named rather than ignored: a page could push past the cap precisely to
bury a third-party origin in the overflow, which is why overflow **blocks** third
parties instead of waving them through.

Node, payload, and manifest caps apply to the **import as a whole**, not per viewport.
Three viewports of one page is one import against one set of caps, and the §9 report
names which cap was hit.

The whole import is **one undo step**, consistent with XD and Figma import.

## 8. Semantic-role reverse mapping

The inverse of SEMANTIC-HTML-CONTRACT.md §"Native/ARIA Role Mapping", and **not a
table inversion**. Rules first, table second — and per WORKING-AGREEMENT the table
is verified row by row against the specs before E1 writes code, not recalled.

### Rules

1. **Read the explicit `role` attribute first.** The forward contract hosts ~20
   different EXP roles on `div` + an explicit `role`. Element name alone cannot
   reverse that, so `role` wins wherever present.
2. **A bare `<div>`/`<span>` has no role.** It becomes a plain EXP group or text
   node. Never guessed at.
3. **Never infer semantics from visual styling.** The forward contract explicitly
   refuses to infer heading level from font size, weight, or layer name; the reverse
   must refuse the mirror temptation. Large bold text is not a heading.
4. **Context-dependent landmarks get the same ancestry check, in reverse.** The
   exporter already does this (contract §B2); the importer must too, or a nested
   `<header>` imports as a page banner.
5. **A `role` EXP has no equivalent for is reported, never approximated.** An
   unmapped role is information the developer needs; guessing destroys it.

### Verified against HTML-AAM 1.0, 2026-07-29 and 2026-08-01

Each row cites the HTML-AAM section that establishes it. "→" is what the IMPORTER
concludes from the rendered element.

| Element (as rendered) | Computed role | HTML-AAM § |
|---|---|---|
| `<a href>` | `link` | 3.5.2 |
| `<a>` **without** `href` | `generic` | 3.5.3 |
| `<article>` | `article` | 3.5.8 |
| `<aside>` scoped to `body`/`main` | `complementary` | 3.5.9 |
| `<aside>` scoped to sectioning content | `complementary` **only with an accessible name**, else `generic` | 3.5.10 |
| `<button>` | `button` | 3.5.20 |
| `<dialog>` | `dialog` | 3.5.33 |
| `<div>` | `generic` | 3.5.35 |
| `<figure>` | `figure` | 3.5.42 |
| `<footer>` scoped to `body` | `contentinfo` | 3.5.43 |
| `<footer>` scoped to `main` or sectioning content | **`sectionfooter`** | 3.5.44 |
| `<form>` | `form`, **but not exposed as a landmark without an accessible name** | 3.5.45 |
| `<h1>`–`<h6>` | `heading` with `aria-level` set from the tag name | 3.5.47 |
| `<header>` scoped to `body` | `banner` | 3.5.49 |
| `<section>` | `region` **only with an accessible name**, else `generic` | verified 2026-07-29 |

Sources: [HTML-AAM 1.0](https://www.w3.org/TR/html-aam-1.0/) ·
[ARIA in HTML](https://www.w3.org/TR/html-aria/) ·
[WAI-ARIA 1.2](https://www.w3.org/TR/wai-aria-1.2/) ·
[APG: Landmark Regions](https://www.w3.org/WAI/ARIA/apg/practices/landmark-regions/)

#### Correction: a row previously recorded as verified was wrong

**2026-07-29 recorded "`<footer>` → `contentinfo` … otherwise `generic`." That is
incorrect.** HTML-AAM §3.5.44 maps a `<footer>` scoped to `main` or a sectioning
content element to **`sectionfooter`**, not `generic`. The same error was almost
certainly made for `<header>` — §3.5.50 was not reachable this session (see below), so
it is recorded as UNVERIFIED rather than fixed by symmetry, which is the mistake that
produced this correction in the first place.

Two consequences:

1. **`sectionfooter` has no EXP equivalent.** Rule 5 fires: report it, never
   approximate it. This is the first concrete instance of that rule doing real work,
   and it is worth noting that the wrong version would have silently produced a plain
   group with the semantic quietly discarded.
2. **The forward exporter was checked, and partly fixed (BUG-018, 2026-08-01).** The
   ancestry check DID exist for `banner` and `contentinfo` — an earlier note here
   claiming otherwise was wrong. What was actually broken: `complementary` was never
   escalated, and the condition tested "has any semantic ancestor" rather than "is
   inside sectioning content or `main`," which is the rule HTML-AAM actually states.
   Both are fixed and covered by a fixture. So the reverse table can rely on EXP's own
   exports stating nested landmark roles explicitly — a real simplification for
   fixture 1's round trip.

#### A forward-contract mismatch, surfaced by the reverse check

HTML-AAM §3.5.10: an `<aside>` inside sectioning content is `complementary` **only if
it has an accessible name**, otherwise `generic`. The forward table lists EXP
`complementary` → `aside` with requirement "—". So a nested, unnamed EXP
`complementary` exports to markup that does not compute as `complementary` at all.
Reverse-mapping work found a forward-mapping bug; that is the argument for doing this
verification before the mapper rather than during it.

### Verified 2026-08-01, second pass — the rest of the element table

Read from HTML-AAM 1.0, **W3C Working Draft 29 July 2026**
(`https://www.w3.org/TR/2026/WD-html-aam-1.0-20260729/`). Role cells quoted, not
paraphrased. "EXP" is what the importer may produce; **—** means EXP has no
equivalent role, so rule 5 applies.

| § | Element | Computed role | EXP |
|---|---|---|---|
| 3.5.50 | `header` scoped to `main`/sectioning content | `sectionheader` | — |
| 3.5.51 | `hgroup` | `group` | group |
| 3.5.56 | `img` | `image or img` | img |
| 3.5.57 | `img` with empty `alt` | `none or presentation` | — (see below) |
| 3.5.85 | `li` | `listitem`, with `aria-setsize`/`aria-posinset` | listitem |
| 3.5.87 | `main` | `main` | main |
| 3.5.91 | `menu` | **`list`** — *not* `menu` | list |
| 3.5.94 | `nav` | `navigation` | navigation |
| 3.5.97 / 3.5.144 | `ol` / `ul` | `list` | list |
| 3.5.99 | `option` | `option`, with `aria-selected` | option |
| 3.5.100 | `output` | `status` | — |
| 3.5.101 | `p` | `paragraph` | — (default, not a loss) |
| 3.5.105 | `progress` | `progressbar` with `aria-valuemin/max/now` | progressbar |
| 3.5.113 | `search` | `search` | search |
| 3.5.114 | `section` | `region` **if it has an accessible name. Otherwise, the generic role.** | region |
| 3.5.115 / 3.5.116 | `select` rendered as list box / drop-down | `listbox` / `combobox` | listbox / — |
| 3.5.124 | `summary` | `No corresponding role`; `html-summary` only as first child of `details`, else `generic` | — |
| 3.5.127 | `table` | `table` | table |
| 3.5.128 / 3.5.133 / 3.5.138 | `tbody` / `tfoot` / `thead` | `rowgroup` | — |
| 3.5.129 / 3.5.130 | `td`, ancestor table is `table` / `grid`\|`treegrid` | `cell` / `gridcell` | — |
| 3.5.132 | `textarea` | `textbox` with `aria-multiline="true"` | textbox |
| 3.5.134–3.5.137 | `th` variants | `cell` / `gridcell` / `columnheader` / `rowheader` | — |
| 3.5.141 | `tr` | `row` | — |
| 3.5.58–3.5.80 | `input`, 23 separate states | see below | see below |

**`input` is 23 sections, and nine of them have no ARIA role at all.**
Button/Image Button/Reset/Submit → `button`; Checkbox → `checkbox` with
`aria-checked` (`"mixed"` when `indeterminate`); Radio → `radio` with
`aria-checked`, `aria-setsize`, `aria-posinset`; Number → `spinbutton`; Range →
`slider`; Search → `searchbox`; Text/Telephone/URL/E-mail → `textbox`; **any of
Text/Search/Telephone/URL/E-mail *with a suggestions source element* →
`combobox`, with `aria-controls` set to the `list` attribute**. The nine with
**`No corresponding role`** — Color, Date, Local Date and Time, File Upload,
Hidden, Month, Password, Time, Week — compute to non-ARIA tokens
(`html-input-color`, `html-input-date`, …; Hidden is `Not mapped`). Anything
assuming `input` always yields an ARIA role is wrong for nine common controls.

#### Rules this second pass forces

6. **`generic` and `paragraph` are the DEFAULT, not a loss.** Every `<div>` is
   `generic` and every `<p>` is `paragraph`, so reporting each one under rule 5
   would bury the report in thousands of rows and reproduce the exact failure the
   2,000-entry manifest cap exists to prevent (§7). They map to plain EXP groups
   and text nodes and are **not** individually reported. Rule 5 applies to
   *non-generic* roles with no EXP equivalent — `sectionheader`, `sectionfooter`,
   `status`, `row`, `cell`, `gridcell`, `rowgroup`, `columnheader`, `rowheader`,
   `combobox`, `article` — which are real semantics being dropped.
7. **Never infer a role from an element name where the spec disagrees.** `<menu>`
   is `list`, **not** `menu` (§3.5.91 — the spec states it has no mappings
   reflecting the ARIA `menu` role). An importer that inverts the forward table by
   name would get this exactly backwards on non-EXP pages.
8. **Some roles depend on rendering or ancestry, not markup**, and the importer has
   the rendered tree, so it can and must resolve them rather than guess:
   `<select>` splits on *how it renders* (list box → `listbox`, drop-down →
   `combobox`); `<td>`/`<th>` take `cell` vs `gridcell` from the **ancestor
   table's** role; `<li>` is `generic` when not an accessibility child of
   `ol`/`menu`/`ul`; `<summary>` depends on position within `details`.
9. **`alt=""` alone does not mean presentational.** §3.5.57: an empty-`alt` `<img>`
   is `none`/`presentation`, **but reverts to the implicit `image` role if it has
   an accessible name from another valid mechanism.** Check the name before
   discarding the image's semantics.

### Verified 2026-08-03 — authored ARIA and explicit-role conflicts

- **`aria-*` state/property mapping:** WAI-ARIA 1.2 §6.1 treats states and
  properties as ARIA attributes; their main distinction is expected change
  frequency, not a request to create visual variants. E1 therefore retains every
  authored `aria-*` name/value as structured, non-executable `NodeSemantics` data.
  It does **not** invent EXP component states from the current value of
  `aria-checked`, `aria-selected`, or `aria-expanded`. `aria-level` additionally
  supplies a positive stored heading level. Unsupported or role-inapplicable
  attributes remain source truth for repair/write-back rather than being discarded.
- **Explicit role contradicting its host:** WAI-ARIA 1.2 §8.1 says the first
  recognized concrete token in a role fallback list is the role user agents
  process. ARIA in HTML then restricts which roles authors may place on each HTML
  host. E1 implements the current allowed-role rows for the §8 element set. A
  conforming explicit role wins; a prohibited role is retained in `authoredRole`,
  marked nonconforming, reported, and the element's verified implicit role becomes
  EXP's effective role. Unknown/unverified hosts retain the explicit token and
  receive an approximation report rather than a false conformance claim.
- **Inline anchors:** a link inside a mixed-style paragraph remains one editable
  rich-text box; its `href` lives on the corresponding text run and semantic HTML
  handoff reconstructs the `<a>` without overlapping link/text layers.

Sources: [WAI-ARIA 1.2](https://www.w3.org/TR/wai-aria-1.2/#states_and_properties) ·
[ARIA in HTML](https://www.w3.org/TR/html-aria/#docconformance)

### Still open

- Elements outside the requested set (`abbr`, `del`/`ins`, `dl`/`dt`/`dd`,
  `details`, `fieldset`, `iframe`, `label`, `meter`, `svg`, …). Not needed for the
  current forward table; check before the mapper touches them.

### Settled

- **`<a>` without `href` → `generic`** (§3.5.3).
- **`<header>` scoped to sectioning content → `sectionheader`** (§3.5.50).
  This was shipped in `AriaRole.needsExplicitRoleWhenNested` on reasoning-by-symmetry
  with `<footer>`/§3.5.44 and flagged as unverified; it is now **verified by
  citation**, and the reasoning happened to be right.
- **`<section>` → `region` only with an accessible name** — independently confirms
  the 2026-07-29 row (§3.5.114).

The governing references are **WAI-ARIA 1.2, ARIA in HTML, HTML-AAM, the APG, and
WCAG 2.1 AA**. The ADA does not specify ARIA.

## 9. Fidelity-report categories

Same shape as the XD/Figma Import Report — visible, copyable, on demand — so all
three importers report identically.

1. **Mapped** — native editable EXP, no loss
2. **Approximated** — imported with a *named* substitution (font fallback, effect
   simplified, gradient approximated)
3. **Flattened** — geometry preserved, structure lost (CSS-drawn shape → path/rect)
4. **Placeholder** — measured box preserved, content unavailable
5. **Dropped** — no EXP equivalent, listed **with the reason**
6. **Semantics** — roles recovered · roles present but unmapped · semantics
   deliberately NOT inferred (rule 3)
7. **Sources** — per origin: allowed, blocked, failed, and what each substitution
   cost. This is the trust step's receipt, readable after the fact
8. **Limits** — anything cut by a cap from §7, and which cap
9. **Hand-supplied** — assets or CSS the designer provided themselves (§5.1). An
   import that blends served and hand-supplied sources says so; a handoff artifact
   that quietly mixes them is the silent guess §0 refuses

**Every row that represents a loss carries an action** (§5.1). A report the designer
can only read is worth less than one they can act on, and for the §4.3 class it is the
only remedy that exists.

Where an import covers several viewports (§1.1), categories 1–5 are reported **per
viewport** — a font that falls back only in the phone layout is a fact about that
artboard, not about the import — while 6 (Semantics) and 7 (Sources) are reported once
per session, because roles and trust are shared across widths. Each viewport's section
names the render height its `vh` units resolved against.

Categories 6 and 7 have no equivalent in the XD/Figma reports, and they are the two
that matter most here: 6 is where the importer admits what it refused to guess, 7 is
where it admits what it was not allowed to load.

## 10. The bounded E0 spike

**Fixture 1 is EXP's own exported semantic HTML** for a small authored artboard.
This is the useful choice rather than a stranger's page: the export carries
`data-exp-id` on every element and its source artboard is known-good, so the spike
measures **round-trip accuracy against ground truth** instead of eyeballing whether
something looks about right. Design → export → import → compare.

- [ ] Box tree geometry within a stated tolerance of the source artboard
- [ ] Text runs land in the correct boxes at the correct measured sizes
- [ ] Authored roles recovered via §8 rules; nothing invented
- [ ] Report exercises the §9 categories, including 7 (Sources)
- [ ] Cancel works mid-render in **both** passes; document untouched
- [ ] Single undo step
- [ ] Non-persistent store verified: no cookies or storage survive

**Fixture 2 is a small hand-written HTML/CSS page that did not come from EXP**, to
prove the importer is not merely self-consistent with its own exporter. Same
criteria, minus `data-exp-id` reunification. **It carries at least one width media
query and is imported at two viewports**, so the §1.1 matrix, the per-viewport report
split, and the union manifest get exercised on the one fixture whose expected result
is known by construction.

- [ ] Both viewports produce artboards at the selected widths, cut to document height
- [ ] The media query resolves differently in each, and the report says so per viewport

**Fixture 3 exercises the trust flow** and is the one that cannot be faked with
local files: a page whose subresources come from more than one third-party origin,
including at least one script and one webfont.

- [x] Pass 1 fetches the document and **nothing else** — verified by observation,
      not assumption. **PASSED 2026-08-01:** the fixture's own server log shows one
      `GET /` per viewport and no subresource of any kind
- [x] Manifest groups correctly by origin; punycode shown for a non-ASCII host.
      **PASSED:** four origins grouped, including two differing only by PORT, and the
      IDN host arrived already punycode-encoded because URL parsing does IDNA — the
      homograph rule is satisfied by construction, not by remembering to encode
- [x] A blocked origin stays blocked through pass 2. **PASSED:** `:8733` and
      `fonts.googleapis.com` stayed blocked while `:8732` was trusted
- [x] Allowing a script surfaces **new** manifest entries (the §4 iterative case).
      **PASSED, and this is the headline result:** pass 1 saw 4 origins / 6 resources
      with no trace of `:8733`; trusting `:8732` let `widget.js` run and pass 2 saw 5
      origins / 8 resources including both `:8733` URLs. The two-pass model's central
      claim reproduces
- [x] A resource requested at only ONE viewport appears in the union manifest.
      **PASSED on the rerun:** `phone-hero.svg` shows up once the document's own
      origin is trusted, and the media query is confirmed resolving `true` at 393 and
      `false` at 1440
- [x] …**attributed to that viewport. PASSED third run:** `phone-hero.svg` reports
      "393×852 declared C · observed P / 1440×1024 declared C · NOT requested here" —
      declaration and request are now distinguishable per viewport (§4.2)
- [ ] Reopening the session restores prior trust decisions — **not testable yet**;
      no session persistence exists outside the app
- [ ] Adjusting trust replaces the import as one undo step, after the warning —
      **not testable yet**; there is no importer, only a probe

**Fourth criterion added after the third run:** the server-log cross-check. It is
listed last and matters most — see §4.3. Every other criterion is the harness
reporting on itself.

- [x] Every subresource the server actually served either appears in the manifest, or
      falls into a class the report names as unenumerable. **RESOLVED 2026-08-01 as a
      documented limit, not as a pass:** `brand.woff2` is fetched and never listed, and
      the cause is understood and written down (§4.3). The criterion was first phrased
      as "appears in the manifest," which the platform makes impossible; the honest
      version is the one above. The cross-check stays automated in
      `verify_html_import_spike.sh` and stays LOUD, so if the set of unlisted resources
      ever grows past the known class, somebody finds out.

**Status after the first run, 2026-08-01.** Fixture 3 — the one that could have
killed the design — passes every criterion testable without an importer. The trust
model is sound. What it exposed is §4.1: the first trust list is structurally
incomplete for almost any page using CSS backgrounds or webfonts. That is a
UI-honesty problem, not a structural one, and E1 absorbs it rather than being
rescoped by it.

Fixtures 1 and 2 currently prove only that extraction runs and that layout differs
correctly across viewports. Their geometry, text-run, and role criteria **cannot be
checked until a mapper exists**, because a probe that reports a box tree is not an
importer that reproduces one. Those boxes stay unticked deliberately; ticking them
because the numbers looked plausible is exactly the impressionistic judgement
fixture 1 exists to prevent.

If fixtures 1–2 pass and fixture 3 exposes a structural problem, E1 is rescoped
before it starts. That is what a spike is for.

## 11. Owner decisions — answered 2026-08-01

The four questions this document opened with are answered. They are recorded here in
one place and folded into the body sections named beside them.

- **Q1 — Folder import: one canvas page, one artboard per file.** All files land on a
  single page so variants can be compared side by side, which is the point of
  importing a folder. Filed against: a large folder makes a crowded page — revisit if
  real folders turn out to be big enough to matter. Body: §1, §1.1.
- **Q2 — Re-importing the same URL: offer to adjust the existing session, defaulting
  to adjust,** with "Import as new" available. Body: §5.
- **Q3 — Superseded by a better answer: the viewport control is a MULTI-SELECT,** so
  one import can produce phone, tablet, and desktop artboards. Desktop 1440 is the
  sole pre-selection. Body: §1.1, with knock-on effects in §3 (per-viewport rects),
  §4 (union manifest, session-wide trust), §5 (per-viewport preview, live artboard
  count), §7 (deadline per viewport, 5-viewport cap, caps are import-wide), §9
  (categories 1–5 per viewport), §10 (fixture 2 imports at two widths).
- **Q4 — Manifest overflow: same-origin-only, with the overflow reported.** Not a
  refusal. Body: §7.

### Added after the spike, 2026-08-01

- **Adjust offers replace-in-place OR import-as-new-artboard** (§5). Chosen over
  making adjust non-destructive: it keeps one clearly-labelled destructive path and
  lets repaired artboards survive by not touching them.
- **Repair actions on every loss row** (§5.1), governed by "if a fix takes one or two
  steps, offer it." Includes pasting stylesheet text, which is admissible because it
  supplements an existing rendered import rather than acting as the root of one.
- **The Sources report carries one named row per unreadable stylesheet** (§4.3).

### Still open, and deliberately so

- The ~40 unverified §8 reverse-mapping rows, `aria-*` state mapping, `<search>`, and
  `<a href>`. These **block E1** and are not owner questions — they are spec work
  against WAI-ARIA 1.2 / ARIA in HTML / HTML-AAM, to be done with citations recorded.
- Surgical placeholder-fill and `data-exp-id` diff/merge (§5) remain post-v2.2
  follow-ups, filed rather than discarded.
- Whether the §1.1 viewport list should stay filtered to Mobile + Web groups. Decided
  as filtered; one sentence from the owner reverses it.
