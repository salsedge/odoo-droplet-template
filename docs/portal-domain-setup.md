# Add portal.loodon.com Domain

**Date:** 2026-03-25
**Status:** Ready to execute
**Requested by:** UBOP project (ubop-lite)
**Prerequisite:** DNS A record for `portal.loodon.com` -> `45.55.164.120` (already added, propagating)

---

## Quick Path

Use `make set-domain` to execute all steps automatically:

```bash
make set-domain \
  DOMAIN=portal.loodon.com \
  CERT_EMAIL=admin@loodon.com \
  ALIAS_DOMAIN=odoo.loodon.com
```

This uploads `scripts/ops/set-domain.sh` to the droplet and runs it. The script handles SSL, Nginx, and Odoo config in one pass with rollback on failure. See below for what it does and how to verify.

---

## Summary

Add `portal.loodon.com` as the primary domain for the Odoo instance. Keep `odoo.loodon.com` working as an alias that redirects to the primary domain.

## What `set-domain.sh` Does

The script (`scripts/ops/set-domain.sh`) executes seven steps:

### 1. DNS Verification

Confirms `portal.loodon.com` resolves to this server's public IP. Exits early if DNS hasn't propagated.

### 2. SSL Certificate — Expand to Cover Both Domains

Uses certbot's **webroot** method (consistent with initial setup via `04-setup-nginx.sh`):

```bash
certbot certonly --webroot --webroot-path /var/www/certbot \
  -d portal.loodon.com -d odoo.loodon.com \
  --expand --keep-until-expiring --non-interactive --agree-tos --email admin@loodon.com
```

**Note:** `--expand` adds domains to the existing certificate. The cert directory name stays as whatever certbot originally created (likely `/etc/letsencrypt/live/odoo.loodon.com/`). The script detects the actual path automatically.

### 3. Certificate Path Detection

Parses `certbot certificates` output to find the live directory. Does not assume the path matches the primary domain name.

### 4. Nginx — Deploy Multi-Domain Config

Backs up the current Nginx config, then deploys `config/nginx/odoo-multidomain.conf` with three server blocks:

**HTTP catch-all** — both domains redirect to `https://portal.loodon.com`:
```nginx
server {
    listen 80;
    server_name portal.loodon.com odoo.loodon.com;
    # certbot ACME challenge location preserved for renewals
    return 301 https://portal.loodon.com$request_uri;
}
```

**Primary HTTPS** — `portal.loodon.com` serves Odoo with full proxy config, security headers, HSTS, and route blocking.

**Alias redirect** — `odoo.loodon.com` returns 301 to `portal.loodon.com`:
```nginx
server {
    listen 443 ssl http2;
    server_name odoo.loodon.com;
    return 301 https://portal.loodon.com$request_uri;
}
```

If `nginx -t` fails, the previous config is automatically restored.

### 5. Nginx Test and Reload

```bash
nginx -t && systemctl reload nginx
```

### 6. Odoo — Update web.base.url

Updates `web.base.url` via psql (reads credentials from `/opt/odoo/.env`):

```sql
UPDATE ir_config_parameter SET value = 'https://portal.loodon.com' WHERE key = 'web.base.url';
```

**Idempotent:** If already set correctly, skips the update and Odoo restart.

**Alternative — Via Odoo UI:**
1. Log in to `https://portal.loodon.com/web`
2. Settings -> Technical -> Parameters -> System Parameters
3. Find `web.base.url`
4. Change value to `https://portal.loodon.com`
5. Save

### 7. Odoo Restart

```bash
docker restart odoo-app
```

Only runs if `web.base.url` was actually changed.

## Verification Checklist

After all changes:

- [ ] `https://portal.loodon.com` serves Odoo login page
- [ ] `https://odoo.loodon.com` 301-redirects to `https://portal.loodon.com`
- [ ] `http://portal.loodon.com` redirects to `https://portal.loodon.com`
- [ ] `http://odoo.loodon.com` redirects to `https://portal.loodon.com`
- [ ] SSL certificate covers both domains (`sudo certbot certificates`)
- [ ] HSTS header present on `portal.loodon.com`
- [ ] Odoo `web.base.url` = `https://portal.loodon.com`
- [ ] Odoo XML-RPC accessible at `https://portal.loodon.com/xmlrpc/2/common`
- [ ] No Nginx errors in log: `sudo tail -20 /var/log/nginx/error.log`

## Rollback

If something goes wrong, the script's trap handler restores the previous Nginx config automatically on failure.

For manual rollback:

```bash
ssh -p 9292 deploy@45.55.164.120
```

1. Restore Nginx config:
   ```bash
   # Find the backup (timestamped .bak file)
   ls -la /etc/nginx/sites-available/odoo.conf.bak.*
   sudo mv /etc/nginx/sites-available/odoo.conf.bak.<timestamp> /etc/nginx/sites-available/odoo.conf
   sudo nginx -t && sudo systemctl reload nginx
   ```

2. Reset `web.base.url`:
   ```bash
   sudo docker exec odoo-db psql -U odoo -d odoo -c \
     "UPDATE ir_config_parameter SET value = 'https://odoo.loodon.com' WHERE key = 'web.base.url';"
   sudo docker restart odoo-app
   ```

The original cert for `odoo.loodon.com` remains valid; certbot `--expand` adds domains, it doesn't remove existing ones.
