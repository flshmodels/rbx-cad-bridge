--!strict
-- Names shared by server and client. The server creates these RemoteEvents at startup under
-- ReplicatedStorage/<FOLDER_NAME>, so there is nothing to set up by hand in Studio.
return {
	FOLDER_NAME = "CadBridgeRemotes",
	RequestCall = "RequestCall", -- client -> server: { nature, description, priority }
	Panic = "Panic", -- client -> server: (no payload)
	Notify = "Notify", -- server -> client: (kind: "info" | "warn" | "dispatch" | "panic", message)
}
