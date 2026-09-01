# Mobile chat bubble design QA

- Source visual truth: `C:\Users\86137\AppData\Local\Temp\codex-clipboard-7377790c-aff6-49d3-9fc7-f32b7a8f94b4.png`
- Supplemental interaction reference: `https://translations.telegram.org/en/android/chat_list/?mode=screenshots`
- Implementation screenshot: `docs/evidence/619-mobile-protocol-upgrade-20260901/group-avatar-first-real.png`
- Interaction evidence: `docs/evidence/619-mobile-protocol-upgrade-20260901/chat-telegram-read-receipt-real.png`
- Automated visual: `test/goldens/05-chat.png`
- Viewport: 1080 x 2400 physical pixels on RMX3366; Flutter logical viewport 360 x 800 at 3x density.
- State: authenticated direct conversation with incoming, outgoing, short, long and repeated messages.
- Comparison: the user source and implementation were opened together at the same physical viewport. A focused comparison was required for message bubbles, avatars, timestamps and read receipts; the rest of the chat shell was intentionally preserved.

## Findings and comparison history

### Iteration 1

- P1, repeated visual identity: every historical message repeated a large avatar and created a loose vertical rhythm.
  - Fix: consecutive messages from the same sender within five minutes are clustered; the cluster keeps one 30 px avatar on the final message.
  - Evidence: `chat-telegram-real.png` shows repeated incoming and outgoing runs with one avatar at each cluster tail.
- P1, status detached from content: the read receipt sat outside the bubble and looked like a separate label.
  - Fix: `HH:mm` and pending, failed, sent or read status now share the bubble footer. The read icon remains a compact tappable entry to the read-receipt sheet.
  - Evidence: the real-device screenshot shows timestamps and double checks inside outgoing bubbles; `chat-telegram-read-receipt-real.png` confirms the sheet opens.
- P2, rigid bubble geometry: saturated full-blue bubbles and large padding made short messages look like buttons.
  - Fix: content-sized 14 px bubbles, 11/7 px internal padding, a soft outgoing blue token, white incoming bubbles and 3 px clustered spacing.
- P2, missing message chronology: message time was not visible beside each item.
  - Fix: every message now renders a compact `HH:mm` label and date changes use a small centered date chip.

### Iteration 2

- P1, identity over-correction: the first Telegram-inspired pass removed direct-chat avatars entirely.
  - Fix: restored both incoming and outgoing avatars while retaining cluster deduplication.
  - Post-fix evidence: `chat-telegram-real.png` shows the peer avatar on the left and current-user avatar on the right without per-message repetition.

### Iteration 3

- P1, identity visibility remained ambiguous: cluster deduplication still hid the avatar beside intermediate messages and made those rows appear anonymous.
  - Fix: every visible incoming and outgoing message now keeps its real avatar; clustering only compresses spacing and repeated group-member names.
  - Post-fix evidence: `chat-avatar-every-message-real.png` shows the peer and current-user avatars beside every visible message on the real device.

### Iteration 4

- P1, current-user portrait regression: outgoing bubbles reserved the avatar slot but only forwarded `avatarDataUrl`; accounts using the desktop-compatible `avatarKey` fell back to a name initial.
  - Fix: the current member's `avatarKey` and `avatarDataUrl` now travel together into every outgoing message avatar.
  - Post-fix evidence: `avatar-key-fix-real-chat.png` and `avatar-key-fix-emulator-own-chat.png` show real portraits on both sides of group history, including every outgoing row.

### Iteration 5

- P1, repeated identity and delayed attribution: time-based clusters repeated the same portrait after five minutes, while keeping the only portrait at the final bubble delayed sender recognition.
  - Fix: consecutive messages from the same sender on the same calendar day form one identity group even across longer pauses. The sender name and the single real avatar both stay on the first message; compact spacing remains limited to messages within five minutes.
  - Post-fix evidence: `group-avatar-first-real.png` shows one 林川 portrait and one sender name at the first 18:41 message, with no repeated portrait through 20:00.

## Required fidelity surfaces

- Fonts and typography: message copy uses 15 px with 1.32 line height; metadata uses 9 px medium text; long identifiers wrap without colliding with metadata.
- Spacing and layout rhythm: bubbles size to content, nearby messages use 3 px gaps, longer pauses retain 9 px separation, and the first-message avatar slot keeps every bubble aligned.
- Colors and tokens: the product blue family is retained with a softer outgoing surface; incoming borders use a low-contrast neutral token.
- Image quality and assets: existing real member avatars and cached avatar rendering are preserved; no placeholder or generated image replaced them.
- Copy and content: server message text is unchanged; only presentation metadata was added.

## Verification

- Flutter analyze: passed with fatal infos enabled.
- Full Flutter test suite: 266/266 passed.
- Golden suite: 13/13 passed.
- Real-device navigation render: 3 frames, 0 janky frames, 50th percentile 7 ms, 90th percentile 14 ms.
- Primary interactions: open conversation, render grouped history, long/short message layout and open read-receipt drawer all passed.

No actionable P0, P1 or P2 findings remain for this message-bubble pass.

final result: passed
