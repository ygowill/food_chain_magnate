# Online Local Manual Validation

## Purpose

This document defines a reliable local validation path for online mode so browser-to-browser testing no longer depends on a full build and deploy cycle.

## Default Local Topology

- Portal: `http://127.0.0.1:5173`
- Backend: `http://127.0.0.1:8000`
- Dedicated server websocket: `ws://127.0.0.1:7000`
- Shared local secrets:
  - `HMAC_SECRET=local-dev-secret`
  - `INTERNAL_API_SECRET=dev-internal-secret-change-in-production`

The helper scripts below are aligned to these defaults.

Local backend database:

- `backend/fcm_local_dev.db`
- This file is intentionally separate from `backend/fcm.db` so old manual data and old schema revisions do not pollute local online validation.

## Start Order

Open three terminals in the project root.

Terminal 1:

```bash
bash tools/run_online_local_backend.sh
```

Terminal 2:

```bash
PATH="/Applications/Godot.app/Contents/MacOS:$PATH" bash tools/run_online_local_server.sh
```

Terminal 3:

```bash
bash tools/run_online_local_portal.sh
```

Quick health checks:

```bash
curl http://127.0.0.1:8000/health
curl http://127.0.0.1:5173
```

If you want the focused automated suite before manual testing:

```bash
PATH="/Applications/Godot.app/Contents/MacOS:$PATH" bash tools/run_online_regression_suite.sh
PATH="/Applications/Godot.app/Contents/MacOS:$PATH" bash tools/run_online_session_suite.sh --group resync
```

## Browser Setup

- Open `http://127.0.0.1:5173`.
- Use two isolated browser contexts:
  - one normal profile
  - one incognito/private window
- Log in as two different users.

## Manual Checklist

### Lobby Lifecycle

1. Player A creates a public room.
2. Player B joins the room.
3. Player B actively leaves the room.
4. Refresh the room list in both browsers.

Expected:

- The old room no longer shows as full.
- No ghost room remains with `player_count=0`.
- A room without password must show `password_required=false`.

### Password Room

1. Player A creates a password room.
2. Player B enters a wrong password once.
3. Player B retries with the correct password.

Expected:

- The room is listed as a password room only when a real password was set.
- Wrong-password rejection is stable and does not poison the next correct join.
- Correct password joins successfully.

### Lobby Refresh Resume

1. Player A creates a room and waits in lobby.
2. Player B joins the room.
3. Player B refreshes the page.

Expected:

- Player B auto-resumes into the original room.
- Room list does not show the room as incorrectly full during the refresh window.
- Host remains in lobby and does not get kicked back to room selection.

### In-Game Refresh Resume

1. Start a match with two players.
2. Let both players enter the main game scene.
3. Refresh Player B.

Expected:

- Player B reconnects into the same in-progress match.
- Player B can only control their own seat.
- Player A does not eventually lose the connection because of Player B's restore flow.
- Resume spinner clears after the restore finishes.

### Disconnect And Indicators

1. Start a match.
2. Disconnect Player B by closing the tab or disabling network.
3. Observe Player A.

Expected:

- Player A sees the disconnect indicator on Player B's restaurant icon.
- If Player B reconnects during grace period, the indicator clears.
- If Player B does not return and is surrendered by the server, the surrender indicator replaces the disconnect indicator.

### Last Remaining Player

1. Start a match with at least two players.
2. Have every other player surrender.

Expected:

- The match ends immediately when only one non-forfeited player remains.
- The remaining player wins.
- Final settlement UI appears immediately on all surviving clients.

## Logs And Troubleshooting

- Dedicated server log: `.godot/LocalOnlineServer.log`
- Online regression logs:
  - `.godot/OnlineRegressionSuite.log`
  - `.godot/OnlineSessionMatrix.log`
- If the portal can create/join rooms but reconnect fails immediately, check whether backend and dedicated server use the same `HMAC_SECRET`.
- If the room list looks stale, confirm the dedicated server heartbeat is reaching `http://127.0.0.1:8000`.
