# ReplyAI v0 plan

Product and architecture plan by Astra. Implementation by Sol 6.1.

**Goal:** Draft replies from selected text on a Mac, using the user’s writing samples and the facts in their chosen project docs. Let the user inspect, edit, and copy each draft.

1. Ship a SwiftUI app with AppKit Services and paste as the two routes into the composer. An explicit Generate action sends the prompt. Copy is the final action.
2. Keep a small, editable library of writing samples and voice preferences. Add project contexts from user-selected text files, with a preview before saving the snapshot. Attach one project per draft and show the exact excerpts before generation.
3. Share prompt assembly and a provider interface across OpenAI, Anthropic, and local Ollama. Store API keys in Keychain. Keep source content local until the user requests a draft. Preserve the previous draft when a provider call fails.
4. Package the SwiftPM executable as a Mac app and verify it against one native Services host, the paste fallback, the fictional demo, library persistence, and mocked requests to all three providers.

A universal shortcut, browser extension, account syncing, history ingestion, and automatic publishing are outside v0. Claude Code and Codex project context means local documents the user selects.

References: [Apple Services bundle keys](https://developer.apple.com/documentation/bundleresources/information-property-list/nsservices), [providing a Service](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/SysServices/Articles/providing.html), [Claude Code memory](https://code.claude.com/docs/en/memory), [OpenAI Responses](https://platform.openai.com/docs/api-reference/responses), [Claude Messages](https://platform.claude.com/docs/en/api/messages/create), and [Ollama chat](https://docs.ollama.com/api/chat).
