# Install into NYSP-MDT

Target: testing#1, reviewed at fef28ab. This integration adds a read-only Roblox feed to the existing Calls screen. It does not replace your CAD or convert it to a website.

## Prepare the files

From this repository, use the existing local Electron GitHub App folder and the current CAD index.html:

```text
node tools/prepare-cad-update.cjs "PATH/TO/GitHub App" "PATH/TO/index.html" "PATH/TO/NEW-UPDATE-FOLDER"
```

The script refuses to overwrite an output folder or patch an unknown/already-patched integration point. It creates:

| File | Where it belongs |
| --- | --- |
| main.js | Replace the local GitHub App/main.js after backing it up |
| bridge/electron/ | Copy this folder into the local GitHub App folder |
| index.html | Review and publish to the NYSP-MDT testing#1 repository root |
| SOURCE-MANIFEST.json | Review record containing source and output SHA-256 hashes |

The local shell dynamically loads main-remote.js with new Function(). CommonJS require is unavailable there. The adapter is therefore installed from main.js; main-remote.js needs no change. GitHub HTML updates alone cannot install this local-shell module.

Copy bridge/electron/cad-bridge.example.json to **GitHub App/cad-bridge.local.json**. Set relayUrl and the read-only CAD tokens for the sessions you use. The keys are Discord session channel IDs, not labels such as 1 or 2. Never use the game token in the desktop config.

The existing build's sessions are:

| CAD session | ID |
| --- | --- |
| Session 1 | 1011898104670330920 |
| Session 2 | 1390212294478397471 |
| Session 3 | 1390212341005680650 |
| Whitelisted | 1411101488146550784 |

Restart the Electron app after installing the local files. Log in, verify session access, select a session, and open Calls. Roblox records appear in the Roblox game feed section. The feed clears when access is revoked, the session changes, or a request fails. The bridge does not need phone streaming enabled.

If configuration is absent, the adapter remains disabled and the feed shows an unavailable message. Authentication and configuration errors do not stop the existing CAD from launching.

## Rollback

Restore the previous main.js and index.html, remove the added bridge folder and local bridge config, and restart. Keep a copy of the original shell and GitHub commit before installing. This update does not edit private CAD settings, API tokens, local profiles, or account data.
