# Reader audio-session consolidation

Reader root main selects a divergent JapaneseLanguageTools revision, while Reader v3-hotfix selects the canonical repository main.

A detailed semantic comparison showed canonical main already supersedes the Reader-only branch for:
- cancellation-aware pronunciation downloads and stale-request fencing;
- typed spoken-audio leases;
- synthesized/recorded playback cleanup;
- HTTP download validation;
- ASCII-representation UTF-8 optimization and tests.

The remaining behavior worth forward-porting is priority-aware lease reconciliation. Reader read-aloud and Japanese pronunciation can overlap. The older Reader branch explicitly ranked intents:
recorded audio > read aloud > pronunciation.

This port adds only that missing policy to canonical main's newer implementation. It reconfigures the shared audio session when the effective highest-priority intent changes, downgrades when a higher-priority lease ends, and marks failed platform transitions unknown so the next operation retries a concrete configuration. Logical lease ownership still ends even when platform deactivation/reconfiguration fails.

The initial `6cffbb79` source port did not change dependencies. The 2026-10-05 follow-up aligns SQLiteData to Reader/Common exact 1.8.2, preserving iOS 15, and restores only the SQLiteData and swift-dependencies lock entries from Reader's former `47ecfea21` pin. It adds duplicate-release/replacement-ownership coverage and moves Darwin test scratch to Trash. Reader #209 separately replaces the deleted audio-test registration.

The previous five-test CI receipt applies only to `6cffbb79`. Run the six-case production-source priority suite and optimized Release source build for this follow-up; neither result establishes complete package or Reader consumer acceptance. The full package Release test target still uses DEBUG-only test seams unconditionally.

Runtime merge blocker: `JapaneseTTS.acquirePronunciationSession()` currently swallows acquisition failure before synthesized and recorded-ready playback. Reader's former pin guarded both starts. Restore guarded acquisition and verify rejection/retry behavior through the production playback paths before merging the runtime pin. Root/Lake tuple resolution, native test discovery and app acceptance remain open.

No TTS request ownership, download behavior, cache format, Reader root pin, signing, or CloudKit state changes in this follow-up.

Focused local verification (2026-10-05): the production-source priority harness passes six Debug runtime cases with no failures, and its optimized Release source build passes, using Xcode's Swift 6.4 / macOS SDK 27. This isolated harness excludes SQLiteData, JapaneseTTS playback and Reader/Lake consumers; those integration gates remain open.
