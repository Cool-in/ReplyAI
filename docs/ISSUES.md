# Open issues and known limits

- Live provider acceptance: each request/response contract is covered with fixtures. A real OpenAI, Anthropic, or Ollama run requires a configured account or installed model.
- Shortcut capture depends on macOS Accessibility access and the source app exposing its selection. Services and Paste provide alternate paths. The app reports if the shortcut could not register.
- Project snapshots are manually refreshed. Each reply uses bounded leading excerpts; review the payload when relevant facts are far down a file.
- Distribution: this is a locally signed build. A public installer needs a release signing and notarization workflow.
