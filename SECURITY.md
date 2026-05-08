# Security

MyMenuMind stores mymind API credentials in the macOS Keychain. The access key ID and secret are not written to `UserDefaults`, logs, test fixtures, or generated documentation.

## Before Publishing

Run the release check before pushing:

```sh
Scripts/check-release-ready.sh
```

The script runs the Swift test suite, builds the local app bundle, and scans the publishable source tree for common secret patterns. `.env`, `.claude/`, `.build/`, and `mymind-api-docs/` are intentionally ignored by Git because they are local or generated artifacts.

## API Key Scope

Use the narrowest mymind access key that supports the features you need:

- Search and recent items require read access.
- Quick notes require write access to create objects.

Rotate the mymind access key immediately if it is ever pasted into an issue, pull request, commit, or log.
