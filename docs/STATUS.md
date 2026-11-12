# Current status

ReplyAI 0.3.0 (4). 0.2.1 added the app icon (`Resources/AppIcon.icns`, drawn from `Resources/AppIcon.svg`). 0.3.0 is the Paper Desk restyle: cream sidebar, the icon's violet as the accent, flat inset fields for the comment and brief, and a serif draft sheet, in the workspace and Quick Reply.

- 0.2.0 adds streamed replies for all three providers, the provider’s own wording in error messages, a Previous Draft swap after regenerating, an installed model menu for Ollama, and a Copy Draft menu shortcut. Saves are debounced and one network session is reused.
- 0.2.0 is verified by CI on a macOS runner: the full package builds, the Swift Testing suite passes (stream parsing, streamed requests through a stubbed session, provider error text, the Ollama model list, plus the earlier coverage), and both the debug bundle and the release zip package and pass `codesign --verify --strict`.
- Not yet verified for 0.2.0: hands-on use of the running app. The streamed draft, Previous Draft, and the Ollama model menu have not been exercised in the UI, and no live provider request has been made.

The notes below describe the 0.1.0 (1) debug bundle QA.

- Stable Xcode 27.2 compiled the app for the local Mac. `plutil` passed on the app Info.plist and `codesign --verify --strict` passed on the locally signed bundle.
- Bundle: `~/Library/Developer/BuildCaches/ReplyAI/macos/Debug/ReplyAI/ReplyAI.app`. Executable SHA-256: `73798f3e05b35f64948ea566618c355fc87449f19714421ac344d2b26b9ad212`.
- The refreshed workspace builds with a two-column composer, compact layout, dark palette, and updated library and settings screens. Quick Reply is 480 × 520 points, with a separate 480 × 280 replacement confirmation. Both draft editors use 15 point system text. How to Use opens Quick Reply directly.
- At minimum window width, the workspace stacked its editors and scrolled to the draft and Copy Draft without horizontal clipping. The test window returned to normal size. The dark appearance launch stayed light on this Mac, so dark visuals remain unverified.
- Seven Swift Testing functions passed in the prior build, including three provider variants. They covered bounded prompts, project imports, library persistence, provider contracts, and error mapping. The current work reused the same core.
- The workspace demo, prompt preview, editing, and copying passed. The native editor hid the scrollbar tracks and preserved wheel scrolling and undo with a 1,250 character draft. The voice sample add flow passed in a temporary library.
- The project file preview, snapshot save, and selected-project prompt excerpt passed in the temporary library.
- The original Service captured selected text in TextEdit and from an X post in Chrome. The updated Service opens Quick Reply over Chrome. The compact build showed the separate replacement view and restored the existing source and draft after Keep Current. Demo generation, Copy Draft, Open Workspace with draft retention, and the How to Use launch button passed in the compact build. Escape with draft retention passed in the first Quick Reply build.
- The global shortcut registered. Physical shortcut activation and Accessibility based capture remain unverified because the available UI automation sent a key event to the focused app.
- The original app sent a validated Ollama-shaped request to a temporary loopback test server and displayed its fixture response. After the server stopped, the app showed a connection error and preserved an edited draft.
- Retained the current 151 MiB build cache and stopped the loopback server. Removed the temporary unit test fixtures, `QA-Context.txt`, and `QA-Selection.rtf` after use. There were no obsolete build caches to remove.
- Available disk space was 91,644,948 KiB at the start of the redesign and 90,410,436 KiB after final QA. The redesign reused the stable cache and left no superseded cache artifacts. The temporary QA session was closed and ReplyAI was reopened normally.
- Live provider generation requires a user-configured model and, where applicable, an API key.
