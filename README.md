# t3-sbx

One command to run [T3 Code](https://github.com/pingdotgg/t3code) agents inside a [Docker Sandbox](https://docs.docker.com/ai/sandboxes/) (`sbx`).

T3 Code has no built-in Docker Sandboxes support yet, but it can connect to a sandbox over SSH. This script does the setup for you:

- creates a sandbox for the current folder, with the T3 Code kit included
- starts it detached, so it doesn't auto-stop when T3's SSH connection drops
- turns on SSH access to it
- checks that the T3 server can start inside, and installs build tools if it can't
- prints exactly what to type into T3 Code

## Requirements

- Docker Sandboxes CLI **0.37.0+**, logged in (`sbx login`)
  - macOS: `brew install docker/tap/sbx`
  - Windows: `winget install Docker.sbx` (run the script from Git Bash or WSL)
- `ssh` and `bash`
- T3 Code desktop app

## Usage

From your project folder:

```bash
curl -fsSL https://raw.githubusercontent.com/Abdelrahman-Qazzaz/t3-sbx/main/t3-sbx.sh | bash
```

To give the sandbox a custom name:

```bash
curl -fsSL https://raw.githubusercontent.com/Abdelrahman-Qazzaz/t3-sbx/main/t3-sbx.sh | bash -s -- my-sandbox
```

Or download `t3-sbx.sh` and run `bash t3-sbx.sh [name]`.

Optional environment variables:

| Variable | Default  | What it does                                      |
|----------|----------|---------------------------------------------------|
| `AGENT`  | `claude` | Agent template the sandbox is based on            |
| `KIT`    | (auto)   | Use a specific T3 kit instead of the known names  |

## Then, in T3 Code

1. **Settings → Connections → add environment → SSH**
2. Host: `<name>.sbx`, User: `agent`
3. Connect. The first connection can take a minute.
4. Add a project, pick the sandbox environment, and type the folder path the script printed. It's the **same path as on your Mac** (e.g. `/Users/you/projects/my-app`). Don't pick `~/workspace`: it exists in the sandbox but is empty.

## Cleanup

```bash
sbx rm <name>
```

Also remove the environment in T3 Code; it doesn't delete the sandbox for you.

## Troubleshooting

- **T3 Code keeps saying "reconnecting"**: the sandbox probably stopped (check `sbx ls`). Sandboxes started by `sbx create` or an attached `sbx run` auto-stop ~30s after their last session disconnects. Restart it detached with `sbx run -d --name <name>`, or just rerun the script. You also need this after a reboot or `sbx stop`.
- **"Remote T3 server did not become ready"**: usually missing build tools or a full disk. Rerun the script; it checks both.
- **SSH test fails**: run `ssh <name>.sbx` yourself to see the error, and make sure `sbx setup ssh` succeeded.

Not affiliated with T3 or Docker.
