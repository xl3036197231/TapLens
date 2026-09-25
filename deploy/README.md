# TapLens ECS deployment

This deployment runs three containers on one ECS instance:

- `nginx`: the only public listener, currently on HTTP port 80;
- `api`: FastAPI on the private Compose network;
- `worker`: exactly one Playwright worker using the same SQLite volume as the API.

The named volume `taplens-data` stores the SQLite database and expiring screenshot
artifacts. All services use `restart: unless-stopped` and define container health
checks. `GET /healthz` verifies that Nginx can reach the API and that the API can
read SQLite and write the artifact directory.

Container JSON logs rotate at 10 MiB with three files retained per service, so a
long-running competition demo cannot fill the system disk with Docker logs.

The Python and Nginx base images are pinned by digest through the DaoCloud mirror
because the Beijing ECS cannot reliably reach Docker Hub. Digest pinning prevents
an upstream tag change from silently changing the deployed base image.
Playwright browser binaries are downloaded through the npmmirror mirror for the
same regional connectivity reason.
Python packages use Alibaba Cloud's public PyPI mirror during image builds.
Debian system packages use Alibaba Cloud's Debian mirror.
The runtime image installs Chromium's headless shell only; TapLens does not need
the full interactive Chrome package.

## First deployment without a domain

Copy `.env.example` to the untracked `.env`, set a random JWT secret of at least
32 characters, and set `TAPLENS_PUBLIC_BASE_URL` to the ECS HTTP origin. Keep
`TAPLENS_ENVIRONMENT=staging`: staging requires a strong secret and rejects
`TAPLENS_TEST_ALLOWED_ORIGINS`, while allowing the temporary HTTP origin.

```bash
docker compose build
docker compose up -d
deploy/scripts/status.sh
```

The temporary public endpoints are:

- API health: `http://<ECS_IP>/api/v1/health`
- deployment readiness: `http://<ECS_IP>/healthz`
- controlled fixture: `http://<ECS_IP>/controlled/go/campus`

The controlled fixture is fictional, has no external assets, and blocks form
submission in the page. It is exposed only for the competition integration
period and should be removed with the deployment afterward.

## HTTPS cutover

After a domain has completed real-name verification and ICP filing:

1. point an `api` subdomain A record at the ECS public IP;
2. issue a certificate for that hostname;
3. add the certificate and port 443 listener to Nginx, redirect port 80 to HTTPS;
4. set `TAPLENS_ENVIRONMENT=production`;
5. set `TAPLENS_PUBLIC_BASE_URL=https://api.<domain>`;
6. recreate `api` and `worker`, then repeat health and mobile-network acceptance.

Production refuses an HTTP public base URL and both staging and production refuse
`TAPLENS_TEST_ALLOWED_ORIGINS`.

## Operations

Run all commands from the repository root on the ECS host. The scripts validate
`deploy/.env` and the Compose model before changing containers.

### Inspect the deployment

```bash
deploy/scripts/status.sh
```

The check requires all three containers to be healthy, verifies that exactly one
worker exists, runs SQLite `PRAGMA quick_check`, requests the local readiness
endpoint, and reports volume and filesystem usage.

### Apply an update

```bash
deploy/scripts/update.sh
```

If the API is running, the update creates an online backup before rebuilding and
recreating the stack. It waits until every service is healthy and then runs the
full status check. Use `--skip-build` only when the required image is already
present. In a Git checkout the deployed revision is recorded in the ignored
`deploy/.deployed-revision` file.

For a code rollback, check out or copy the last known-good repository revision
onto the ECS host and run `deploy/scripts/update.sh` again. The pre-update backup
keeps the database recoverable if the older code needs matching data.

### Back up persistent data

Create a consistent online backup:

```bash
deploy/scripts/backup.sh
```

The archive is written under the ignored `backups/` directory with mode `0600`
and a SHA-256 checksum. It contains a SQLite online-backup snapshot, its
`quick_check` result, a format manifest, and current screenshot artifacts. It
does not contain `deploy/.env` or the JWT secret. Pass a directory as the first
argument to store the archive elsewhere.

Restore an archive only after copying it to the ECS host:

```bash
deploy/scripts/restore.sh backups/taplens-backup-YYYYMMDDTHHMMSSZ.tar.gz --confirm-restore
```

Restore verifies the checksum when present, creates a safety backup of the
current data, stops API and worker writes, validates archive paths and SQLite,
atomically replaces the database and artifacts, then waits for the whole stack
to become healthy.

### Stop or remove the deployment

Stop and remove containers while preserving the named volume:

```bash
deploy/scripts/cleanup.sh
```

Permanently remove the Compose volume and locally built images:

```bash
deploy/scripts/cleanup.sh --purge-data taplens
```

The destructive form first writes a backup under `backups/`. After the contest,
also remove the ECS TCP/80 security-group rule and delete `/opt/taplens` after
copying any backups that must be retained. The base VPS operating system is not
modified by the cleanup script.
