# Deploys

Every push to `main` that passes CI deploys (`.github/workflows/ci.yml`:
`flyctl deploy --remote-only --ha=false`). The app runs one machine; deploys use
Fly's **blue-green** strategy (`[deploy] strategy = "bluegreen"` in `fly.toml`),
so there is no downtime. Before that, the machine restarted in place and the
site was down for each deploy.

## What happens

1. **Release command**: `/app/bin/migrate` runs in a temporary machine from the
   new image while the old ("blue") machine still serves. A failure stops the
   deploy with nothing changed.
2. **Green boots** beside blue. Its Oban starts at once; it gets no traffic yet.
3. **Health checks** (every 10 s, from 15 s after boot): `/health` (the endpoint
   answers; gates routing) and `/health/ready` (the app booted and the database
   answers `SELECT 1`). The deploy waits for both, up to 5 minutes; if they
   never pass, green is destroyed and blue keeps serving (CI goes red).
4. **Switch**: traffic moves to green; blue gets SIGTERM.
5. **Blue shuts down** within `kill_timeout = "60s"`: LiveView sockets reconnect
   to green, in-flight requests finish, and Oban stops taking jobs and gives
   running ones 25 s (`shutdown_grace_period`).
6. Blue is destroyed. Each deploy gets a new machine id.

## Two machines for a minute or two

| Part | During the overlap |
|---|---|
| Oban | Fine: jobs are claimed with row locks; cron runs only on the leader. |
| PubSub (summaries, sign-out disconnects) | Per machine until blue stops; pages re-read the database on reconnect. |
| `EverydayCitizen.RateLimit` | Per machine (in memory); limits are briefly doubled. |
| Sessions | Fine: signed with the shared `SECRET_KEY_BASE`. |
| Database connections | Two pools for the overlap. |

## Interrupted jobs

A job still running on blue after the 25 s grace stays `executing` in the
database. Each node records a heartbeat every 30 s (`node_heartbeats`,
`EverydayCitizen.NodeHeartbeat`); once blue has been silent for 2 minutes the
sweep releases its jobs and they run again on green (jobs are idempotent).
`Oban.Plugins.Lifeline` (2 hours) remains the backstop.

## The migration rule

Migrations run while the old code is still serving, so each must work with both
the old and the new code: add columns and tables first, start using them in a
later deploy, and drop or rename only once no running code reads them.
