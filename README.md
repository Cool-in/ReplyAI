# ReplyAI

ReplyAI is a native Mac writing desk for drafting replies in your voice. Give it a comment, a few examples of your writing, and optional product facts from a project. Read and edit the result, then copy it back wherever you’re replying.

## Build and open

Requires macOS 14 or later and a Swift 6 toolchain. Run from this checkout:

```sh
./scripts/build-app.sh
open "$HOME/Library/Developer/BuildCaches/ReplyAI/macos/Debug/ReplyAI/ReplyAI.app"
```

The script builds a native app for this Mac, packages the text Service, and signs it ad hoc for local use. Quit ReplyAI before packaging a new build. For a distributable build, run `./scripts/build-release.sh`. It makes an optimized, zipped app in `dist/`. Set `SIGN_IDENTITY` to a Developer ID Application identity and `NOTARY_PROFILE` to a notarytool keychain profile to sign and notarize it; without them the zip is only ad hoc signed and will be blocked on other Macs. For an isolated walkthrough, quit first, then open the bundle with `--args --temporary-library`. Voice and project changes made in that session disappear on quit; do not save or remove real API keys during QA.

## How to use

1. **Set up your writing desk.** Choose a provider and model in **Settings**. Save an API key for a cloud provider. Add a few posts or messages you wrote in **My voice**. In **Projects**, optionally review and save selected files such as a README, `CLAUDE.md`, or `AGENTS.md` for product facts.
2. **Highlight a comment.** With ReplyAI running, select text in the other app. Choose **Services → Draft Reply with ReplyAI** in its context menu or app menu. ReplyAI opens **Quick Reply**, a floating panel over the source app. You can also press the global shortcut, **Option + Shift + R** by default (change it under **Settings → Capture and reading**). When an app does not expose its selection to accessibility, as many browsers and chat apps do not, the shortcut copies the selection for you and then puts your clipboard back. The first time you use the shortcut, click **Enable Selection Access** if prompted, allow ReplyAI under **System Settings → Privacy & Security → Accessibility**, then return to the source app and retry.
3. **Generate, edit, and copy.** Choose a project and length if useful. **Review Input** shows what will go to the model. Click **Generate Reply** or press **⌘Return** (the button becomes **Regenerate** once a draft exists). The reply appears as it is written. Edit the draft, then press **⇧⌘C**: in Quick Reply that copies the draft and closes the panel, and in the workspace it copies. Paste it where you’re replying. A reply that hits the length limit keeps the text that arrived. If you regenerate over a draft you liked, **Previous Draft** swaps it back. A failed or cancelled request leaves your draft as it was. **Esc** hides the panel and keeps your draft. **Open Workspace** opens the full app.

When an app or text field does not expose its selection, copy the comment, choose **Quick Reply** from the ReplyAI menu bar or **Open Quick Reply** in **How to Use**, then click **Paste**. Services and Paste work without the shortcut’s Accessibility permission. If the shortcut cannot register, **Settings**, **How to Use** and the menu bar menu all say so, and you can pick another shortcut in Settings. If Services is missing, launch the packaged app once and check **System Settings → Keyboard → Keyboard Shortcuts → Services**.

Click **Try Example** in the workspace to walk through the flow with a fictional product and a labeled simulated draft. The example runs without a model request.

## Providers

| Provider | Setup |
| --- | --- |
| [Ollama](https://docs.ollama.com/api/chat) | Run Ollama locally, then pick a model under **Choose Installed Model** in Settings or enter its exact name. ReplyAI connects to `127.0.0.1:11434`. Choose a model that runs on the device to keep inference local. |
| [OpenAI](https://platform.openai.com/docs/api-reference/responses) | Enter a model ID enabled for your API account and save its API key. ReplyAI uses the Responses API with response storage disabled. |
| [Anthropic](https://platform.claude.com/docs/en/api/messages/create) | Enter a Claude API model ID enabled for your account and save its API key. ReplyAI uses the Messages API. |

A consumer ChatGPT or Claude subscription is separate from API access. API providers may charge for usage and apply their own retention policies. ReplyAI sends no prompt until you choose **Generate Reply**. It does not load consumer Claude Projects, ChatGPT conversations, or private Codex or Claude Code session histories. To use project knowledge from those workflows, select the documentation you already keep locally.

## Data on your Mac

The voice library, project snapshots, and provider preferences live in `~/Library/Application Support/ReplyAI/Library.json`. Provider keys are held separately in the macOS Keychain and can be removed in Settings. Current comments and drafts live in memory. The app has no analytics, network service of its own, or background indexing.

Project imports accept explicitly selected UTF-8 Markdown or text files up to 64 KiB. The app blocks hidden paths, symlinks, credential-like filenames, and some common credential patterns. These checks cannot detect every sensitive detail. Redact private text before saving it and use **Review Input** to verify what will be sent. Drafts use the first 2,500 characters of each included file, up to 10,000 project characters total. Generated claims can be wrong; review the draft before posting it.

## Develop and test

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test \
  --scratch-path "$HOME/Library/Developer/BuildCaches/ReplyAI/macos/Debug/ReplyAI"
```

`ReplyCore` holds persistence, project imports, prompt assembly, and provider adapters. `ReplyAI` owns the SwiftUI workspace, AppKit Quick Reply panel and Services integration, the global shortcut, clipboard controls, and Keychain access. Tests use temporary fixture files and mocked API responses. There are no third-party package dependencies.

See [the plan](docs/PLAN.md), [current verification](docs/STATUS.md), and [open issues](docs/ISSUES.md). MIT licensed.
