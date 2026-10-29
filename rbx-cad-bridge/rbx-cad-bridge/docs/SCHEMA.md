# Database schema

> **Important:** the field names below are this bridge's *canonical* names, chosen before seeing your
> CAD's exact data model. If your CAD uses different names, do **not** edit the code: set
> `Config.fieldMap` (see the bottom of this file). The same map is applied in reverse when records are
> read back.

Collections live under `Config.paths` (defaults `calls`, `units`, `panics`). Record ids are generated
by the server: `<unix seconds, 11 digits>_<JobId prefix>_<counter>`, for example
`01761696000_ab12cd34_0001`. They are time-ordered, key-safe, and unique per server, and because the
bridge writes with `PUT`, retrying a write can never create a duplicate.

## `calls/<id>`

```json
{
  "source": "roblox",
  "nature": "Shots fired",
  "description": "man with a handgun behind the gas station",
  "priority": "high",
  "location": "Courthouse [120, -48]",
  "status": "pending",
  "callerUserId": 1234567,
  "callerName": "CantBeatMeFLASH",
  "createdAt": 1761696000123
}
```

`createdAt` is written as Firebase's server timestamp, not the Roblox server's clock.
`priority` is one of `low | medium | high | emergency`.

To assign an officer, the CAD writes either of these to the call (both are understood):

```json
"assigned": { "1234567": true }
"assigned": [1234567]
```

where the value is the officer's **Roblox UserId**.

## `units/<robloxUserId>`

```json
{
  "source": "roblox",
  "userId": 1234567,
  "username": "CantBeatMeFLASH",
  "callsign": "2A-14",
  "status": "available",
  "lastSeen": 1761696060000
}
```

`status` is one of `offline | available | busy | en_route | on_scene | panic`. The bridge uses `PATCH`,
so any extra fields your CAD adds to a unit are preserved. A dispatcher changing `status` in the CAD
is delivered to the player in game.

## `panics/<id>`

```json
{
  "source": "roblox",
  "userId": 1234567,
  "username": "CantBeatMeFLASH",
  "callsign": "2A-14",
  "location": "Near Courthouse, ~85 studs [200, 12]",
  "status": "active",
  "createdAt": 1761696000123
}
```

## Mapping to your CAD's field names

```lua
-- src/server/Config.luau
fieldMap = {
	calls  = { nature = "type", description = "notes", location = "address", priority = "level" },
	units  = { callsign = "unitId" },
	panics = {},
},
paths = { calls = "dispatch/calls", units = "dispatch/units", panics = "dispatch/panics" },
```

Keys are canonical names, values are your CAD's names. Only top-level fields are renamed. If your CAD
needs a different *structure* (nested objects, different value formats), add a mapper in
`Core/Mappers.luau` and cover it with a test.

## Making the CAD show Roblox calls

Your web CAD already listens to its calls path with Firebase listeners. If `paths.calls` and `fieldMap`
point at the data your CAD expects, new in-game calls appear like any other call. The `source: "roblox"`
field lets the CAD badge them.
