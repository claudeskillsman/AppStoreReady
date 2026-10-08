# Claude skill (optional)

AppStoreReady works on its own from the command line. If you use [Claude Code](https://claude.com/claude-code), this folder has a skill that runs the audit, double-checks the findings against your code, and turns them into a prioritized list of fixes. It can also make the simple fixes for you.

## Install

```sh
mkdir -p ~/.claude/skills
cp -R integrations/claude/app-store-ready ~/.claude/skills/
```

Restart Claude Code. Then type `/app-store-ready` in any project, or ask "Is my app App Store ready?"

The skill uses an installed `appstoreready`, or clones and builds this repository into `~/.appstoreready/AppStoreReady`.
