# Jabber

A macOS menu bar app for local speech-to-text transcription using on-device ASR models.

All audio is processed entirely on-device — nothing leaves your Mac.

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

Model options are available in Settings:

- Qwen3-ASR: Qwen3-ASR 1.7B 8-bit (~2.5GB) — 52 languages, highest accuracy
- Parakeet: NVIDIA Parakeet TDT v3 0.6B INT8 (~634MB) — 25 European languages, fastest
- Nemotron: NVIDIA Nemotron Speech Streaming 0.6B INT8 (~600MB) — English-only, native punctuation

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

Public Domain — see [LICENSE](LICENSE). Do whatever you want with it.

## Acknowledgements

Jabber uses the following open-source models and libraries:

### Models

| Model | Creator | License | Link |
|-------|---------|---------|------|
| Qwen3-ASR | Alibaba Qwen Team | [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) | [huggingface.co/Qwen/Qwen3-ASR-0.6B](https://huggingface.co/Qwen/Qwen3-ASR-0.6B) |
| Parakeet TDT v3 | NVIDIA | [CC-BY-4.0](https://creativecommons.org/licenses/by/4.0/) | [huggingface.co/nvidia/parakeet-tdt-0.6b-v3](https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3) |
| Nemotron Speech Streaming | NVIDIA | [OpenMDW-1.1](https://www.openmodeldefinition.org/) | [huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b](https://huggingface.co/nvidia/nemotron-speech-streaming-en-0.6b) |

Parakeet TDT v3 CoreML conversion by [aufklarer](https://huggingface.co/aufklarer/Parakeet-TDT-v3-CoreML-INT8).

### Libraries

| Library | License | Link |
|---------|---------|------|
| [speech-swift](https://github.com/soniqo/speech-swift) | Apache 2.0 | ASR/TTS models for Apple Silicon |
| [Sparkle](https://sparkle-project.org/) | MIT | Software update framework |
| [mediaremote-adapter](https://github.com/ejbills/mediaremote-adapter) | MIT | Media remote control |
