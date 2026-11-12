# Open issues and known limits

- Live provider acceptance: each request/response contract is covered with fixtures. A real OpenAI, Anthropic, or Ollama run requires a configured account or installed model.
- Shortcut capture depends on macOS Accessibility access. When the source app does not expose its selection, the shortcut sends Copy to it, reads the clipboard, and restores the earlier clipboard; a clipboard manager will see that copy. The fallback runs only when the app gives no usable accessibility answer, and never in a password field or while a ReplyAI window has the keyboard. It is untested on a real Mac: check Chrome and Slack, including with Option and Shift still held from the shortcut. Services and Paste provide alternate paths. The shortcut is one of three presets, not a free recorder.
- No in-app update check: the repository is private, so the app cannot read its releases without credentials. Tagging `v*` publishes a GitHub Release through `.github/workflows/release.yml`.
- Saved API keys are legacy Keychain items tied to the code signature. The first Developer ID signed build may ask once per saved key (not yet observed).
- Open Workspace and Dock reopen rely on the main window having appeared once in the session.
- Project snapshots are manually refreshed. Each reply uses bounded leading excerpts; review the payload when relevant facts are far down a file.
- Distribution: `scripts/build-release.sh` produces a release zip and can sign and notarize it, but it needs a Developer ID identity and notarytool profile. CI builds it ad hoc only.
