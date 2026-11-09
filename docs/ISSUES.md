# Open issues and known limits

- Live provider acceptance: each request/response contract is covered with fixtures. A real OpenAI, Anthropic, or Ollama run requires a configured account or installed model.
- Shortcut capture depends on macOS Accessibility access and the source app exposing its selection. Services and Paste provide alternate paths. The app reports if the shortcut could not register.
- Project snapshots are manually refreshed. Each reply uses bounded leading excerpts; review the payload when relevant facts are far down a file.
- Distribution: `scripts/build-release.sh` produces a release zip and can sign and notarize it, but it needs a Developer ID identity and notarytool profile. CI builds it ad hoc only.
