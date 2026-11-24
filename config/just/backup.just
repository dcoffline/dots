# =============================================================================
# BACKUPS & DISASTER RECOVERY
# =============================================================================

# Backs up Nextcloud database, config, and Quadlets (keeps last 4 days)
nextcloud:
    #!/usr/bin/env bash
    set -euo pipefail

    # Source secrets if available to get MYSQL_ROOT_PASSWORD
    if [ -f "$HOME/.secrets" ]; then
      source "$HOME/.secrets"
      source "$HOME/.local/share/nextcloud-db/.env" 2>/dev/null || true
    fi

    TARGET_DIR="$HOME/.mnt/10T/Backups/nextcloud"
    BACKUP_DIR="$TARGET_DIR/nextcloud_$(date +%Y%m%d_%H%M%S)"

    echo "Starting Nextcloud backup to $TARGET_DIR..."
    mkdir -p "$BACKUP_DIR"

    # 1. Dump the database (MariaDB)
    echo "Dumping MariaDB database..."
    if [ -n "${MYSQL_ROOT_PASSWORD:-}" ]; then
      podman exec -i nextcloud-db mariadb-dump -u root -p"$MYSQL_ROOT_PASSWORD" nextcloud > "$BACKUP_DIR/db_dump.sql"
    elif [ -n "${MYSQL_PASSWORD:-}" ]; then
      podman exec -i nextcloud-db mariadb-dump -u eric -p"$MYSQL_PASSWORD" nextcloud > "$BACKUP_DIR/db_dump.sql"
    else
      echo "Error: No database password found in environment or ~/.secrets" >&2
      exit 1
    fi

    # 2. Backup Nextcloud config directory
    echo "Copying config folder..."
    if [ -d "$HOME/.local/share/nextcloud/config" ]; then
      podman unshare tar -cf - -C "$HOME/.local/share/nextcloud" config | tar -xf - -C "$BACKUP_DIR"
      chmod -R u+rw "$BACKUP_DIR/config"
    else
      echo "Warning: Nextcloud config directory not found at ~/.local/share/nextcloud/config" >&2
    fi

    # 3. Backup Quadlet definition files
    echo "Copying Quadlet files..."
    mkdir -p "$BACKUP_DIR/quadlets"
    cp -r "$HOME/.config/containers/systemd/"* "$BACKUP_DIR/quadlets/" 2>/dev/null || true

    # 4. Retention: Delete backups older than 4 days
    echo "Cleaning up old backups (keeping last 4 days)..."
    find "$TARGET_DIR" -maxdepth 1 -type d -name "nextcloud_*" -mtime +3 -exec rm -rf {} \;

    echo "Backup complete!"

# Backs up all dev projects, Hermes state, Quadlets, Systemd units, Gemini & Secrets (keeps 7)
[no-cd]
athena target_dir="$HOME/.mnt/10T/Backups/Athena":
    #!/usr/bin/env bash
    exec bash "$HOME/.config/just/lib/backup-athena.sh" "{{target_dir}}"

# Restores all dev projects, Hermes state, Quadlets, Systemd units, Gemini & Secrets
[no-cd]
restore-athena backup_path="":
    #!/usr/bin/env bash
    exec bash "$HOME/.config/just/lib/restore-athena.sh" "{{backup_path}}"

# Backs up Immich (Postgres DB dump + hardlink-incremental library sync, keeps 3)
[no-cd]
immich target_dir="$HOME/.mnt/10T/Backups/immich":
    #!/usr/bin/env bash
    set -euo pipefail
    source "$HOME/.config/just/lib/common.sh"

    TARGET_DIR="{{target_dir}}"
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    BACKUP_DIR="$TARGET_DIR/immich_$TIMESTAMP"
    LATEST_LINK="$TARGET_DIR/latest"
    RETENTION_COUNT=3

    echo "================================================================"
    echo " Starting Immich Backup Protocol"
    echo " Destination: $BACKUP_DIR"
    echo "================================================================"

    mkdir -p "$BACKUP_DIR"

    # 1. Postgres DB dump (logical, restorable into the same image)
    echo "[ 1/3 ] Dumping Immich Postgres database..."
    podman exec immich-db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$BACKUP_DIR/immich_db.sql"
    echo "  ✓ DB dumped ($(du -h "$BACKUP_DIR/immich_db.sql" | cut -f1))"

    # 2. Photos/videos upload library — hardlink-incremental rsync
    echo "[ 2/3 ] Rsync'ing upload library (--link-dest incremental)..."
    PREV=""
    if [ -d "$LATEST_LINK" ]; then
      PREV="--link-dest=$LATEST_LINK/library"
    fi
    rsync -a --delete $PREV \
      --exclude='/encoded-video' --exclude='/library' --exclude='/backups' \
      "$HOME/.mnt/2T/immich/" "$BACKUP_DIR/library/"
    for sub in encoded-video library backups; do
      SUB_PREV=""
      if [ -d "$LATEST_LINK/library/$sub" ]; then
        SUB_PREV="--link-dest=$LATEST_LINK/library/$sub"
      fi
      rsync -a --delete $SUB_PREV "$HOME/.mnt/10T/immich/$sub/" "$BACKUP_DIR/library/$sub/"
    done
    echo "  ✓ Library synced."

    # 3. Thumbs/profile dir if present
    echo "[ 3/3 ] Rsync'ing thumbs..."
    if [ -d "$HOME/.local/share/immich/thumbs" ]; then
      rsync -a --delete $PREV "$HOME/.local/share/immich/thumbs/" "$BACKUP_DIR/thumbs/"
      echo "  ✓ Thumbs synced."
    else
      echo "  (no thumbs dir — skipping)"
    fi

    # Manifest
    cat > "$BACKUP_DIR/manifest.json" <<JSON
    {
      "timestamp": "$TIMESTAMP",
      "db_dump": true,
      "library_source": "$HOME/.mnt/2T/immich"
    }
    JSON

    ln -sfn "$BACKUP_DIR" "$LATEST_LINK"

    # Retention: keep newest N snapshots
    prune_old_backups "$TARGET_DIR" "immich_" "$RETENTION_COUNT" >/dev/null

    echo "✅ Immich backup complete: $BACKUP_DIR"

# Backs up Honcho (Hermes memory DB — pg_dump, keeps 7)
[no-cd]
honcho target_dir="$HOME/.mnt/10T/Backups/honcho":
    #!/usr/bin/env bash
    set -euo pipefail
    source "$HOME/.config/just/lib/common.sh"

    TARGET_DIR="{{target_dir}}"
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    BACKUP_DIR="$TARGET_DIR/honcho_$TIMESTAMP"
    RETENTION_COUNT=7

    echo "================================================================"
    echo " Starting Honcho Backup Protocol"
    echo " Destination: $BACKUP_DIR"
    echo "================================================================"

    mkdir -p "$BACKUP_DIR"

    echo "[ 1/2 ] Dumping Honcho Postgres database..."
    podman exec honcho-db sh -c 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB"' > "$BACKUP_DIR/honcho_db.sql"
    echo "  ✓ DB dumped ($(du -h "$BACKUP_DIR/honcho_db.sql" | cut -f1))"

    echo "[ 2/2 ] Copying app data dir (if any)..."
    if [ -d "$HOME/.local/share/honcho/data" ] && [ -n "$(ls -A "$HOME/.local/share/honcho/data" 2>/dev/null)" ]; then
      rsync -a "$HOME/.local/share/honcho/data/" "$BACKUP_DIR/data/"
      echo "  ✓ App data copied."
    else
      echo "  (app data empty — DB is the state)"
    fi

    cat > "$BACKUP_DIR/manifest.json" <<JSON
    {
      "timestamp": "$TIMESTAMP",
      "db_dump": true,
      "retention_count": $RETENTION_COUNT
    }
    JSON

    prune_old_backups "$TARGET_DIR" "honcho_" "$RETENTION_COUNT" >/dev/null

    echo "✅ Honcho backup complete: $BACKUP_DIR"

# Backs up per-service container data not covered by other recipes (keeps 7; skips Kiwix)
[no-cd]
apps target_dir="$HOME/.mnt/10T/Backups/apps":
    #!/usr/bin/env bash
    set -euo pipefail
    source "$HOME/.config/just/lib/common.sh"

    TARGET_DIR="{{target_dir}}"
    TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
    BACKUP_DIR="$TARGET_DIR/apps_$TIMESTAMP"
    RETENTION_COUNT=7
    SHARE="$HOME/.local/share"

    echo "================================================================"
    echo " Starting Apps Backup Protocol"
    echo " Destination: $BACKUP_DIR"
    echo "================================================================"

    mkdir -p "$BACKUP_DIR"

    # --- Vaultwarden (passwords - highest value) ---
    echo "[1/7] Vaultwarden..."
    mkdir -p "$BACKUP_DIR/vaultwarden"
    rsync -a --exclude 'cache' "$SHARE/vaultwarden/" "$BACKUP_DIR/vaultwarden/"

    # --- Paperless (data + media; uid-mapped files, tar via podman unshare) ---
    echo "[2/7] Paperless..."
    mkdir -p "$BACKUP_DIR/paperless"
    podman unshare tar --exclude='data/index' --exclude='data/llm_index' -cf - -C "$SHARE/paperless" data media \
      | tar -xf - -C "$BACKUP_DIR/paperless"

    # --- Actual Budget ---
    echo "[3/7] Actual Budget..."
    mkdir -p "$BACKUP_DIR/actualbudget"
    rsync -a "$SHARE/actualbudget/" "$BACKUP_DIR/actualbudget/"

    # --- Homebox ---
    echo "[4/7] Homebox..."
    mkdir -p "$BACKUP_DIR/homebox"
    rsync -a "$SHARE/homebox/" "$BACKUP_DIR/homebox/"

    # --- Shlink (MariaDB dump via container) ---
    echo "[5/7] Shlink DB..."
    mkdir -p "$BACKUP_DIR/shlink"
    if podman exec shlink-db sh -c 'mariadb-dump -uroot -p"$MYSQL_ROOT_PASSWORD" --all-databases 2>/dev/null' > "$BACKUP_DIR/shlink/shlink_db.sql" 2>/dev/null; then
      echo "  ✓ shlink db dumped"
    else
      echo "  ⚠️ shlink dump failed"
    fi

    # --- Open WebUI (config/data, no cache) ---
    echo "[6/7] Open WebUI..."
    mkdir -p "$BACKUP_DIR/open-webui"
    rsync -a --exclude 'cache' "$SHARE/open-webui/" "$BACKUP_DIR/open-webui/"

    # --- AIOMetadata / AIOStreams / Vane (small app states) ---
    echo "[7/7] AIOMetadata / AIOStreams / Vane..."
    # Skip any app whose local dir is absent (aiometadata retired 2026-11-17).
    for app in aiometadata aiostreams vane; do
      if [ -d "$SHARE/$app" ]; then
        mkdir -p "$BACKUP_DIR/$app"
        rsync -a --exclude 'cache' "$SHARE/$app/" "$BACKUP_DIR/$app/"
      else
        echo "  - $app: no local dir, skipping"
      fi
    done

    printf '{"timestamp": "%s", "retention_count": %d, "kiwix": "skipped per Eric 2026-11-13"}\n' "$TIMESTAMP" "$RETENTION_COUNT" > "$BACKUP_DIR/manifest.json"

    prune_old_backups "$TARGET_DIR" "apps_" "$RETENTION_COUNT" >/dev/null

    echo "✅ Apps backup complete: $BACKUP_DIR"
