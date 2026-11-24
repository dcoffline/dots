#!/usr/bin/env python3
"""Applies flicker-prevention flags (--disable-gpu, Wayland, Vulkan disable)
to Electron & Chromium apps (Flatpaks, Local State, desktop entries, Gearlever, AppImages).
"""
import configparser
import glob
import json
import os
import sys

target = (sys.argv[1] if len(sys.argv) > 1 else "").strip().lower()
home = os.path.expanduser("~")

GREEN = "\033[32m"
YELLOW = "\033[33m"
CYAN = "\033[36m"
BOLD = "\033[1m"
DIM = "\033[2m"
RESET = "\033[0m"

print(f"\n{BOLD}{CYAN}================================================================{RESET}")
print(f"{BOLD}{CYAN}         GPU FLICKER FIX PROTOCOL (LEGACY RADEON / WAYLAND)    {RESET}")
print(f"{BOLD}{CYAN}================================================================{RESET}")
if target:
    print(f"Target filter: {BOLD}{target}{RESET}\n")
else:
    print("Scanning all installed Flatpaks, AppImages, and Electron configurations...\n")

changes = 0
flags_list = ["--ozone-platform=wayland", "--disable-gpu", "--disable-features=Vulkan"]
flags_block = "\n".join(flags_list) + "\n"

# 1. Flatpaks
flatpak_map = {
    "com.google.Chrome": ["chrome-flags.conf"],
    "com.brave.Browser": ["brave-flags.conf"],
    "com.discordapp.Discord": ["discord-flags.conf"],
    "com.bitwarden.desktop": ["bitwarden-flags.conf", "electron-flags.conf"],
    "com.slack.Slack": ["slack-flags.conf", "electron-flags.conf"],
    "com.spotify.Client": ["spotify-flags.conf"],
    "md.obsidian.Obsidian": ["obsidian-flags.conf", "electron-flags.conf"],
    "im.riot.Riot": ["element-flags.conf"],
    "com.visualstudio.code": ["code-flags.conf", "electron-flags.conf"],
    "com.vscodium.codium": ["codium-flags.conf", "electron-flags.conf"],
}

var_app = os.path.join(home, ".var/app")
if os.path.isdir(var_app):
    for app_id in sorted(os.listdir(var_app)):
        if target and target not in app_id.lower():
            continue
        cfg_dir = os.path.join(var_app, app_id, "config")
        if not os.path.isdir(cfg_dir):
            continue

        flag_files = flatpak_map.get(app_id, [])
        if not flag_files and any(
            k in app_id.lower()
            for k in ["electron", "chrome", "brave", "discord", "slack", "matrix", "chat"]
        ):
            flag_files = ["electron-flags.conf"]

        for f_name in flag_files:
            f_path = os.path.join(cfg_dir, f_name)
            needs_write = True
            if os.path.isfile(f_path):
                try:
                    with open(f_path, "r") as fp:
                        cur = fp.read()
                    if "--disable-gpu" in cur and "--disable-features=Vulkan" in cur:
                        needs_write = False
                except Exception:
                    pass
            if needs_write:
                try:
                    with open(f_path, "w") as fp:
                        fp.write(flags_block)
                    print(f" {GREEN}✓{RESET} Flatpak flag: {BOLD}{app_id}{RESET} -> {f_name}")
                    changes += 1
                except Exception as e:
                    print(f" {YELLOW}!{RESET} Error writing {f_path}: {e}")

# 2. Local State hardware acceleration disabled
ls_patterns = [
    os.path.join(home, ".config/*/Local State"),
    os.path.join(home, ".var/app/*/config/*/Local State"),
]
for pattern in ls_patterns:
    for ls_path in glob.glob(pattern):
        if target and target not in ls_path.lower():
            continue
        try:
            with open(ls_path, "r") as fp:
                data = json.load(fp)
            if not isinstance(data, dict):
                continue
            ham = data.get("hardware_acceleration_mode")
            if not isinstance(ham, dict) or ham.get("enabled") is not False:
                data["hardware_acceleration_mode"] = {"enabled": False}
                with open(ls_path, "w") as fp:
                    json.dump(data, fp)
                rel = os.path.relpath(ls_path, home)
                print(f" {GREEN}✓{RESET} Local State disabled GPU: {DIM}~/{rel}{RESET}")
                changes += 1
        except Exception:
            pass

# 3. Desktop files (~/.local/share/applications)
apps_dir = os.path.join(home, ".local/share/applications")
if os.path.isdir(apps_dir):
    for df in sorted(glob.glob(os.path.join(apps_dir, "*.desktop"))):
        base = os.path.basename(df)
        if target and target not in base.lower():
            continue
        try:
            with open(df, "r") as fp:
                lines = fp.readlines()
            modified = False
            new_lines = []
            for line in lines:
                if line.startswith("Exec="):
                    val = line.strip()[5:]
                    is_candidate = ".appimage" in val.lower() or (
                        target and target in base.lower()
                    )
                    if is_candidate:
                        parts = val.split()
                        if parts:
                            exec_part = parts[0]
                            args = parts[1:]
                            for req in flags_list:
                                if req not in args:
                                    inserted = False
                                    for idx, a in enumerate(args):
                                        if a.startswith("%"):
                                            args.insert(idx, req)
                                            inserted = True
                                            break
                                    if not inserted:
                                        args.append(req)
                                    modified = True
                            val = f"{exec_part} " + " ".join(args)
                            line = f"Exec={val}\n"
                new_lines.append(line)
            if modified:
                with open(df, "w") as fp:
                    fp.writelines(new_lines)
                print(f" {GREEN}✓{RESET} Desktop launcher: {BOLD}{base}{RESET}")
                changes += 1
        except Exception as e:
            print(f" {YELLOW}!{RESET} Error modifying {base}: {e}")

# 4. Gearlever persistent configuration
gl_conf = os.path.join(home, ".var/app/it.mijorus.gearlever/config/gearlever.conf")
if os.path.isfile(gl_conf):
    try:
        cp = configparser.ConfigParser(interpolation=None)
        cp.read(gl_conf)
        gl_modified = False
        for sec in cp.sections():
            if sec.startswith("app."):
                app_name = cp.get(sec, "name", fallback="")
                if target and target not in app_name.lower() and target not in sec.lower():
                    continue
                args = cp.get(sec, "default_exec_arguments", fallback="")
                arg_list = args.split()
                for req in flags_list:
                    if req not in arg_list:
                        inserted = False
                        for idx, a in enumerate(arg_list):
                            if a.startswith("%"):
                                arg_list.insert(idx, req)
                                inserted = True
                                break
                        if not inserted:
                            arg_list.append(req)
                        gl_modified = True
                cp.set(sec, "default_exec_arguments", " ".join(arg_list))
        if gl_modified:
            with open(gl_conf, "w") as fp:
                cp.write(fp)
            print(f" {GREEN}✓{RESET} Gearlever persistent AppImage config updated")
            changes += 1
    except Exception as e:
        print(f" {YELLOW}!{RESET} Error updating Gearlever config: {e}")

# 5. Local wrappers (~/.local/bin)
appimages = glob.glob(os.path.join(home, "Applications/*.appimage")) + glob.glob(
    os.path.join(home, "Applications/*.AppImage")
)
for ai in appimages:
    ai_name = os.path.splitext(os.path.basename(ai))[0].lower()
    if target and target not in ai_name:
        continue
    wrapper = os.path.join(home, ".local/bin", ai_name)
    wrapper_content = f'#!/bin/bash\nexec {ai} --no-sandbox --ozone-platform=wayland --disable-gpu --disable-features=Vulkan "$@"\n'
    if not os.path.exists(wrapper):
        try:
            os.makedirs(os.path.dirname(wrapper), exist_ok=True)
            with open(wrapper, "w") as fp:
                fp.write(wrapper_content)
            os.chmod(wrapper, 0o755)
            print(f" {GREEN}✓{RESET} Created CLI wrapper: {BOLD}~/.local/bin/{ai_name}{RESET}")
            changes += 1
        except Exception:
            pass

print()
if changes > 0:
    print(f"{GREEN}{BOLD}✅ Applied {changes} flicker-prevention adjustment(s)!{RESET}")
    print(
        f"{YELLOW}💡 Note:{RESET} If an affected application is currently running, quit and reopen it for changes to take effect.\n"
    )
else:
    print(f"{GREEN}{BOLD}✨ All detected applications are already properly configured!{RESET}\n")
