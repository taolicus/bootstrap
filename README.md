# bootstrap

This is a simple personal bootstrap for putting a new project online. It splits the work into small, repeatable steps and leaves the project to own its own build and deploy. Two scripts live here:

- `bootstrap.sh` — adds a file-based workflow (issues/tasks/features) to a project repo so an agent keeps durable notes across sessions.
- `vps.sh` — sets up the host side on `ssh tao`: creates a user, allocates a loopback port, writes a systemd unit, writes an nginx vhost, and issues a Let's Encrypt certificate.

`repo.sh` is a small helper to create a GitHub repo from the current directory with `gh`.

## Personal project bootstrap process

Do the steps in order. The parts marked "done on the project" are not automated here; they belong in the project repo (`deploy.sh`, build scripts, etc.).

| Step                                            | Tool                    | What to do                                                                                                                                                                               |
| ----------------------------------------------- | ----------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. DNS (manual for now)                         | DNS provider            | Point `<name>.<domain>` at the VPS IP. For `pifia.net` use `pifia.net` as the domain. Port 80 must reach the host before requesting a certificate.                                       |
| 2. Bootstrap                                    | `bootstrap.sh`          | Add the workflow files to the project repo.                                                                                                                                              |
| 3. Repo                                         | `repo.sh` or `git`/`gh` | Create the remote and push. `repo.sh` does this if you run it from the project directory.                                                                                                |
| 4. Placeholder (done on the new project itself) | Project repo            | Add a small placeholder app and a `deploy.sh` that builds/copies it to the host. Match the unit's `ExecStart` and make it listen on the port the host assigns (or honor `-addr`/`ADDR`). |
| 5. Deploy (also done on the project)            | Project `deploy.sh`     | Build for `linux/amd64`, copy the binary to `/home/<user>/<name>/<name>` on the host (replace by rename), restart the service, and health check.                                         |
| 6. Host                                         | `vps.sh`                | Create the user, allocate a port, write the systemd unit and nginx vhost, and issue the certificate. Run again to fill gaps or to fix a bare unit when the binary's flags change.        |

### Step 2: add the workflow

```sh
sh /path/to/bootstrap/bootstrap.sh path/to/project
```

Modes: `--upgrade` (keep edited files as `<file>.new`), `--force` (overwrite everything), `--init` (run `git init` if needed). Optional `--phone NAME` and `--laptop NAME` record which devices are used. See `--help`.

After bootstrapping:

```sh
git -C path/to/project add -A
git -C path/to/project commit -m "Add project workflow"
```

### Step 3: repo

From inside the project directory:

```sh
sh /path/to/bootstrap/repo.sh
```

It initializes git if needed, creates a public GitHub repo named after the directory with `gh repo create`, commits and pushes to `origin`. You can also do this manually.

### Step 6: host setup

From the project directory, or pass the name explicitly. Connects to `DEPLOY_HOST` (default `tao`) as root and is idempotent.

```sh
sh /path/to/bootstrap/vps.sh
sh /path/to/bootstrap/vps.sh coverletter
DOMAIN=tequionet.org sh /path/to/bootstrap/vps.sh komikan
PORT=18090 sh /path/to/bootstrap/vps.sh
```

What it does:

- Creates the service user (default `dev`) and `/home/<user>/<name>` if missing.
- Allocates a loopback port starting at `BASE_PORT` (default `18080`), skipping ports already used by other units or listeners. A project with an existing unit keeps its port. Pass `PORT` to force one.
- Writes `/etc/<name>.service` pointing to `/home/<user>/<name>/<name>` and `ADDR=<ip>:<port>`. If the binary exists and `-h` shows `-addr`, `vps.sh` adds `-addr <ip>:<port>` to `ExecStart`. If it shows `-open` defaulting to true, it adds `-open=false`. A later run repairs a bare `ExecStart`.
- Creates `/etc/<name>.env` with a random `LOBBY_KEY` once (never rotated). Loads it via a drop-in.
- Writes an nginx vhost for `<name>.<domain>` proxying to the port, adds `/events` with buffering off, enables it, tests and reloads nginx.
- Requests a Let's Encrypt certificate with `certbot --nginx` if none exists.
- Starts the service if the binary is executable, otherwise prints instructions.

Environment: `DEPLOY_HOST` (default `tao`), `DOMAIN` (default `pifia.net`), `PORT`, `BASE_PORT` (default `18080`), `APP_USER` (default `dev`).

## What this is not

- **Not a full installer.** `vps.sh` assumes `nginx`, `certbot`, and `systemctl` are already on the host. It does not configure firewalls, DNS, or install packages.
- **Not a build system.** Building, copying, and restarting the binary is the project's responsibility (see its `deploy.sh`).
- **Not an enforcement mechanism for the workflow.** `bootstrap.sh`'s `lint.sh` checks bookkeeping (filenames, dependencies, outcomes, links). It cannot judge scope or honesty.

## Examples on this host

| Project                                                | Public                                                 | Unit                  | Port    |
| ------------------------------------------------------ | ------------------------------------------------------ | --------------------- | ------- |
| [kxp](https://github.com/taolicus/kxp)                 | [kxp.pifia.net](https://kxp.pifia.net)                 | `kxp.service`         | `18080` |
| [asteroids](https://github.com/taolicus/asteroids)     | [asteroids.pifia.net](https://asteroids.pifia.net)     | `asteroids.service`   | `18081` |
| [komikan](https://github.com/taolicus/komikan)         | [komikan.tequionet.org](https://komikan.tequionet.org) | `komikan.service`     | `18082` |
| [dungeon](https://github.com/taolicus/dungeon)         | [dungeon.pifia.net](https://dungeon.pifia.net)         | `dungeon.service`     | `18083` |
| [coverletter](https://github.com/taolicus/coverletter) | [coverletter.pifia.net](https://coverletter.pifia.net) | `coverletter.service` | `18084` |

## Requirements

- `bootstrap.sh`: POSIX `sh`, `awk`, `sed`, `find`, and one SHA-256 implementation for the manifest.
- `vps.sh`: POSIX `sh`, `ssh` to a root login on the VPS, and a host that already has `nginx`, `certbot`, `systemctl`, and `ss`.
- `repo.sh`: `git` and `gh` logged in.

## Status

Ruleset `0.2.0` for `bootstrap.sh`. `vps.sh` is a personal helper added to match the host layout described here.
