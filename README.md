# Jabber

A macOS menu bar app for local speech-to-text transcription using [WhisperKit](https://github.com/argmaxinc/WhisperKit).

All audio is processed entirely on-device — nothing leaves your Mac.

> **⚠️ Personal Project Notice**
>
> This code was written for my own use. It is **not supported** in any way.
> No issues, no PRs, no questions answered, no guarantees it works.
> You're welcome to use it, fork it, modify it, sell it, burn it, whatever.
> Just don't expect anything from me. Good luck.

## Requirements

- macOS 14.0+
- Apple Silicon recommended (Intel works but slower)

## Installation

Download the latest DMG from [Releases](../../releases), open it, and drag Jabber to Applications.

## Building from Source

```bash
swift build
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
