# BedrockConnect + MCXboxBroadcast Pterodactyl Egg

A production-grade, low-maintenance [Pterodactyl](https://pterodactyl.io/) and [Pelican Panel](https://pelican.rocks/) server egg combining **[BedrockConnect](https://github.com/Pugmatt/BedrockConnect)** and **[MCXboxBroadcast](https://github.com/MCXboxBroadcast/Broadcaster)** in a single container.

This setup allows Minecraft Bedrock Edition players on consoles (**Xbox One / Series X|S, PlayStation 4/5, and Nintendo Switch**) as well as mobile/Windows to join custom Bedrock or Java/Geyser servers directly from their in-game **"Friends"** tab without requiring DNS workarounds, home router modifications, or external client apps.

---

## Architecture Overview

```
                                +---------------------------------------------+
                                |             Pterodactyl Panel               |
                                |         (Container: yolks:java_21)          |
                                |                                             |
                                |  +---------------------------------------+  |
                                |  |         start.sh (Supervisor)         |  |
                                |  |  * Auto-update daemon                 |  |
                                |  |  * Zero-rate-limit release polling    |  |
                                |  |  * Crash detection & auto-healing     |  |
                                |  |  * Clean SIGTERM signal forwarding    |  |
                                |  +----------+-------------------+--------+  |
                                |             |                   |           |
+--------------------------+    |             v                   v           |
|  Xbox Live Friends List  |<---|--->  [broadcaster/]       [bedrockconnect/] |
|  (Player sees Broadcast) |    |      MCXboxBroadcast      BedrockConnect    |
+------------+-------------+    |      Standalone           (Port: UDP 19132) |
             |                  |             |                   ^           |
             | 1. Player joins via NetherNet  |                   |           |
             +--------------------------------+                   |           |
             |                                                    |           |
             | 2. MCXboxBroadcast sends TransferPacket -----------+           |
             v    (Directs client to BedrockConnect IP & Port)                |
+--------------------------+                                                  |
| Bedrock Client UI        | <------------------------------------------------+
| (Custom Server List GUI) |
+--------------------------+
```

1. **Broadcaster**: Logs in via a dedicated Microsoft account and advertises an active Minecraft game over Xbox Live to friends.
2. **Transfer**: When a friend clicks "Join" in Minecraft, MCXboxBroadcast performs the NetherNet handshake and immediately sends a `TransferPacket` redirecting their connection to BedrockConnect.
3. **BedrockConnect GUI**: The client connects to BedrockConnect and is greeted with an interactive in-game menu listing your configured custom servers or allowing them to enter any custom server address.

---

## Key Features

- **Autonomous Background Auto-Updater**: Periodically polls GitHub for new releases of BedrockConnect and MCXboxBroadcast without needing panel intervention.
- **Zero Rate-Limit Polling**: Inspects HTTP release redirect headers instead of REST API endpoints, bypassing GitHub's 60 req/hour unauthenticated rate limits.
- **Integrity Validation**: Verifies binary size and ZIP/JAR header signatures prior to replacing running files, preventing corrupted downloads or network dropouts from breaking the server.
- **Graceful In-Container Restarts**: Safely stops and restarts child processes when updates are found without causing container termination loops.
- **Process Watchdog**: Automatically detects if either BedrockConnect or MCXboxBroadcast crashes and relaunches them with backoff protection.
- **File-First Configuration**: Keeps panel variables lean. All service settings (server lists, public IP, friend sync, MOTD) are configured directly in their respective files in the Pterodactyl File Manager and are **never overwritten** across updates or reboots.

---

## Installation Guide

### 1. Import the Egg into Pterodactyl
1. Download [`egg-bedrockconnect-xboxbroadcast.json`](egg-bedrockconnect-xboxbroadcast.json).
2. Go to your **Pterodactyl Admin Panel** -> **Nests**.
3. Select an existing nest (e.g., *Minecraft*) or create a new one.
4. Click **Import Egg** and upload `egg-bedrockconnect-xboxbroadcast.json`.

### 2. Create the Server
1. Go to **Servers** -> **Create New**.
2. Set your server name, memory limit (recommended minimum: **1024 MB**), and disk allocation.
3. Select the **BedrockConnect + MCXboxBroadcast** egg.
4. Assign an external **UDP Port** (standard Bedrock default is `19132`).
5. Complete creation and click **Install**.

---

## Panel Variables

The egg exposes only the container-level settings that cannot be managed through server files:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `UPDATE_CHECK_INTERVAL` | `60` | Frequency in minutes to check GitHub for updates (minimum: `5`). |
| `AUTO_UPDATE_RESTART` | `true` | Automatically performs a graceful restart when a verified update is installed (`true`), or defers until the next manual reboot (`false`). |
| `GITHUB_TOKEN` | *empty* | Optional Personal Access Token if your hosting node is behind a heavily shared public IP. |
| `JAVA_MEMORY_BC` | `256` | Maximum RAM (heap limit in MB) allocated to BedrockConnect. |
| `JAVA_MEMORY_XBL` | `256` | Maximum RAM (heap limit in MB) allocated to MCXboxBroadcast. |

---

## File-First Configuration

All server-specific behavior is configured in the Pterodactyl **File Manager**:

### 1. `broadcaster/config.yml` (MCXboxBroadcast)
- **`session.session-info.ip`**: The public IP or domain name that console players will connect to.
  > [!IMPORTANT]
  > This MUST be an address accessible over the internet (e.g., your node's public IP or a domain like `mc.example.com`). Do NOT set this to `127.0.0.1` or `localhost`.
- **`session.session-info.port`**: The UDP port matching your server allocation (default: `19132`).
- **`session.session-info.host-name`**: Server name displayed on Xbox friends lists.
- **`friend-sync.auto-friend`**: Automatically accept incoming friend requests (`true` by default).

### 2. `bedrockconnect/serverlist.json` (BedrockConnect Server List)
Define the servers that appear on the BedrockConnect GUI for players:

```json
[
  {
    "name": "My Survival Server",
    "iconUrl": "https://example.com/icon.png",
    "address": "play.myserver.com",
    "port": 19132
  },
  {
    "name": "Featured: The Hive",
    "iconUrl": "",
    "address": "geo.hivebedrock.network",
    "port": 19132
  }
]
```

### 3. `bedrockconnect/config.yml` (BedrockConnect Settings)
- **`user_servers`**: Allow players to add and save custom servers to their own list (`true`/`false`).
- **`featured_servers`**: Display official Minecraft featured servers (`true`/`false`).
- **`server_limit`**: Maximum number of servers a player can save (default: `100`).

---

## First-Time Setup: Xbox Account Authentication

MCXboxBroadcast must authenticate with Xbox Live to broadcast sessions to friends:

> [!CAUTION]
> Always use a dedicated **secondary/alt Microsoft account** for broadcasting. Do not use your primary personal Microsoft account.

1. Start your server from the Pterodactyl console.
2. On initial startup, MCXboxBroadcast will output a high-visibility authentication challenge:
   ```text
   ========================================================================
     [XboxBroadcast] ACTION REQUIRED: Microsoft Account Sign-In
     1. Open: https://www.microsoft.com/link
     2. Enter Code: ABCD-1234
   ========================================================================
   ```
3. Open `https://www.microsoft.com/link` in a web browser on your computer or phone.
4. Sign in with your dedicated broadcast Microsoft account and enter the 8-character code.
5. Once authorized, MCXboxBroadcast will save the authentication tokens to `broadcaster/cache/`. Future reboots and updates will authenticate automatically without re-prompting!

---

## Connecting as a Player

1. From any Xbox, PlayStation, Switch, or Mobile device, have the player send an Xbox friend request to the Gamertag of your dedicated broadcast account.
2. MCXboxBroadcast automatically accepts the friend request.
3. Open Minecraft Bedrock Edition and navigate to the **Friends** tab.
4. Click on the broadcaster account's session.
5. The player is transferred directly to BedrockConnect, where they can choose any server from the server list!

---

## Console Commands

While the server is running, the following commands can be typed into the Pterodactyl Console:

- `status`: Displays current running PIDs and health of BedrockConnect and MCXboxBroadcast.
- `update`: Manually forces an immediate GitHub update check.
- `restart`: Gracefully restarts BedrockConnect and MCXboxBroadcast within the container.
- `stop`: Gracefully stops both services and shuts down the container cleanly.
