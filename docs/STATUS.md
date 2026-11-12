# Current status

ReplyAI 0.4.0 (5).

## What changed since 0.2.0

- 0.2.1: app icon (`Resources/AppIcon.icns`, drawn from `Resources/AppIcon.svg`).
- 0.3.0: Paper Desk restyle of the workspace and Quick Reply.
- 0.4.0: review fixes.
  - Library.json decodes leniently, carries a schema version, and a file from a newer version is refused rather than overwritten. A storage error offers Show in Finder.
  - Length and project are remembered. New settings: generate on capture, editor text size, and a choice of three global shortcuts.
  - The shortcut falls back to copying the selection when accessibility returns nothing, then restores the clipboard.
  - Draft state (generate, stream, fail, cancel, previous draft) lives in `ReplyCore.DraftState` with tests.
  - A reply cut short by the length limit keeps its text. A dropped connection has its own message.
  - Undo history is cleared when the app replaces editor text. Tab and Shift Tab move between fields.
  - VoiceOver announcements for a finished or failed draft. Error text uses a darker red.
  - Quick Reply has Copy and Close. Example mode ends as soon as the example comment is edited.
  - Removing a sample or snapshot asks first. Each import rejection has its own message.
  - Non-content diagnostics through `os.Logger` (subsystem `dev.replyai.mac`). A tag-triggered release workflow.
  - The empty band at the top of the window is gone, and the main window drags from any empty area.

## Verification

- 0.4.0 was built on a Mac with Swift 6.4.2 (Xcode, macOS 26 SDK): `swift build` finished with no warnings and `swift test` passed all 18 test functions, including the streamed request tests.
- `scripts/build-app.sh` produced the bundle, `codesign --verify --strict` passed, and the app was installed and launched.
- Exercised in the running app: the example flow generates a draft, the Paper Desk workspace and Settings render, the Ollama panel reports when Ollama is not running, and the top spacing fix shows.
- Not yet exercised by hand: a live provider request, the global shortcut and its copy fallback (check Chrome and Slack), Quick Reply, the wide two column layout, dragging the window from empty areas, and the icon in the Dock.

## Earlier QA

These notes describe the 0.1.0 (1) debug bundle.

- Stable Xcode 27.2 compiled the app for the local Mac. `plutil` passed on the app Info.plist and `codesign --verify --strict` passed on the locally signed bundle.
- The refreshed workspace builds with a two-column composer, compact layout, dark palette, and updated library and settings screens. Quick Reply is 480 × 520 points, with a separate 480 × 280 replacement confirmation. Both draft editors use 15 point system text. How to Use opens Quick Reply directly.
- At minimum window width, the workspace stacked its editors and scrolled to the draft and Copy Draft without horizontal clipping. The test window returned to normal size. The dark appearance launch stayed light on this Mac, so dark visuals remain unverified.
- Seven Swift Testing functions passed in the prior build, including three provider variants. They covered bounded prompts, project imports, library persistence, provider contracts, and error mapping. The current work reused the same core.
- The workspace demo, prompt preview, editing, and copying passed. The native editor hid the scrollbar tracks and preserved wheel scrolling and undo with a 1,250 character draft. The voice sample add flow passed in a temporary library.
- The project file preview, snapshot save, and selected-project prompt excerpt passed in the temporary library.
- The original Service captured selected text in TextEdit and from an X post in Chrome. The updated Service opens Quick Reply over Chrome. The compact build showed the separate replacement view and restored the existing source and draft after Keep Current. Demo generation, Copy Draft, Open Workspace with draft retention, and the How to Use launch button passed in the compact build. Escape with draft retention passed in the first Quick Reply build.
- The global shortcut registered. Physical shortcut activation and Accessibility based capture remain unverified because the available UI automation sent a key event to the focused app.
- The original app sent a validated Ollama-shaped request to a temporary loopback test server and displayed its fixture response. After the server stopped, the app showed a connection error and preserved an edited draft.
- Live provider generation requires a user-configured model and, where applicable, an API key.
