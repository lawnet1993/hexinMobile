# Mobile todo tabs and profile design QA

## Comparison target

- Source visual truth: `Mobile/docs/audits/mobile-continuation-20260901/todo-tab-user-reference.png`
- Todo implementation: `Mobile/docs/audits/mobile-continuation-20260901/52-todo-tab-indicator-stable-after-real.png`
- Profile before/after evidence: `Mobile/docs/audits/mobile-continuation-20260901/56-profile-stable-before-after-comparison.png`
- Full-view comparison: `Mobile/docs/audits/mobile-continuation-20260901/53-todo-tab-source-after-comparison.png`
- Device/state: realme RMX3366, profile APK, server offline, cached authenticated state
- Viewport: 1080 × 2400 physical pixels, Android density 480 dpi, approximately 360 × 800 logical pixels at device pixel ratio 3
- Density normalization: the source and implementation captures are both 1080 × 2400, so no resampling was applied before the side-by-side comparison.

## Findings

- No remaining P0/P1/P2 visual mismatch in the requested todo indicator region.
- The selected tab indicator now has a measured 4–6 logical-pixel gap below the label instead of reading as a text underline. Label widths, inline badges, horizontal scrolling, edge fades, search density, and the bottom navigation remain unchanged.
- The profile header no longer repeats the terminal account on the top-level page. The account remains available under Account & Security. The profile summary is under 64 logical pixels high, presence is a compact dot-and-label state, and the logout action now follows the same surface hierarchy as the settings groups.
- Offline `状态未知`, `安全连接不可用`, and `暂时无法同步` values are intentional runtime states, not static design copy.

## Required fidelity surfaces

- Fonts and typography: existing application font stack, weights, truncation, and line heights were preserved. The selected tab remains the only emphasized label.
- Spacing and layout rhythm: the indicator gap and profile vertical density were corrected without enlarging touch controls or changing the single-row tab structure.
- Colors and visual tokens: existing primary, secondary-text, surface, success, and error tokens were reused. No new palette was introduced.
- Image quality and asset fidelity: the real cached user avatar and existing Material/TDesign-compatible icon system remain in use; no placeholder or generated asset was added.
- Copy and content: top-level profile account duplication was removed; account details remain discoverable in the security page. Offline state copy remains truthful.

## Interaction and runtime checks

- Todo and Profile bottom-navigation transitions were exercised on the real device.
- The selected todo tab, inline badge, horizontal overflow, and profile summary size are covered by widget geometry assertions.
- `flutter analyze` passed.
- The full Flutter suite passed: 272 tests.
- The profile APK built, installed, and stayed alive on the real device. Android runtime logs contained no crash entry in the final capture window.

## Comparison history

1. P2: the indicator visually touched the tab label. Added explicit bottom space and measured the rendered geometry; an initial 5-pixel padding produced only a 3-pixel rendered gap.
2. P2 fix: calibrated the component padding to produce a verified 4–6-pixel rendered gap, then captured the stable real-device state.
3. P2: the Profile summary repeated the account, used an oversized status capsule, and presented logout as a dominant outlined action.
4. P2 fix: reduced the summary to name and department, changed presence to a compact dot-and-label, and changed logout to a normal surface action. Stable real-device before/after evidence was captured.

## Follow-up polish

- None for this focused pass. Server-dependent online presence and device-sync content should be rechecked after the test service recovers.

## Profile settings continuation

- Scope: Account & Security, Notification Settings, Network & Security, Login Devices, Appearance & Language, Help & Feedback, and About.
- Account evidence: `Mobile/docs/audits/mobile-continuation-20260901/69-account-security-before-after.png`.
- Notification evidence: `Mobile/docs/audits/mobile-continuation-20260901/70-notification-before-after.png`.
- About evidence: `Mobile/docs/audits/mobile-continuation-20260901/71-about-before-after.png`.
- P1 state fix: an unavailable realtime channel previously left Account & Security showing cached `已验证·在线`; it now shows `已验证·状态未知` until realtime presence is available.
- P2 density fix: password fields are at most 40 logical pixels high and the submit button is 118 × 36 logical pixels.
- P2 loading fix: Notification Settings now renders a 52-pixel offline sync row with retry instead of a large indeterminate spinner card.
- P2 density fix: the About brand block is at most 110 logical pixels high while preserving version, update, platform, and managed-policy rows.
- Final real-device APK stayed alive and the Android runtime log contained no crash. `flutter analyze` and all 273 Flutter tests passed.

final result: passed
