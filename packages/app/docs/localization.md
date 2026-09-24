# Localization

UI copy, including the English source copy, was authored on 2026-09-09 using
Antigravity CLI (`agy`) with `gemini-3.8-flash-high`, as requested for this project.
The model received UI strings, screen context, and a shared terminology glossary.
It was instructed to preserve behavior, product names, keyboard symbols and typed
format arguments; count labels work for zero, one and multiple items.

After feedback about overtranslation, Gemini directly explored the Swift source
using Antigravity's read and search tools. It read the settings pages, shared
controls, help sheets, menu construction, preview lifecycle and overlay code.
The same conversation then rewrote all Japanese entries using the observed
behavior. It also corrected context-sensitive terms in the other six languages.

On 2026-09-16, the settings window was reorganized into five input- and
presentation-focused destinations, reviewed and localized by `gemini-3.8-flash-high`
via Antigravity CLI:

1. 一般 / General
2. キーボード / Keyboard
3. トラックパッド / Trackpad
4. 画面表示 / Display
5. プレビュー画像 / Preview Images

For Japanese, use the approved Japanese sidebar and page titles above, superseding
the earlier 2026-09-09 preference for English sidebar headings. Retain brand names
(AeroKit, AeroSpace, macOS, Mission Control, Dock) and gesture modes (Natural, Reversed)
in English, while explaining their observable outcome in natural Japanese around them.
Use familiar, beginner-oriented explanations: use natural action and result labels
for feature sections (ワークスペース一覧, ウインドウ一覧, ウインドウの連続切り替え);
describe on-screen HUD elements simply as a workspace-name bar (ワークスペース名バー);
explain App Windows as windows belonging to the frontmost application across workspaces
rather than an app list (アプリ一覧); and describe window arrangement as layout style
(並べ方). AeroSpace is detected automatically, so avoid wording implying manual
pairing or online connection.
The preview-age control is a refresh threshold upon opening the grid, not a retention
or periodic deletion timer. App exclusions apply to future saved workspace preview
images, not live Exposé rendering. Each page's reset is strictly scoped to its own
settings (Display reset restores shared workspace order and name strip; Keyboard reset
restores shortcuts, selection and cycling; Trackpad reset restores gestures; Preview
Images reset restores auto-refresh and freshness threshold).


On 2026-09-22, settings were flattened for first-time use: workspace controls
precede window controls, related controls share one section, and six disclosure
groups were removed. Antigravity's `gemini-3.8-flash-high` directly reviewed the
views and authored the new Basics heading in all seven languages. Following the
user's decision to remove Accessibility-dependent input handling entirely, all
Accessibility permission copy and Option-number selection settings were removed.
Plain number/letter selection and permission-free window cycling remain.

On 2026-09-23, `gemini-3.8-flash-high` through Antigravity directly read all five
settings pages, their help and setup sheets, and the relevant preferences and
navigation code before editing the Japanese catalog. A follow-up editorial pass
checked ambiguous wrap-around descriptions, shortcut selection versus switching,
and preview-update wording against the implementation. Use natural action labels
and complete explanatory sentences; shortening text alone is not an improvement.
Japanese qualifiers use fullwidth parentheses, such as （実験的機能） and
（デフォルト）. Wrap-around descriptions cover both ends of the workspace order.
The swipe direction shown in its help sheet now applies immediately, and the
distance setting uses one slider. Avoid copy about draft or unapplied settings
where no such state exists.

The experimental window switcher starts without an assigned shortcut. Gemini
also authored the setup button, its accessibility label and the unassigned-state
instruction across all seven languages. Assigning the first shortcut enables the
feature; replacing an existing shortcut preserves an intentional off state.

The seven `Localizable.strings` catalogs live in
`Sources/AeroKitCore/Resources`. They are copied into the signed application by
`build-app.sh`. Language names are written in their native language so users can
recover from an accidental language choice. System default resolves the Mac's
preferred supported language at launch, falling back to English.

Use `L10n.tr("Complete sentence with \(value)")` inside view bodies. Store
`LocalizedStringResource` for persistent app-generated messages, translating when
displayed, so changing language also updates existing warnings. Keep user content
and technical commands outside the catalogs. Avoid assembling translated sentence
fragments or using translated strings as persistent identifiers.

Validate resources on macOS:

```sh
python3 packages/app/scripts/validate-localizations.py
swift build --package-path packages/app \
  -Xswiftc -emit-localized-strings \
  -Xswiftc -emit-localized-strings-path -Xswiftc /tmp/aerokit-localized-strings
python3 packages/app/scripts/validate-localizations.py \
  --extracted /tmp/aerokit-localized-strings
```

Use a fresh extraction directory and a full rebuild when auditing every source
file; incremental builds emit only changed files. The validator checks locale
coverage, duplicate keys and interpolation argument positions, types and counts.
`LocalizationTests` cover persistence, regional language matching and interpolation
without changing user-provided names. Visual QA should include Japanese and a
longer European translation at the minimum settings-window size.

On 2026-09-24, settings were regrouped by feature into four destinations:
一般 / General, ワークスペース / Workspaces, ウインドウ / Windows and
プレビュー画像 / Preview Images. Two-option choices became segmented controls
whose subtitle explains only the selected side, and toggle subtitles describe
the enabled behavior instead of switching with the state. The eight new
strings (page subtitles, reset messages, the shortcut-row hint, the clear
button and the name-strip note) were authored by `gemini-3.8-flash` through
Antigravity for all seven languages. Keys no longer referenced by the source
were removed from every catalog.
