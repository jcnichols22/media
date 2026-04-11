# Gluetun Quarterly Manual Test Checklist

## Purpose
Safely test a candidate `gluetun` upgrade (with `qbittorrent` dependency) in a controlled, manual window.

**Rule:** never run gluetun/qbittorrent unattended.

---

## Preconditions
- You are available for 20–30 minutes.
- Current stack is healthy (`./status-check.sh`).
- Compose is digest-pinned.
- Rollback path is ready.

---

## 1) Baseline Snapshot

```bash
cd /home/josh/media
./status-check.sh

docker inspect -f 'gluetun={{.Config.Image}}' gluetun
docker inspect -f 'qbittorrent={{.Config.Image}}' qbittorrent

docker exec qbittorrent sh -c 'wget -qO- https://ipinfo.io/ip 2>/dev/null || curl -fsSL https://ipinfo.io/ip 2>/dev/null'
```

Record:
- current gluetun digest
- current qbit digest
- current VPN egress IP

---

## 2) Backup Compose Before Test

```bash
cd /home/josh/media
cp docker-compose.yml docker-compose.yml.bak.gluetun-test-$(date +%Y%m%d-%H%M%S)
```

---

## 3) Set Candidate Gluetun Digest

Get latest digest:

```bash
docker buildx imagetools inspect qmcgaw/gluetun:latest | awk '/^Digest:/ {print $2; exit}'
```

Update `docker-compose.yml` gluetun image line to candidate digest.

Validate compose:

```bash
docker compose config -q
```

---

## 4) Upgrade gluetun + qbittorrent (manual)

```bash
docker compose pull gluetun qbittorrent
docker compose up -d gluetun qbittorrent
```

---

## 5) Validation (must all pass)

```bash
cd /home/josh/media
docker compose ps gluetun qbittorrent

docker inspect -f 'gluetun state={{.State.Status}} health={{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' gluetun
docker inspect -f 'qbit state={{.State.Status}}' qbittorrent

docker inspect -f 'qbit networkMode={{.HostConfig.NetworkMode}} ports={{json .HostConfig.PortBindings}}' qbittorrent

docker exec qbittorrent sh -c 'wget -qO- https://ipinfo.io/ip 2>/dev/null || curl -fsSL https://ipinfo.io/ip 2>/dev/null'

docker logs --tail 120 gluetun
```

Pass criteria:
- gluetun health = `healthy`
- qbittorrent running
- qbit still on `network_mode: service:gluetun` (no direct host port bindings)
- qbit egress IP is VPN egress (not your home WAN IP)
- no sustained healthcheck/DNS flap loops in gluetun logs after a few minutes

---

## 6) Rollback (if any check fails)

Restore prior compose and recreate only affected services:

```bash
cd /home/josh/media
# restore previous known-good compose file
cp docker-compose.yml.bak.gluetun-test-<timestamp> docker-compose.yml

docker compose config -q
docker compose up -d gluetun qbittorrent
docker compose ps gluetun qbittorrent
```

Then re-run validation from section 5.

---

## 7) Document Outcome

Update `README.md` after the test with:
- test date/time
- candidate digest
- pass/fail
- rollback used (yes/no)
- notes (health flaps, endpoint behavior, etc.)

Optional commit message:

```text
ops(media): quarterly gluetun manual test (pass/fail + notes)
```

---

## Quick Decision Matrix

- **All checks pass** → keep candidate digest
- **Any safety check fails** → rollback immediately
- **Unclear result** → rollback and re-test later
