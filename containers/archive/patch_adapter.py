#!/usr/bin/env python3
"""Patch DiscordAdapter in hermes to resolve forum threads defensively."""
import sys

path = "/opt/hermes/plugins/platforms/discord/adapter.py"
with open(path, "r", encoding="utf-8") as f:
    content = f.read()

target = """            # Forum channels reject channel.send() \u2014 create a thread post instead.
            if self._is_forum_parent(channel):
                result = await self._send_to_forum(channel, content)"""

replacement = """            # Forum channels reject channel.send() \u2014 create a thread post instead.
            if self._is_forum_parent(channel):
                target_thread_id = (
                    (metadata or {}).get("thread_id")
                    or reply_to
                    or (metadata or {}).get("reply_to_message_id")
                )
                resolved_thread = None
                if target_thread_id:
                    try:
                        cand = self._client.get_channel(int(target_thread_id))
                        if not cand:
                            try:
                                cand = await self._client.fetch_channel(int(target_thread_id))
                            except Exception:
                                cand = None
                        if cand and isinstance(cand, discord.Thread):
                            resolved_thread = cand
                    except Exception as exc:
                        logger.debug("[Discord] Could not resolve forum thread from %s: %s", target_thread_id, exc)
                if resolved_thread:
                    channel = resolved_thread

            if self._is_forum_parent(channel):
                result = await self._send_to_forum(channel, content)"""

if target in content:
    with open(path, "w", encoding="utf-8") as f:
        f.write(content.replace(target, replacement, 1))
    print("Successfully patched adapter.py!")
elif replacement in content:
    print("adapter.py already contains patch.")
else:
    print("Error: Target pattern not found in adapter.py", file=sys.stderr)
    sys.exit(1)
