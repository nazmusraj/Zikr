# Nur Zikr Supabase backend

This directory contains the versioned PostgreSQL migrations for account profiles,
low-write progress synchronization, global leaderboards, and private group
leaderboards.

## Data model

- `profiles` — public-facing name/avatar preferences created automatically after
  Supabase Auth creates a user.
- `user_stats` — one lifetime aggregate row per user.
- `daily_progress` — one aggregate row per user, date, and zikr.
- `zikr_progress` — one lifetime aggregate row per user and zikr.
- `progress_sync_devices` — the last accepted sequence for each device, making
  retries idempotent without storing every tap.
- `groups` and `group_members` — invitation-only competition groups.

Only normal orb taps increase `ranked_count`. Manual and batch entries increase
the private/personal `total_count` but do not affect leaderboards.

## Client RPCs

- `sync_progress` — submits a batched tap/manual delta. Use one persistent UUID
  per installation and a monotonically increasing sequence number.
- `get_global_leaderboard` / `get_my_global_rank` — `daily`, `weekly`, or `all`.
- `create_group`, `join_group`, `update_group`, `leave_group`, `delete_group`.
- `get_group_leaderboard` / `get_my_group_rank` — available only to members.

All application tables have forced Row Level Security. Anonymous clients cannot
read tables or execute application RPCs. Signed-in users can directly read only
their own progress and the groups they belong to. Leaderboard RPCs deliberately
return only display name, avatar, score, position, and user ID—never email.

## Migrations

Migration filenames match the migration versions recorded by the hosted project.
Apply future schema changes as new files rather than editing migrations that have
already been deployed.

The current hosted project is:

```text
https://opdrhpyooeeafluuzdgm.supabase.co
```

Do not store database passwords, Supabase secret/service-role keys, Google client
secrets, or signing keystores in this directory or in Git.
