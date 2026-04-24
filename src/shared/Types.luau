--!strict

--- @class Types
--- Shared type definitions for the Github-Specialist project.
--- Import this module wherever strong typing is required.

--- Represents persistent data stored per-player.
export type PlayerData = {
    userId: number,
    displayName: string,
    coins: number,
    level: number,
    experience: number,
    joinedAt: number,
}

--- Generic payload sent over RemoteEvents.
export type RemotePayload = {
    action: string,
    data: { [string]: any }?,
}

--- Configuration passed to a service during construction.
export type ServiceConfig = {
    name: string,
    priority: number,
}

return {}
