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

No dependency versions, lockfile, TTS request ownership, download behavior, cache format, Reader root pin, signing, or CloudKit state changes.
