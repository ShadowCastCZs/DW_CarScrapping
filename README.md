# DW_CarScrapping

Multi-step FiveM car scrapping script for `ESX + ox_lib`.

Current version: `2.0.0` (see `fxmanifest.lua`).

## What It Does

- Starts scrapping at a configured map start point (`Worksites.StartPoint`).
- Locks and freezes the selected vehicle for the active session.
- Runs ordered dismantle tasks from `Config.TaskOrder`:
  - wheels, doors, hood, trunk, bumpers, battery, exhaust, plate, engine
- Requires carrying each removed part to `Worksites.DropPoint` for reward payout.
- After all parts are delivered, requires a final shell dismantle step on the vehicle.
- Supports per-part emotes (`Config.Emotes.byPart`) and final shell emote (`shell.remove`).
- Supports per-part rewards (`Config.PartRewards`) including shell reward (`PartRewards.shell`).
- Includes server-side validation (distance, owned vehicle rules, class/model whitelist, anti-spam).

## Dependencies

- `es_extended`
- `ox_lib`
- `oxmysql`
- `owned_vehicles` table (only if you enforce owned vehicle checks)

## Installation

1. Put resource in `resources/[...]/DW_CarScrapping`.
2. Ensure dependencies in `server.cfg`:
   - `ensure ox_lib`
   - `ensure oxmysql`
   - `ensure es_extended`
3. Start resource:
   - `ensure DW_CarScrapping`

## Main Config Sections

Everything is configured in `config.lua`.

- `Config.Profile`
  - `Mode = 'pro'` for normal use
  - `Mode = 'off'` to disable script interaction flow
- `Config.Worksites`
  - Multiple worksites supported
  - Each worksite has its own `StartPoint`, `DropPoint`, and optional `allowedJobs`
- `Config.Distances`
  - Client/server interaction and validation ranges
- `Config.Scrapping`
  - Timing, required item, allowed classes, blacklisted models
  - Final body step: `Config.Scrapping.FinalVehicleStep`
- `Config.TaskOrder`
  - Ordered dismantle checklist
- `Config.PartRewards`
  - Reward tables per delivered part type
  - Final shell reward: `Config.PartRewards.shell`
- `Config.Emotes`
  - `rpemotes-reborn` or custom/none
  - Per-part overrides in `byPart`
- `Config.Notify` and `Config.Progress`
  - Notification backend + progress style

## Client Export

Use this from another client script (for example `ox_target` callback):

```lua
local ok, err = exports['DW_CarScrapping']:TryScrapVehicle(vehicleEntity, { silent = true })
if not ok then
    print(err)
end
```

Notes:
- `vehicleEntity` must be a valid vehicle entity.
- Export uses the same server checks as built-in interaction.

## Owned Vehicle Policy

`Config.OwnedVehiclePolicy`:

- `AllowOwnedVehicles = false` blocks vehicles found in `owned_vehicles`.
- `AllowOwnedVehicles = true` allows them.
- `DeleteOwnedRecordWhenAllowed = true` removes DB record on approved start.

## Rewards

- Part rewards are paid on each successful part delivery (`deliverPart` callback).
- Shell reward is paid on final completion (`finish` event) from `PartRewards.shell`.

## Notes

- SPZ (`plate`) can be dismantled from front or rear side (nearest point is used).
- Checklist and prompts are shown only for active session flow.

## Troubleshooting

- Cannot start:
  - Check `RequiredItem`, `JobRestriction`, `AllowedVehicleClasses`, `BlacklistedModels`.
  - Check player is close enough to start point and vehicle.
- Part cannot be delivered:
  - Check distance to drop point and inventory capacity.
- Owned vehicle blocked:
  - Verify `Config.OwnedVehiclePolicy`.