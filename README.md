# Jabber

A macOS menu bar app for local speech-to-text transcription using on-device ASR models.

All audio is processed entirely on-device — nothing leaves your Mac. (Optional transcript refinement via OpenRouter sends the transcript text to a cloud provider you choose; this is off by default.)

> **⚠️ Personal Project Notice**
>
> This code was written for my own use. It is **not supported** in any way.
> No issues, no PRs, no questions answered, no guarantees it works.
> You're welcome to use it, fork it, modify it, sell it, burn it, whatever.
> Just don't expect anything from me. Good luck.

## Requirements

- macOS 26.0+ (Tahoe)
- Apple Silicon required

## Installation

Download the latest DMG from [Releases](../../releases), open it, and drag Jabber to Applications.

## Building from Source

```bash
swift build
./scripts/build_mlx_metallib.sh debug
```

If the Metal library build reports a missing Xcode Metal Toolchain, install it:

```bash
xcodebuild -downloadComponent MetalToolchain
```

For a release build with signing:

```bash
./scripts/release.sh --skip-notarize  # local testing
./scripts/release.sh                   # full signed + notarized DMG
```

## Usage

1. Launch Jabber — it lives in your menu bar
2. Click the icon or use the global hotkey to start dictation
3. Speak, and text appears wherever your cursor is

Model options are available in Jabber's main window (menu bar → **Open Jabber**, or **Cmd-,** while Jabber is active):

- **Qwen3-ASR** — 52 languages, highest accuracy. Available in four sizes:
  - 1.7B 8-bit (~2.5GB) — recommended for non-English
  - 1.7B 4-bit (~1.3GB)
  - 0.6B 8-bit (~1GB)
  - 0.6B 4-bit (~600MB)
- **Nemotron** (~600MB) — NVIDIA Nemotron Speech Streaming, English-only with native punctuation & capitalization
- **Apple Speech** — built-in macOS 26 speech recognition, no download required

During onboarding, you'll pick a language and Jabber recommends the best model for it.

## Permissions

Jabber requires two macOS permissions to provide the full experience:

- **Microphone**: required to capture speech.
- **Accessibility**: required for type-into-active-app mode.

On first launch or first use, macOS may ask for microphone permission and may open a system permission prompt for accessibility when you type into the active app.

If permission prompts do not appear:

- Open **System Settings > Privacy & Security**
- Enable Jabber for **Microphone**
- Enable Jabber for **Accessibility**

## Auto-Updates

Jabber uses [Sparkle](https://sparkle-project.org/) for auto-updates. On first launch (after the second run), it will check for updates automatically.

### Setting up EdDSA keys (maintainers)

1. Download Sparkle from [releases](https://github.com/sparkle-project/Sparkle/releases)
2. Run `./bin/generate_keys` to create a keypair (stored in Keychain)
3. Export the private key: `./bin/generate_keys -x sparkle_private_key`
4. Add the private key as `SPARKLE_EDDSA_PRIVATE_KEY` secret in GitHub
5. Add your public key to `SUPublicEDKey` in Info.plist

### Appcast

The workflow generates `appcast.xml` as an artifact. Host it at:
`https://rselbach.github.io/jabber/appcast.xml`

## License

MIT — see [LICENSE](LICENSE).

## Acknowledgements

Jabber uses the following open-source models and libraries:

### Models

| Model | Creator | License | Link |
|-------|---------|---------|------|
| Qwen3-ASR | Alibaba Qwen Team | [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) | [huggingface.co/Qwen/Qwen3-ASR-0.6B](https://huggingface.co/Qwen/Qwen3-ASR-0.6B) |
| Nemotron Speech Streaming | NVIDIA | [OpenMDW-1.1](https://www.openmodeldefinition.org/) | [huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b) |
| Apple Speech | Apple | [Apple SLA](https://www.apple.com/legal/sla/) | Built-in macOS 26 Speech framework |

Qwen3-ASR (MLX) and Nemotron (CoreML) conversions by [aufklarer](https://huggingface.co/aufklarer).

### Libraries

| Library | License | Link |
|---------|---------|------|
| [speech-swift](https://github.com/soniqo/speech-swift) | Apache 2.0 | ASR/TTS models for Apple Silicon |
| [Sparkle](https://sparkle-project.org/) | MIT | Software update framework |
| [mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter) | MIT | Media remote control |
