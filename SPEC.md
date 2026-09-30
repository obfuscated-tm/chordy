# Chordy — Spec

A free, fully-local, Wispr Flow–style dictation app for macOS. Hold a key, talk, and cleaned-up text is pasted wherever your cursor is. Named after vocal cords.

Decisions were settled in a design interview on 2026-09-30. This file is the source of truth; update it when a decision changes.

## Principles

1. **Local only.** Audio and text never leave the Mac.
2. **Do it in code, use the LLM only for judgment.** Anything deterministic (prefix/suffix, casing commands, file paths, filler words) is a rule, not a prompt instruction.
3. **Worst case is "slightly messy", never "wrong".** A diff guard falls back to the less-cleaned text if the LLM changes too much.
4. **Chordy never writes for you.** Cleanup edits what you said; it doesn't add content.
5. **Users never see a prompt.** Modes are configured with a slider and toggles.

## Architecture

```
chordy/                      macOS menu-bar app (SwiftUI + AppKit), Xcode project
Packages/ChordyCore/         platform-neutral Swift package (reused by iPhone in v2)
  ChordyCore                 audio → transcript → rules → cleanup → guard
  chordy (CLI)               `transcribe`, `process`, later `eval`
```

Pipeline for one utterance:

```
Fn down → AudioRecorder (16 kHz mono) → Fn up
  → Transcriber (WhisperKit | Apple SpeechAnalyzer)
  → TextRules (level ≥ 1: tidy; dev rules)
  → TextCleaner LLM (level ≥ 2; skipped for short utterances)
  → DiffGuard (reject over-edits → fall back to rules-only text)
  → prefix/suffix → Paster (clipboard + ⌘V, clipboard restored)
```

### Engines

| Tier | Speech | Cleanup | Notes |
|---|---|---|---|
| **Downloaded (default)** | WhisperKit, `large-v3-v20240930_turbo_632MB` (Recommended) or `small.en` (Lite) | MLX Swift, Qwen3 4B / 1.7B at 4-bit | Downloaded on first run from Hugging Face |
| **Built-in** | Apple SpeechAnalyzer / SpeechTranscriber | Apple Foundation Models | No download; needs macOS 26+ and Apple Intelligence for cleanup |

The Built-in tier is used immediately while the downloaded models fetch in the background. Users can switch tiers in settings. If a download fails (offline, or a network filter like Securly blocking huggingface.co), Chordy stays on Built-in and says why.

### Distribution

- A `.app` on GitHub Releases, signed with a free Apple ID Personal Team certificate. Not notarized, so first launch needs System Settings → Privacy & Security → **Open Anyway**; the README shows how.
- Not sandboxed: posting ⌘V and global hotkeys need Accessibility, which the App Store sandbox forbids.
- Open source vs. closed: undecided.

## Interaction

### Keys

| Keybind | Action |
|---|---|
| Hold **Fn** | Dictate using the mode auto-picked for the frontmost app |
| Double-tap **Fn** | Lock recording on (hands-free); press Fn again to finish |
| **Fn + Ctrl** | Force **Raw** mode |
| **Fn + Option** | Command mode (v1.1) |

All rebindable in Settings (✅ done): modifier-only shortcuts (fn, Right ⌥, fn ⌃…, side-specific) or key combos (⌥Space, F5…), captured with a system event tap so combos don't leak into the focused app. **Esc** cancels a dictation. Users should set System Settings → Keyboard → "Press 🌐 key to" → **Do Nothing**; onboarding checks this.

### Modes

A mode = name, keybind, cleanup level, toggles (dev rules, trailing space), optional prefix/suffix, optional list of apps it auto-applies to. Built-ins:

| Mode | Default level | Auto-applies to |
|---|---|---|
| Default | 2 Clean | everything else |
| Prompt | 3 Smooth | Claude, ChatGPT, browsers on AI sites (v1: Claude/ChatGPT apps) |
| Terminal | 1 Tidy | Terminal, iTerm, Ghostty, Warp |
| Essay | 2 Clean | Pages, Word, Google Docs (browser) |
| Raw | 0 Raw | — |

An "Advanced: custom instructions" box exists per mode, collapsed (v1.1).

### Cleanup slider

| Level | Name | Does | LLM? |
|---|---|---|---|
| 0 | Raw | transcript verbatim | no |
| 1 | Tidy | whitespace, capitalization, spoken "new line/new paragraph", strip `[BLANK_AUDIO]` | no |
| 2 | Clean | + remove fillers, apply self-corrections ("3, no wait, 4") | yes |
| 3 | Smooth | + fix grammar, keep wording | yes |
| 4 | Polish | + restructure, format lists | yes |

The diff guard's tolerance scales with the level.

### Dev rules (deterministic, toggle per mode)

- "at src slash app dot ts" → `@src/app.ts`
- "camel case user name" → `userName` (also snake, kebab, pascal, constant)
- Text inside backticks is never touched.

### UI

- **Menu-bar icon**: status, current engine, mode quick switch, history, settings, quit.
- **Pill** at bottom-center while dictating: live waveform, mode name, processing spinner. After pasting: "↩ Undo · Raw" for about 3 seconds, which replaces the paste with the raw transcript.
- **Onboarding**: mic permission → Accessibility permission → Fn key setting → engine choice (Recommended ~3 GB / Lite ~1.2 GB, Built-in works meanwhile) → "try it here" box.

### Data

- History: text only (raw + cleaned + mode + app), 30 days by default, "never save" option. "Keep audio" is off by default.
- Personal dictionary (fed to the transcriber as vocabulary and to the cleaner) and voice snippets.

## Roadmap

### Milestone 1 — core loop ✅ (in progress)
- [x] `ChordyCore` package: recorder, transcribers (WhisperKit + Apple), rules, cleaner (Foundation Models), diff guard, hotkey state machine
- [x] `chordy` CLI: `transcribe <audio>`, `process <text>`
- [x] Menu-bar app: Fn hold / double-tap lock → record → transcribe → clean → paste, pill with waveform

### v1
- [ ] Onboarding window
- [ ] Modes + per-app auto-pick + Fn+Ctrl raw; settings UI with slider
- [ ] MLX cleanup engine (Qwen3 4B / 1.7B), model download manager with progress
- [ ] "Undo · Raw" swap
- [ ] Dictionary + snippets
- [ ] History window with raw/clean diff, persistence and retention
- [ ] Music pause, sound cues, silence trimming, mic picker
- [ ] Eval set (~40 messy→clean pairs) + `chordy eval`
- [ ] README with the Open Anyway walkthrough, release script

### v1.1
Command mode (rewrite selection) · French · stats · cursor-context opt-in · custom instructions box

### v2
iPhone keyboard extension + app-bounce (needs the $99 account to ship to others) · project-aware vocabulary · whisper mode · integrations (URL scheme, Shortcuts, CLI dictation)

### Later / undecided
Open source vs. closed · notarization · auto-learning dictionary
