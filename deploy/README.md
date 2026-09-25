# TapLens ECS deployment

This deployment runs three containers on one ECS instance:

- `nginx`: the only public listener, currently on HTTP port 80;
- `api`: FastAPI on the private Compose network;
- `worker`: exactly one Playwright worker using the same SQLite volume as the API.

The named volume `taplens-data` stores the SQLite database and expiring screenshot
artifacts. All services use `restart: unless-stopped` and define container health
checks. `GET /healthz` verifies that Nginx can reach the API and that the API can
read SQLite and write the artifact directory.

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
docker compose ps
curl http://127.0.0.1/healthz
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

## Backup and cleanup

Back up SQLite before upgrades or final cleanup:

```bash
docker compose exec api python -c "import sqlite3; source=sqlite3.connect('/var/lib/taplens/taplens.db'); target=sqlite3.connect('/var/lib/taplens/backup.db'); source.backup(target)"
```

Stopping the deployment preserves data. Removing the named volume permanently
deletes accounts, quota records, tasks, and remaining artifacts.
