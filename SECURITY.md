# Security and verifying a download

## Verify a release

Releases are published at https://github.com/idan2025/translatorai/releases. Each has the APK and a
`.sha256` file.

```sh
sha256sum -c translatorai-X.Y.Z-android-arm64.apk.sha256
apksigner verify --print-certs translatorai-X.Y.Z-android-arm64.apk
```

Every release since 0.2.0 is signed with the same key. The signer certificate's SHA-256 is:

```
28:32:36:E1:A0:05:38:C0:18:F2:65:5A:FC:15:E2:48:F5:64:64:D5:47:71:24:FE:91:3F:0E:C5:3E:30:76:BB
```

(`CN=TranslatorAI, O=idan2025`, RSA 4096). If `apksigner` shows a different fingerprint, do not
install it. The in-app updater has the same protection by itself: Android refuses an update signed
with another key.

## Why Play Protect may still ask to scan it

Google Play Protect asks to scan apps from developers it has not seen before. That is about the
app's reputation, not its signature, and only publishing through Google Play (or time and installs)
removes it. Tapping "Send for scanning" once is safe.

## How downloads are protected

- Speech models are fetched from pinned URLs (fixed commits) and checked against a SHA-256 in the
  app before they are used; a file that does not match is deleted.
- An update is checked against the SHA-256 GitHub records for the file, and Android's installer
  asks you to confirm. Only files from the app's own update folder can be handed to the installer.
- No cleartext (http) traffic is allowed.

## Reporting a problem

Open an issue at https://github.com/idan2025/translatorai/issues, or for something sensitive use
GitHub's private vulnerability reporting on the repository.
