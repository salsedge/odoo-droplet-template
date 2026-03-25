# Add portal.loodon.com Domain

**Date:** 2026-03-25
**Status:** Ready to execute
**Requested by:** UBOP project (ubop-lite)
**Prerequisite:** DNS A record for `portal.loodon.com` -> `45.55.164.120` (already added, propagating)

---

## Summary

Add `portal.loodon.com` as the primary domain for the Odoo instance. Keep `odoo.loodon.com` working as an alias that redirects to the primary domain.

## Changes Required

### 1. SSL Certificate — Expand to Cover Both Domains

Current cert covers `odoo.loodon.com` only. Expand it to include `portal.loodon.com`.

```bash
ssh -p 9292 deploy@45.55.164.120
```

```bash
# Expand the Let's Encrypt certificate to cover both domains
sudo certbot --nginx -d portal.loodon.com -d odoo.loodon.com --expand
```

Certbot will update the Nginx config automatically if using the `--nginx` plugin. If it doesn't, or if the cert was originally obtained with `certonly`, apply the Nginx changes manually (see step 2).

**Verify:**
```bash
sudo certbot certificates
```

Expected output should show both domains on the same certificate.

### 2. Nginx — Update Server Blocks

Two server blocks needed: one for the primary domain serving Odoo, one for the alias redirecting.

**Edit the Nginx site config:**
```bash
sudo nano /etc/nginx/sites-available/odoo
```

**Primary server block** — update `server_name` to `portal.loodon.com`:

```nginx
server {
    listen 443 ssl http2;
    server_name portal.loodon.com;

    # SSL cert paths (updated by certbot)
    ssl_certificate /etc/letsencrypt/live/portal.loodon.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/portal.loodon.com/privkey.pem;

    # ... rest of existing config (proxy_pass, headers, etc.) unchanged ...
}
```

**Alias redirect block** — add a new block that 301 redirects `odoo.loodon.com` to `portal.loodon.com`:

```nginx
server {
    listen 443 ssl http2;
    server_name odoo.loodon.com;

    ssl_certificate /etc/letsencrypt/live/portal.loodon.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/portal.loodon.com/privkey.pem;

    return 301 https://portal.loodon.com$request_uri;
}
```

**HTTP redirect blocks** — ensure both domains redirect HTTP to HTTPS (certbot usually handles this, but verify):

```nginx
server {
    listen 80;
    server_name portal.loodon.com odoo.loodon.com;
    return 301 https://portal.loodon.com$request_uri;
}
```

**Test and reload:**
```bash
sudo nginx -t && sudo systemctl reload nginx
```

### 3. Odoo — Update web.base.url

The `web.base.url` system parameter controls URLs in emails, portal links, and shared documents.

**Option A: Via Odoo UI**
1. Log in to `https://portal.loodon.com/web`
2. Settings -> Technical -> Parameters -> System Parameters
3. Find `web.base.url`
4. Change value to `https://portal.loodon.com`
5. Save

**Option B: Via psql**
```bash
sudo docker exec -it odoo-db psql -U <POSTGRES_USER> -d <POSTGRES_DB> -c \
  "UPDATE ir_config_parameter SET value = 'https://portal.loodon.com' WHERE key = 'web.base.url';"
```

Then restart Odoo to pick up the change:
```bash
sudo docker restart odoo-app
```

### 4. HSTS — Verify

After the domain change, verify HSTS is working on the new primary domain:

```bash
curl -sI https://portal.loodon.com | grep -i strict
```

Expected: `Strict-Transport-Security: max-age=31536000`

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

If something goes wrong:

1. Revert Nginx config to the original single-domain setup
2. `sudo nginx -t && sudo systemctl reload nginx`
3. Reset `web.base.url` to `https://odoo.loodon.com`
4. `sudo docker restart odoo-app`

The original cert for `odoo.loodon.com` remains valid; certbot `--expand` adds domains, it doesn't remove existing ones.
