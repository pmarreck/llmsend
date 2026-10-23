# Persistent inbox reminders

For immediate agent-to-agent delivery through exposed Codex tools, see
[Native Codex delivery](native-codex.md). This document describes the separate
scheduled socket adapter, not the interactive tool workflow. A tool-based live
success does not establish timer deployment or every project's socket coverage.

`llmsend-inbox-remind --config PRIVATE_JSON` performs one bounded scan of
explicitly configured projects. A single persistent timer invokes it once a
minute; each project/native session has a default reminder interval of 3600
seconds. Existing immediate hook and monitor notifications remain enabled.
The timer works while the recipient is idle and must survive reboot.

```json
{
  "version": 1,
  "state_dir": "/absolute/private/reminder-state",
  "interval_seconds": 3600,
  "projects": [
    {
      "project": "/absolute/project",
      "thread": "00000000-0000-0000-0000-000000000001",
      "socket": "/absolute/existing/app-server-control.sock"
    }
  ]
}
```

Use the actual loaded native thread UUID and canonical project directory.
Keep configuration outside the repository and Nix store, owned by the service
operator with mode 0600. The state directory must be owned with mode 0700;
its parent must exist. State records are 0600. Keep inboxes outside public
version control. Configuration has at most 64 distinct canonical projects;
an inbox has at most 4096 direct entries. Exceeding a limit fails visibly.

The package attribute is `packages.<system>.inboxRemind`; `default` includes
it. LuaJIT, LuaFileSystem, lua-cjson, coreutils and Websocat are packaged
runtime dependencies. The tested deployment is a Linux user service. The
portable adapters also contain macOS support; native macOS execution has not
been verified for this feature.

## Delivery and status

The current scheduled adapter connects to an existing Codex daemon over an
owned Unix socket. It uses WebSocket framing, initializes that connection,
checks `thread/loaded/list`, and verifies the exact UUID, cwd and idle state
through `thread/read`. It rechecks before `turn/start`. It never starts or
resumes a thread, starts a daemon, changes approval policy, or edits terminal
input. Active, absent, mismatched, unsupported or offline recipients defer.
The installed Codex 0.162.1 schema and a live read-only probe established this
protocol. Other backends retain their existing hooks/monitors; the scheduled
native adapter currently supports Codex only.

`--dry-run` reads state and checks native availability without writing state
or submitting a turn. Each JSON project result reports pending count, status,
last delivery outcome, any native turn receipt, and next due time. Exit 0
means the scan completed with empty/waiting/delivered/dry-run results; exit 3
means at least one deferred, failed or unconfirmed delivery; exit 1 is a
configuration or I/O failure. `delivered` means the native API accepted a turn.
Only recipient readback or acknowledgement establishes consumption.

A normal scan has a 50-second transport budget, each connection at most five
seconds, bounded response sizes, and bounded native-registry pagination.
Unchanged waiting state is not rewritten each minute. State contains filenames,
file identities, deadlines and delivery receipts, never note bodies or drafts.

## Timing and recovery

The first observed pending note arms its interval. New notes do not postpone
older deadlines. One due project produces one aggregate reminder naming the
original notes. Direct visible ordinary `.md` files qualify, including legacy
names; hidden files, symlink entries, special files and nested/processed
contents do not. A final scan rejects notes removed or replaced during
recipient verification. The command never creates reminder-note files or
deletes inbox notes.

A per-project/native-session OS lock covers read, checkpoint, delivery and
receipt. Atomic checkpoints are synced before the external effect. Known
failures retry after 60 seconds, at most three attempts before waiting another
interval; retries preserve the logical operation ID. A crash or ambiguous
response retains an unconfirmed attempt and waits until the next interval.
That later hourly reminder has a new identity and may repeat an earlier
reminder that was delivered without a confirmed response. It cannot repeat
unrelated business effects. A fully completed immediate rerun submits nothing.

Monotonic elapsed time is used within a boot, including process restarts.
Across boots, elapsed wall time is clamped at zero on rollback; rollback may
delay the next reminder but cannot trigger a burst. Removing all observed
notes clears their obligation state. A later recreated file starts a new
interval. Deletion and recreation entirely between scans with reused inode
identity cannot be distinguished from an unchanged file.

Recipients act on notes, transfer unfinished authorized work into an organized
PLAN/context with an owner, blocker and next action, and report genuine owner
blockers to the coordinator. They trash envelopes only after completion or
that durable transfer. Reading alone does not discharge an obligation.

## Draft fallback boundary

The owner authorized an advisory fallback after 60 seconds without edits.
That permission requires an exact full editor snapshot, including multiline
Unicode content and selection/cursor state, private durable recovery before
mutation, monotonic stability and an immediate identity/content/geometry
recheck. Restoration must wait for an idle unchanged empty composer and must
never press Enter or overwrite new typing. Recovery failures retain private
0600 data and notify the owner without publishing the draft.

The current Herdr API provides rendered screen captures, not that exact editor
snapshot. Draft displacement is therefore unsupported and remains disabled,
including at 59, 60 and 61 seconds. Native reminders bypass the composer.
No screen-derived text is a substitute for an exact editor buffer, and 60
seconds of inactivity does not eliminate the human-input race.

## Deployment verification

Declare one user oneshot service and one persistent minutely timer. Use
`UMask=0077`, `TimeoutStartSec=90` and `SuccessExitStatus=3` while retaining JSON
outcomes for operator inspection. The service needs access to the configured
inboxes, private state and existing AF_UNIX socket. It needs no interactive
Herdr environment variables. Provisioning and activation are separate from
building the package. Verify one approved idle recipient's acknowledgement,
then timer health and the recorded next due. A staged unit is not a running
reminder service. Do not restart shared agent or mail daemons for this job.
