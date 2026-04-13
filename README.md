# DW_CarScrapping
Fivem car scrapping script

# DW_CarScrapping

Jednoduchy a optimalizovany FiveM script pro rozebirani aut postaveny na `ESX + ox_lib`.

## Funkce

- Rozebrani auta klavesou (`E`) s text UI.
- Progress (`bar` nebo `circle`) a animace nastavitelna v configu.
- Server-side validace (distance, lock session, class/model, owned vehicle policy).
- Volitelna podminka na job (vice jobu).
- Volitelna podminka na item (napr. sada na rozebirani).
- Rewardy po dokonceni (vice itemu, min/max/chance).
- Po uspesnem dokonceni se vozidlo smaze ze sveta.

## Pozadavky

- `es_extended`
- `ox_lib`
- `oxmysql`
- Tabulka `owned_vehicles` (pokud chces resit owned auta)

## Instalace

1. Resource nech ve slozce `resources/[...]/DW_CarScrapping`.
2. V `server.cfg` zajisti, aby bezely dependency resource:
   - `ensure ox_lib`
   - `ensure oxmysql`
   - `ensure es_extended`
3. Spust script:
   - `ensure DW_CarScrapping`

## Rychle nastaveni

Vse se nastavuje v `config.lua`.

### Nejdulezitejsi casti

- `Config.Scrapping.DurationSeconds` - delka rozebirani v sekundach.
- `Config.Scrapping.RequiredItem` - povinny item pro start.
- `Config.JobRestriction` - whitelist jobu.
- `Config.OwnedVehiclePolicy` - pravidla pro `owned_vehicles`.
- `Config.Rewards` - co hrac dostane po dokonceni.
- `Config.Notify` - system notifikaci (`ox_lib`, `esx`, `custom`).
- `Config.Progress` - typ progressu, disable controls a animace.

## Jak funguje owned vehicle logika

- `AllowOwnedVehicles = false`  
  -> Vozidla s plate v `owned_vehicles` nejdou rozebrat.

- `AllowOwnedVehicles = true`  
  -> Owned auta jdou rozebrat.

- `DeleteOwnedRecordWhenAllowed = true` (a zaroven `AllowOwnedVehicles = true`)  
  -> Pri schvaleni startu se smaze zaznam z `owned_vehicles`.

## Job restriction (vice jobu)

Podporovany format:

```lua
Config.JobRestriction = {
    enabled = true,
    allowedJobs = {
        mechanic = true,
        scrapper = true
    }
}
```

## Item restriction

```lua
Config.Scrapping.RequiredItem = {
    enabled = true,
    item = 'scrap_kit',
    count = 1,
    consumeOnStart = false
}
```

- `consumeOnStart = true` item odebere hned pri schvaleni startu.
- `consumeOnStart = false` item pouze kontroluje.

## Notify system

- `ox_lib` -> pouzije `lib.notify`.
- `esx` -> pouzije `esx:showNotification`.
- `custom` -> vyvola event z `Config.Notify.customEvent`.

Priklad:

```lua
Config.Notify = {
    system = 'custom',
    customEvent = 'my_notify:event'
}
```

Event dostane argumenty:

1. `description`
2. `type` (`inform`, `success`, `error`)

## Poznamky k optimalizaci

- Klient pouziva `GetClosestVehicle` (neprochazi cely vehicle pool).
- Server predpocitava hash blacklist modelu pri startu resource.
- Kriticke kontroly bezi server-side (distance, state, inventory/job/owned).

## Troubleshooting

- Stisk `E` nic nedela:
  - zkontroluj `Config.Interaction.Key` a `Radius`
  - nastav `Config.Debug = true` a sleduj logy
- Hrac nemuze rozebrat auto:
  - zkontroluj `JobRestriction`, `RequiredItem`, `AllowedVehicleClasses`, `BlacklistedModels`
- Owned auto je bloknute:
  - over `Config.OwnedVehiclePolicy`

---

Pokud chces, muzu dopsat i anglickou verzi README nebo kratky changelog format pro dalsi updaty.
