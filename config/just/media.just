# =============================================================================
# HOMELAB MEDIA SERVICES (JELLYFIN / GELATO / THREADFIN)
# =============================================================================

# Bulk "Create Mapping" writes one shared placeholder into x-mapping for every channel,
# causing Threadfin's XMLTV export to contain zero programmes.
# Repairs Threadfin EPG mappings, restarts the service, and verifies the XMLTV export
threadfin-fix-epg:
    #!/usr/bin/env bash
    set -euo pipefail

    SCRIPT="/var/home/eric/.local/share/hermes/scripts/threadfin_fix_xmapping.py"

    # Inside a distrobox the PATH systemctl shim can't reach the host USER bus;
    # the host binary path does (verified seam). Outside, plain systemctl --user.
    if [ -f /run/.containerenv ]; then
      SC="/usr/bin/systemctl --user"
    else
      SC="systemctl --user"
    fi

    if [ ! -f "$SCRIPT" ]; then
      echo "❌ Fix script not found at $SCRIPT (restore the Athena backup first)" >&2
      exit 1
    fi

    echo "[ 1/4 ] Stopping threadfin.service ..."
    $SC stop threadfin.service

    echo "[ 2/4 ] Repairing x-mapping entries ..."
    python3 "$SCRIPT"

    echo "[ 3/4 ] Starting threadfin.service ..."
    $SC start threadfin.service

    echo "[ 4/4 ] Waiting for EPG export rebuild ..."
    sleep 20
    EXPORT="$HOME/.local/share/threadfin/conf/data/threadfin.xml"
    PROGS=$(grep -c '<programme ' "$EXPORT" 2>/dev/null || true)
    PROGS=${PROGS:-0}
    echo "✅ Done. Export programmes: $PROGS"
    echo "   Previous mapping DB backed up alongside it (xepg.json.bak-*)"

# Gelato: enable new catalogs & start collection import sync (use --list to inspect)
gelato-sync *args:
    python3 ${HOME}/.hermes/scripts/gelato_sync.py {{args}}

# Gelato: show enable state of every catalog
gelato-list:
    python3 ${HOME}/.hermes/scripts/gelato_sync.py --list

# Stops jellyfin for the edit (JF overwrites plugin config on shutdown-save).
# Gelato: prune legacy catalog blocks from Gelato.xml (dry-run first!)
gelato-prune *args:
    systemctl --user stop jellyfin.service
    python3 ${HOME}/.hermes/scripts/gelato_prune_legacy.py {{args}}
    systemctl --user start jellyfin.service

# Gelato: refresh the cached live-catalog ID list (run while jellyfin is up)
gelato-prune-ids:
    python3 ${HOME}/.hermes/scripts/gelato_prune_legacy.py --refresh-cache-only

# Prunes legacy Gelato.xml blocks FIRST, otherwise re-keyed ghost catalogs
# resurrect duplicate collections on every rebuild.
# Gelato: wipe ALL collections and rebuild from enabled catalogs (nuclear reset)
gelato-reset:
    just --justfile "$HOME/.justfile" media gelato-prune
    python3 ${HOME}/.hermes/scripts/gelato_sync.py --reset

# Jellyfin: restart the user service (busts Gelato's cached manifest)
jf-restart:
    systemctl --user restart jellyfin.service

# Jellyfin: trigger Gelato collection import sync only (no enabling)
gelato-sync-run:
    python3 ${HOME}/.hermes/scripts/gelato_sync.py --sync-only
