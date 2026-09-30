# Chordy

Free, fully local dictation for your Mac, in the style of Wispr Flow. Hold **fn**, talk, let go, and cleaned-up text appears wherever your cursor is. Your voice never leaves your Mac.

Named after vocal cords.

## What it does

- **Hold fn to talk, double-tap fn to go hands-free.** Press esc to cancel. Every shortcut can be changed in Settings.
- **Cleanup slider** with five steps: Raw, Tidy, Clean, Smooth, Polish. It removes ums and self-corrections ("3, no wait, 4" → "4") and fixes grammar. Chordy only edits what you said: it never answers your questions or adds content, and a built-in guard falls back to the lighter cleanup if the model changes too much.
- **Modes per app.** Prompt mode for Claude and ChatGPT, Terminal mode for terminals, Essay mode for Pages and Word, and Default everywhere else. You can make your own, give any mode its own shortcut, and hold **fn ⌃** for Raw.
- **Coding rules.** "at src slash app dot ts" becomes `@src/app.ts` and "camel case user name" becomes `userName`. Text in backticks is left alone.
- **↩ Raw**: right after a paste, click it in the pill to swap in exactly what you said.
- **Dictionary and snippets.** Teach it names and jargon, and fix things it hears wrong ("cordy" → "Chordy"). Say "my email" and it pastes your address.
- **History** of the last 30 days (you can change this or turn it off), showing what changed between what you said and what was pasted. Text only; audio is never saved.
- Pauses Music or Spotify while you talk, lets you pick a microphone, and trims silence.

## Installing

1. Download `Chordy-x.y.zip` from [Releases](../../releases), unzip it and drag **Chordy** into Applications.
2. Open it. macOS will say it "can't be opened" because the app isn't notarized (notarizing needs a paid Apple developer account).
3. Open **System Settings → Privacy & Security**, scroll down to the message about Chordy and click **Open Anyway**, then confirm. You only do this once.
4. The setup guide walks you through the microphone and Accessibility permissions, the fn key setting, and picking models.

Needs macOS 26 on Apple silicon. Cleanup with the built-in models needs Apple Intelligence turned on.

## Models

| Setup | Speech | Cleanup | Download |
|---|---|---|---|
| Recommended | Whisper large-v3 turbo | Qwen3 4B (MLX) | ~3 GB |
| Lite | Whisper small.en | Qwen3 1.7B (MLX) | ~1.2 GB |
| Built-in | Apple SpeechAnalyzer | Apple Intelligence | none |

Chordy uses the built-in models while downloads finish. Models download from Hugging Face. If a network filter (like a school's) blocks huggingface.co, Chordy says so and keeps using the built-in models.

## Building

Needs Xcode 26.

```bash
./scripts/run.sh          # build, copy to ~/Applications, launch
./scripts/release.sh      # Release build → build/Chordy-<version>.zip
```

Sign with your own (free) team: open `chordy.xcodeproj` → target **chordy** → Signing & Capabilities → Team.

The builds go to `$TMPDIR` on purpose, because files under `~/Documents` pick up extended attributes that break code signing.

### The MLX cleanup models

`Packages/ChordyMLX` runs Qwen3 locally with [MLX Swift](https://github.com/ml-explore/mlx-swift-lm). Building it needs Xcode's Metal toolchain, which you install once:

```bash
xcodebuild -downloadComponent MetalToolchain
```

The scripts pass `-skipMacroValidation` because mlx-swift-lm uses a Swift macro. In the Xcode app, click **Trust & Enable** when it asks.

Eval results on the 40 cases:

| Cleanup model | Exact | Similarity |
|---|---|---|
| Qwen3 4B (Recommended) | 27/40 | 0.97 |
| Apple Intelligence | 25/40 | 0.95 |
| Qwen3 1.7B (Lite) | 23/40 | 0.93 |

The Debug app can rerun this with `Chordy.app/Contents/MacOS/Chordy --mlx-eval Packages/ChordyCore/Evals/cleanup.json [recommended|lite]`.

### Core package and CLI

The speech, cleanup rules, guard and hotkey logic live in `Packages/ChordyCore`, so they can be reused by an iPhone version later.

```bash
cd Packages/ChordyCore
swift test
swift run chordy process "um at src slash app dot ts has a bug no wait two bugs" --level 2
swift run chordy transcribe recording.wav --engine whisper
swift run chordy eval --verbose         # 40 messy → clean cases, scored per cleanup level
swift run chordy mics
```

The design decisions are in [SPEC.md](SPEC.md).
