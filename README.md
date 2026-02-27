# SlackmojiEverywhere

Menu bar app for macOS that expands `:emoji_alias:` into emoji system-wide, similar to Slack.

## Requirements

- macOS 13+
- Swift 6 toolchain
- Accessibility permission for the app (required to monitor typing globally)

## Run locally

```bash
swift run
```

When prompted, grant Accessibility access in **System Settings → Privacy & Security → Accessibility**.

## Supported aliases

- Bundled Slack-style aliases from a generated dataset (`Sources/Resources/slack_emoji_aliases.json`)
- Custom aliases loaded from:

```text
~/Library/Application Support/SlackmojiEverywhere/custom_aliases.json
```

Example:

```json
{
  "partyparrot": "🦜",
  "shipit": "🚢",
  "myshrug": "¯\\_(ツ)_/¯"
}
```

Use the menu bar options **Open Custom Aliases…** and **Reload Aliases** after edits.

## Build DMG

```bash
./scripts/build_dmg.sh
```

Optional version:

```bash
./scripts/build_dmg.sh 0.1.0
```

Output:

```text
dist/SlackmojiEverywhere-<version>.dmg
```
