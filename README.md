# Mare Synchronos Self‑Hosting with Podman

This repository contains a set of Kubernetes manifests and helper scripts for self‑hosting a complete [Mare Synchronos](https://github.com/marika‑exarch/MareSynchronos) server stack.  Mare Synchronos is a suite of services that allow players of Final Fantasy XIV to synchronise character appearance and file data.  The files in this repository provide a simple way to run all of the necessary services – database, cache, application servers and a reverse proxy – on a single machine using [Podman](https://podman.io/) and its Kubernetes YAML support.

## Repository Contents

| File/Directory      | Purpose                                                                                                      |
|--------------------|---------------------------------------------------------------------------------------------------------------|
| **`db.yaml`**      | Defines two pods: a **PostgreSQL** database and a **Redis** cache.  Both pods expose their default ports on the host (5432 for PostgreSQL and 6379 for Redis) and declare persistent volumes. |
| **`mare-template.yaml`** | A template manifest describing the four Mare Synchronos application pods (server, auth service, services pod and static files server) and a ConfigMap containing their JSON configuration.  Placeholders such as `${HOST_IP}`, `${DOMAIN}` and Discord credentials are substituted when generating the final manifest. |
| **`nginx.yaml`**    | Defines an **NGINX** reverse‑proxy pod and an accompanying ConfigMap with its `nginx.conf`.  The proxy forwards requests to the appropriate Mare services based on the request path. |
| **`generate-yaml.sh`** | A helper script that uses [`envsubst`](https://www.gnu.org/software/gettext/manual/html_node/envsubst-Invocation.html) to expand environment variables in `mare-template.yaml` and write the resulting manifest to `mare.yaml`.  It also prints the values used for `HOST_IP` and `DOMAIN` for transparency. |
| **`start_linux.sh`** | Simple start‑up script that invokes `podman kube play` for each manifest in the correct order: first `db.yaml`, then `mare.yaml`, and finally `nginx.yaml`. |

> **Note**
>
> The `node_modules` directory, `package.json` and the JavaScript/TypeScript tooling in this repository are part of the environment used to create presentation slides during the challenge and are not needed for running the server.  You can safely ignore these files when deploying Mare Synchronos.

## Prerequisites

Before attempting to run the services, ensure that your system meets the following requirements:

* **Podman 3.x or newer with Kubernetes support.**  These manifests rely on `podman kube play`, which reads Kubernetes YAML files and creates Podman pods accordingly.  On some distributions this functionality is provided by a separate package (`podman‑kube`).
* **Bash and core utilities.**  The helper scripts are Bourne‑compatible shell scripts.
* **`envsubst`** (part of the GNU `gettext` package).  This utility is used by `generate-yaml.sh` to replace variables in the template.  On many Linux systems you can install it via your package manager (for example, `sudo apt install gettext-base` or `sudo dnf install gettext`).
* **A Linux host with the necessary ports free.**  By default the manifests expose multiple services directly on the host.  See the [Ports](#ports) section below for details.

## Generating the Application Manifest

The main Mare Synchronos pods are defined in `mare-template.yaml`, but the file contains placeholders (e.g. `${HOST_IP}`) that need to be replaced with real values.  Use `generate-yaml.sh` to create a final `mare.yaml` with your settings:

```sh
cd path/to/this/repository

# Optionally override any of these values before running the script.
export HOST_IP="192.168.0.202"        # IP address on which Podman will bind application ports
export DOMAIN="example.com"          # Public DNS name used in generated URLs
export DISCORD_BOT_TOKEN="<bot-token>"
export DISCORD_CHANNEL_ID="<channel-id>"
export DISCORD_OAUTH_CLIENTID="<client-id>"
export DISCORD_OAUTH_CLIENTSECRET="<client-secret>"

./generate-yaml.sh
# The script prints the variables used and writes mare.yaml
```

If you do not define any variables, the script falls back to the defaults encoded inside it.  **Do not use the provided default Discord credentials in production.**  They exist purely as placeholders; always set your own tokens before deploying.

After running the script you should see a new file called `mare.yaml` in the repository.  This file is what you will pass to `podman kube play` in the next step.

## Deploying the Services

There are two ways to bring up the stack: running `start_linux.sh` or executing each command manually.  The script simply runs the necessary `podman` commands with a short pause between them, so you can use it as a reference.

### Using the provided start script

```sh
./start_linux.sh
```

The script executes three commands in order:

1. `podman kube play db.yaml` – creates the PostgreSQL and Redis pods.
2. `podman kube play mare.yaml` – deploys the Mare Synchronos application pods defined in your generated manifest.
3. `podman kube play nginx.yaml` – starts the reverse‑proxy pod.

Each `podman kube play` invocation returns immediately, so the script includes `pause 5` between them.  Depending on your shell, you may need to replace `pause 5` with `sleep 5`.

### Manual deployment

If you prefer to run the commands yourself or tailor the order, execute the following commands individually:

```sh
podman kube play db.yaml
sleep 5
podman kube play mare.yaml
```

When finished, Podman will create several pods named according to the `metadata.name` fields in the YAML files (e.g. `postgres`, `redis`, `mare-server`, etc.).  You can inspect them with `podman pod ps` and view their logs with `podman pod logs <pod-name>`.

## Ports

The following ports are exposed on the host by default.  You can change the host‑side bindings by setting `HOST_IP` or editing the YAML files directly.

- **PostgreSQL** – `5432` (db.yaml)
- **Redis** – `6379` (db.yaml)
- **Mare main server (HTTP)** – `6000` (mare.yaml)
- **Mare main server (gRPC)** – `6005` (mare.yaml)
- **Authentication service** – `6100` (mare.yaml)
- **Services pod** – `6110` (mare.yaml)
- **Static files / CDN** – `6200` (mare.yaml)
- **Public entry point** – `8080` (nginx.yaml)

With the provided `nginx.yaml`, all public traffic should go through the proxy on port `8080`.  Internally, the proxy routes requests to the appropriate Mare service based on the path:

- `/auth/…` → authentication service at `mare-auth:6100`
- `/oauth/…` → OAuth endpoints in the authentication service
- `/cache/…` → static files server at `mare-files:6200`
- `/marehub/…` → WebSocket/hub endpoint on the main server
- `/` (root) → main server at `mare-server:6000`

## Configuration and Secrets

The `mare-template.yaml` includes a `ConfigMap` called `mare-config` with four JSON configuration files: `authservice-standalone.json`, `files-standalone.json`, `server-standalone.json` and `services-standalone.json`.  These files configure database connections, logging, rate limiting and other settings for each service.  In particular, the `MareSynchronos` sections define important values such as JWT secrets, Redis connection strings and metrics ports.

Before deploying in a real environment you should:

* Change all hard‑coded passwords and secrets.  The sample configuration uses `secretdevpassword`, `secretredispassword` and a dummy JWT string; these must be replaced with your own secure values.
* Update the `ExpectedClientVersion` in `server-standalone.json` to match the version of the Mare Synchronos client you expect to connect.
* Modify any limits (e.g. `MaxExistingGroupsByUser`, `MaxGroupUserCount`) according to your community’s needs.

You can edit the template JSON strings directly inside `mare-template.yaml` or mount your own configuration file via a volume or ConfigMap; just ensure the correct `subPath` names are used in the pod definitions.

## Shutting Down and Cleanup

To stop the services, use `podman kube down` with the name of the manifest you played:

```sh
podman kube down db.yaml
podman kube down mare.yaml
```

Alternatively, you can remove individual pods with `podman pod rm -f <pod-name>`.  Persistent volumes created by Podman (such as the PostgreSQL data volume) will remain unless explicitly removed.

## Troubleshooting

Here are a few common issues and their remedies:

* **`envsubst` not found.**  Install the GNU `gettext` package via your distribution’s package manager.
* **Ports already in use.**  Modify the `hostPort` values in the YAML files or change the `HOST_IP` environment variable before generating the manifest.
* **Services can’t find PostgreSQL or Redis.**  Ensure that the `db.yaml` pod is running and that `/tmp/postgresql-sockets` is writable on your host (the manifests mount the PostgreSQL socket directory there).  The `wait-for-postgres` init container in `mare-template.yaml` waits until PostgreSQL is reachable on port 5432 before starting the main server.

## Caveats and Disclaimer

This setup is intended for testing and personal use.  It does **not** constitute a hardened production deployment.  You are responsible for configuring TLS, access control, backups, monitoring and scaling according to your operational requirements.  The Mare Synchronos software itself is governed by its own licence; consult the upstream project for legal terms.

---

Please feel free to open issues or submit pull requests if you encounter problems or wish to improve this deployment guide.