# claude-code-hooks

A collection of [SessionStart hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) for Claude Code. Each hook runs asynchronously on session start — no startup delay.

## Hooks

| Hook | Description |
|---|---|
| [claude-code-update](claude-code-update/) | Auto-update Claude Code CLI from npm (once per day) |
| [sync-compound-engineering](sync-compound-engineering/) | Sync [compound-engineering](https://github.com/EveryInc/compound-engineering-plugin) plugin from upstream (once per day) |

## Install

```bash
git clone https://github.com/kirvahe/claude-code-hooks.git
cd claude-code-hooks
./install.sh
```

The installer copies scripts to `~/.claude/scripts/` and shows you the JSON to add to `~/.claude/settings.json`.

### Install a single hook

```bash
./install.sh claude-code-update
```

### Manual install

See each hook's README for copy-paste instructions.

## How hooks work

Claude Code [hooks](https://docs.anthropic.com/en/docs/claude-code/hooks) are shell commands triggered by lifecycle events. These hooks use `SessionStart` with `"async": true` so they run in the background without blocking your session.

Each hook uses a timestamp file to throttle checks to once per 24 hours.

## Add your own hook

1. Create a folder with your script and a README
2. Add the folder/script mapping to the `HOOKS` array in `install.sh`
3. Submit a PR

## License

MIT
