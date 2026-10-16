#!/usr/bin/env python3
"""
ZCC v2 — Shepherd Orchestrator (Athena's dispatcher)

Reads events from the detector queue (/opt/data/logs/zcc_v2_queue.jsonl),
builds a self-contained brief per event (contact, category, tier, license
track, conversation history, case file), then DELEGATES to Stan (the
shepherd / Sales & BD) via Hermes delegate_task so he can:
  - read the conversation (via ghl_actions.read_conversation)
  - decide the right next action in his own voice (consultative/warm)
  - call ghl_actions to send/move/note/tag/disqualify
  - update his case file (hypothesis, next move, asked/answered)

This script is the QUEUE CONSUMER only — it does NOT talk to GHL directly
(except to read context via ghl_actions), and it NEVER mutates a prospect.
All writes happen inside Stan's delegation (or are prepared as stubs).

Design:
  - One event processed per run (cron-friendly, idempotent by queue offset)
  - Each event, once handled, is marked by appending its id to a processed
    ledger, so no double-delegation across restarts.
  - In DRY_RUN, builds the brief + prints it and DOES NOT delegate.
  - Every brief embeds a Three-Department Diagnostic (Prevette overlay,
    2026-09-03): which of emotion/judgment/desire is in charge, the phase
    (open/damp_antenna/triage/commitment), jam state, and phase guidance.
    Classification is pure (reads the case file, writes nothing, never calls
    GHL); dept tags are case-file-only and non-triggering.

Usage:
  python3 zcc_orchestrator.py              # process next pending event
  ZCC_DRY_RUN=1 python3 zcc_orchestrator.py  # build brief, no delegation
"""
import json
import os
import sys
import time

QUEUE_FILE = "/opt/data/logs/zcc_v2_queue.jsonl"
PROCESSED_FILE = "/opt/data/logs/zcc_v2_processed.txt"
LOG_FILE = "/opt/data/logs/zcc_v2_orchestrator.log"

DRY_RUN = os.environ.get("ZCC_DRY_RUN") == "1"


def log(msg, level="INFO"):
    ts = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime())
    line = f"[{ts}] [{level}] {msg}"
    print(line, flush=True)
    try:
        with open(LOG_FILE, "a") as f:
            f.write(line + "\n")
    except OSError:
        pass


def load_processed():
    try:
        with open(PROCESSED_FILE) as f:
            return set(f.read().splitlines())
    except OSError:
        return set()


def mark_processed(evt_id):
    with open(PROCESSED_FILE, "a") as f:
        f.write(evt_id + "\n")


def event_keys(evt):
    """Identity keys for an event. OLD format collapsed batches where
    conversation_id was None (2026-10-15 incident: 41 lead_new events shared
    one key and 40 would have been silently dropped after the first dispatch).
    NEW format is collision-free; both are checked so legacy processed.txt
    entries (old key format) still exclude historical events."""
    q = evt.get("queued_at", "")
    old = q + (evt.get("conversation_id") or "")
    new = "|".join([
        q,
        str(evt.get("conversation_id") or ""),
        str(evt.get("contact_id") or ""),
        str(evt.get("opportunity_id") or ""),
    ])
    return old, new


def next_pending_event(processed):
    try:
        with open(QUEUE_FILE) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                evt = json.loads(line)
                old_key, new_key = event_keys(evt)
                if old_key in processed or new_key in processed:
                    continue
                return evt, new_key
    except OSError:
        return None, None
    return None, None


def build_brief(evt):
    """Assemble the self-contained handoff text for the owning specialist."""
    contact_id = evt.get("contact_id")
    # Canonical pipeline/category: detector writes 'pipeline' (canonical name).
    # Accept 'category' as fallback for backward compat with older queue records.
    category = evt.get("pipeline") or evt.get("category")
    tier = evt.get("tier")
    license_track = evt.get("license_track")
    tag = evt.get("tag") or ""

    # Eric's owner-routing rule (2026-08-24): Sales + Groups -> Stan, Recruits -> Mikayla
    specialist = "Mikayla" if category == "Recruits" else "Stan"

    # Try to read the current case file (working memory)
    sys.path.insert(0, "/opt/data/scripts")
    try:
        import ghl_actions as ga
        case = ga.read_case(contact_id)
    except Exception as e:
        case = {}
        log(f"could not read case: {e}", "WARN")

    # Three-Department Diagnostic (Prevette overlay, 2026-09-03).
    # Pure classification (reads the case, writes nothing, never touches GHL)
    # — dry-run safe by construction. Feeds the phase-guidance block below.
    dept = None
    try:
        if hasattr(ga, "classify_department"):
            dept = ga.classify_department(case, category, case.get("current_stage"))
    except Exception as e:
        dept = None
        log(f"department classification unavailable: {e}", "WARN")

    # Try to read conversation history (context for the reply)
    conv_history = []
    try:
        _ch = ga.read_conversation(evt.get("conversation_id") or evt.get("conv_id"))
        # Normalize to a safe value for the brief: a marker dict (no thread),
        # an error/dry-run dict, or a list of messages.
        if isinstance(_ch, list):
            conv_history = _ch
        elif isinstance(_ch, dict) and "__no_conversation__" in _ch:
            conv_history = [{"direction": "system", "type": "note",
                             "body": _ch.get("note", "No thread yet"), "date": ""}]
        elif isinstance(_ch, dict):
            # error / dry-run envelope — do not crash; log a single WARN
            if _ch.get("__error__"):
                conv_history = [{"direction": "note", "type": "note",
                                 "body": "(conversation read unavailable)", "date": ""}]
    except Exception as e:
        log(f"could not read conversation: {e}", "WARN")

    if specialist == "Mikayla":
        subject = "recruiting candidate (licensing track)"
    else:
        subject = "sales prospect"

    # Phase-guidance block for the owning specialist (Prevette overlay).
    # Scope = Sales + Recruits ONLY (approved 2026-09-03); Groups is skipped.
    # Case-file-only classification: the dept tag is NEVER applied in GHL and
    # triggers no workflow. DRY_RUN-gated by the outer brief flow (no sends).
    _diag = ""
    _pk = (category or "").strip().lower()
    if dept and _pk in ga.DIAGNOSTIC_PIPELINES:
        _wr = {}
        try:
            _wr = ga.wish_recovery_due(case)
        except Exception as e:
            log(f"wish-recovery calc unavailable: {e}", "WARN")
            _wr = {}
        _wr_line = _wr.get("note", "wish-recovery: no timestamp on file — follow the 24h ONE-open-question rule.")
        _session = {
            "sales": "Individual & Family B2C working session",
            "recruits": "Agency Stack Audit",
        }.get(_pk, "working session")
        _anchor = (f"booking anchor ({_pk}): {_session} — "
                   f"{ga.PIPELINE_SLOT_MIN.get(_pk, 30)} min, calendar "
                   f"{ga.PIPELINE_CALENDARS.get(_pk, 'unmapped')}"
                   f"{' (DRY_RUN — do NOT send booking links unless asked)' if DRY_RUN else ''}")
        _diag = f"""
THREE-DEPARTMENT DIAGNOSTIC (Prevette overlay — case-file only, non-triggering):
  department: {dept.get('department')}
  phase: {dept.get('phase')}   [{dept.get('stage_band')}]
  jam: {dept.get('jam')}
  dept tag (case file ONLY — never applied in GHL, triggers nothing): {dept.get('dept_tag')}
  reason: {dept.get('reason')}
  guidance: {dept.get('guidance')}
  decision tree: no ideas -> damp antenna (nurture posture, no pain-probe);
    idea then death -> judgment jam (inherited voice — name it, don't argue);
    idea survives then stalls -> desire jam (mood vs chore, book the session).
  lead-response law: post-intent reply <=5 min — 'give the idea a body'
    (concrete next step or the booking), before the feeling fades;
    wish-recovery = ONE open question within 24h ('Still feeling good about this,
    or did a question come up?') — never a re-pitch, never a second asset.
  timing status: {_wr_line}
  {_anchor}
"""
    brief = f"""You are {specialist}, shepherding a {subject} in GoHighLevel (ZCC {category} pipeline).

CONTACT
  name: {evt.get('name') or 'Unknown'}
  email: {evt.get('email') or 'Unknown'}
  contact_id: {contact_id}
  conversation_id: {evt.get('conversation_id')}
  pipeline category: {category}
  tag (whitelist): {tag or 'not-carrying-star-tag'}
  tier: {tier}{'-star' if tier else ''}
  license track (recruits): {license_track or 'n/a'}
  last message: {(evt.get('lastMessageBody') or '')[:300]}
  form top priority (their stated answer): {evt.get('top_priority') or 'not captured (no form answer / legacy row)'}
  attribution source: {(evt.get('attribution_url') or evt.get('source') or 'n/a')}

FIRST-TOUCH DIRECTION — anchor to their STATED priority, not a preset script:
  The prospect (via the FFL.Health form) told us their top priority is
  '{evt.get('top_priority') or 'not captured'}'. Lead with THAT (their real
  concern), not the product or a generic BD opener. Use the FFL Health brand
  (not ZCC — ZCC is internal). If the top priority is 'Healthcare Insurance',
  they are a CONSUMER seeking coverage — the frame is coverage/plan fit, NOT
  recruiting or 'growing your book'. Ask one question about THAT priority.

SENDER IDENTITY (CRITICAL — do not skip):
  Every outbound SMS/email to a prospect is sent from ERIC HEMATI's GHL channels
  (his phone number + eric@hemati.com). Therefore every message the prospect
  receives must be authored and signed as ERIC HEMATI, FFL Health — never as
  "{specialist}", "Stan", "Mikayla", or "ZCC". Do NOT change the tone, structure,
  or questions from what you'd normally send — keep everything consistent — but
  the message is FROM Eric ("Hi [Name], this is Eric Hemati with FFL Health…").
  YOU (as {specialist}) steer the strategy and write the copy; the copy always
  presents as Eric Hemati.

STOP OPT-OUT RULE (Eric's directive — 2026-08-26):
  • FIRST SMS to a prospect: include EXACTLY ONE STOP signature (e.g.
    "Reply STOP to opt out of texts anytime."). Never two, never a separate
    loose line like "If you don't want these texts, reply STOP" stacked on top.
  • EVERY FOLLOW-UP SMS (2nd message onward in the same thread): NO STOP
    signature at all — the single first-message opt-out covers the whole thread.
  • Keep the one STOP only on the FIRST message; subsequent messages carry the
    same tone/content but NO opt-out footer.
  • Do NOT auto-append: the send_sms tool does not add one; you write the copy,
    so YOU decide once per thread (first message only).

CASE FILE (your working memory so far)
{r'''

'''
 if case else '  (new prospect — no case yet)'}
{json.dumps(case, indent=2) if case else ''}
{_diag}
CONVERSATION HISTORY (recent)
{json.dumps(conv_history, indent=2) if conv_history else '  (none found yet)'}

YOUR JOB — be the shepherd, like a human inside sales agent:
  1. Read the conversation thread (ghl_actions.read_conversation) as needed.
  2. Decide the NEXT action: respond with a confident, consultative, warm
     tone — match the prospect's energy; lead with THEIR problem, not the product.
     Write the copy in ERIC HEMATI's voice (from Eric, FFL Health) per the SENDER
     IDENTITY rule above — never as "{specialist}/Stan/Mikayla".
     Move the pipeline stage when the conversation genuinely advances, ask the
     right qualifying question, or gracefully disqualify non-fit prospects (with
     a reason; NEVER delete).
  3. EXECUTE via the ghl_actions toolkit so the action is real in GHL + your
     case file:
       - send_sms(contact_id, text)
       - send_email(...)
       - move_stage(contact_id, opp_id, pipeline_name, stage_name)
       - add_note(contact_id, text)
       - set_tag(...) / remove_tag(...)
       - disqualify(contact_id, opp_id, pipeline_name, reason)
       - create_opportunity / find_opportunity as needed
  4. UPDATE YOUR CASE FILE at the end of your turn: hypothesis, next_move,
     asked_answered, status. (save via the ghl_actions file helpers / direct
     json write to /opt/data/zcc/cases/{contact_id}.json)
  5. Report what you did + what the prospect said + your next move.

Safety: never fabricate a message you didn't actually send. Verify real API
results before claiming success. If a move would be inappropriate (e.g. you're
not sure the prospect wants this), ask one open question instead of assuming.
"""
    return brief


def next_pending_brief():
    """Return (brief, evt, evt_id) for the next unprocessed event, else (None,None,None)."""
    processed = load_processed()
    evt, evt_id = next_pending_event(processed)
    if evt is None:
        return None, None, None
    brief = build_brief(evt)
    return brief, evt, evt_id


def process_next():
    processed = load_processed()
    evt, evt_id = next_pending_event(processed)
    if evt is None:
        log("No pending events")
        return 0

    brief = build_brief(evt)
    log(f"📋 Event: {evt.get('type')} contact={evt.get('contact_id')} cat={evt.get('category')} tier={evt.get('tier')}")

    if DRY_RUN:
        print("===== BRIEF (DRY_RUN — would delegate to Stan) =====")
        print(brief)
        print("===== END BRIEF =====")
        return 1

    print(brief)
    return 1


def main():
    if "--emit-brief" in sys.argv:
        # Print the brief for the NEXT pending event only (cron agent pulls it),
        # plus the queue offset so the agent can mark handled. No delegation here.
        brief, evt, evt_id = next_pending_brief()
        if brief is None:
            print("NO_PENDING_EVENTS")
            return 0
        print(f"EVENT_ID={evt_id}")
        print(brief)
        return 0
    if "--drain" in sys.argv:
        # process ALL pending events (for testing)
        total = 0
        while True:
            n = process_next()
            if n == 0:
                break
            total += n
        log(f"Drain complete: {total} event(s)")
    else:
        process_next()


if __name__ == "__main__":
    main()