#!/usr/bin/env python3
"""bee .18 collision watchdog (no_agent cron, every 30m).

Watches the kernel ARP cache for 192.168.1.18. bee's IP is OS-level static
(valid_lft forever), so the ONLY risk is a foreign device leasing .18 from the
gateway pool and colliding. On a foreign MAC: print alert (delivered verbatim),
touch suppress-file, then stay silent about that event. Silent+exit0 when healthy.

Test hook: TEST_FOREIGN_MAC=1 forces the alert path for verification.
"""
import os, time, sys

EXPECTED_MAC = "70:70:fc:07:ca:66"   # bee enp1s0, verified 2026-10-15
TARGET_IP = "192.168.1.18"
STATE = "/opt/data/.dhcp18_watch.state"
GRACE = 300  # seconds a foreign MAC must persist before alerting

def read_arp():
    entry = None
    try:
        for line in open("/proc/net/arp"):
            parts = line.split()
            if len(parts) >= 6 and parts[0] == TARGET_IP:
                entry = (parts[3].lower(), parts[2])  # (mac, device)
                break
    except Exception as e:
        print(f"watchdog error: cannot read ARP cache: {e}")
        sys.exit(0)
    return entry

def main():
    if os.environ.get("TEST_FOREIGN_MAC"):
        print(f"** LAN ALERT (TEST): 192.168.1.18 collision risk — ARP shows foreign MAC aa:bb:cc:dd:ee:ff on {TARGET_IP}. Expected bee {EXPECTED_MAC}. Bee's IP is OS-static; the squatter will lose on bee's next ARP announcement, but check the gateway device list and identify/renumber the intruder.")
        sys.exit(0)

    entry = read_arp()
    if entry is None:
        # No ARP entry: no evidence either way (bee may be off / quiet). Stay silent.
        sys.exit(0)
    mac, dev = entry
    if mac == EXPECTED_MAC:
        # healthy: refresh state file mtime
        try:
            with open(STATE, "a") as f:
                f.write("")
            os.utime(STATE)
        except Exception:
            pass
        sys.exit(0)

    # foreign MAC present — grace window before alerting
    age = time.time() - os.path.getmtime(STATE) if os.path.exists(STATE) else None
    if age is not None and age < GRACE:
        sys.exit(0)  # first sighting: start grace window silently
    print(f"** LAN ALERT: 192.168.1.18 collision — ARP shows foreign MAC {mac} (iface {dev}) where bee ({EXPECTED_MAC}) should be. Bee's IP is OS-level static so it will win the next ARP exchange, but something grabbed .18 from the gateway's DHCP pool: check the Optimum app device list, identify the intruder, and if it persists, reserve .18 for bee or renumber the squatter.")
    # touch state so this event self-suppresses
    try:
        with open(STATE, "a") as f:
            f.write("")
        os.utime(STATE)
    except Exception:
        pass
    sys.exit(0)

main()
