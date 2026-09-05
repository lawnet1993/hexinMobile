# Mandatory update dialog design QA

- Source visual truth: `C:\Users\86137\AppData\Local\Temp\codex-clipboard-cbb9796d-7fc8-412a-a5da-8d64bee9abb0.png`
- Implementation screenshot: `test/goldens/13-mandatory-update.png`
- Combined comparison: `test/evidence/update-dialog-735/01-source-vs-implementation.png`
- Viewport: 390 x 844 logical pixels at 1x golden density; source and implementation are both 390 x 844 pixels and required no density normalization.
- State: authenticated workbench with the mandatory update dialog open.
- Full-view evidence: the combined image places the user screenshot on the left and the final Flutter render on the right.
- Focused-region evidence: no separate crop was needed because the centered 342 px dialog, its typography, chips, notes and CTA are readable at original size in the combined image.

## Findings and comparison history

### Iteration 1

- P2, muddy surface hierarchy: the supplied runtime screenshot showed a gray-purple dialog surface that blended with the dimmed page.
  - Fix: the dialog owns an explicit white surface and transparent Material tint; release notes render directly on that surface without a separate background block.
- P2, first revision added a heavy outline-like shadow.
  - Fix: the post-fix pass removed elevation, shadow and border, and used a 36% neutral black modal barrier.
  - Post-fix evidence: the right side of `01-source-vs-implementation.png` has a clearly white, flat card without the gray-purple cast or dark halo.

## Required fidelity surfaces

- Fonts and typography: existing Microsoft YaHei/PingFang fallback, 17 px bold title, 13 px notes and 12 px metadata are preserved; no new wrapping appears.
- Spacing and layout rhythm: original compact 18 px side padding, 16 px radius, 342 px available width and 40 px CTA are preserved; the dialog remains centered.
- Colors and visual tokens: body is pure white, modal barrier is neutral black at `0x5C`, notes have no separate background or border, and semantic blue/red chips are unchanged.
- Image quality and assets: this dialog has no raster imagery; the existing Material download icon remains the product's icon-library asset.
- Copy and content: title, version, package size, mandatory label, release notes and download action are unchanged.

## Interaction and responsive verification

- Mandatory dialog remains non-dismissible by barrier tap and system back.
- Download action remains enabled and invokes exactly once.
- 320 x 640 portrait and 640 x 320 landscape with 150% text scale render without exceptions; long notes remain scrollable and the CTA stays reachable.
- Widget suite: 4/4 passed. Updated golden: 1/1 passed.
- Full Flutter suite: 1362/1362 passed; static analysis: 0 issues.
- The same APK was installed over the existing app on the emulator and realme device without clearing data. The workbench remained authenticated and showed no overflow or Flutter exception. The production dialog itself was not forced through server configuration; its exact production widget state is covered by the golden and interaction tests.

No actionable P0, P1 or P2 visual differences remain for this focused background correction.

final result: passed
