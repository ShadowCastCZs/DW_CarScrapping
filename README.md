# DW_CarScrapping

Jednoduchy a optimalizovany FiveM script pro rozebirani aut postaveny na `ESX + ox_lib`.

**Aktualni verze:** `1.1.0` (viz `fxmanifest.lua`).

## Funkce

- Rozebrani auta klavesou (`E`) s text UI (jde v configu vypnout).
- Client export `TryScrapVehicle` pro spusteni z `ox_target`, vlastniho menu apod.
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

## Aktualizace (changelog)

### 1.1.0 (z verze 1.0.0)

**Co je nove**

- V `config.lua` pribyl prepinac **`Config.Interaction.BuiltinKeybind`** (default `true`).
  - `false` = vypne text UI a klavesu **E** u auta; rozebirani spoustis jen zvenci (export / target).
- Na **klientovi** je export **`TryScrapVehicle`**: stejny server flow jako u E (job, item, owned vozidla, validace).
  - Volani: `exports['DW_CarScrapping']:TryScrapVehicle(entity, opts?)` → vraci `ok, err`.
  - Volitelne `{ silent = true }` = pri chybe neposila notify z tohoto resource.

**Migrace z 1.0.0**

- Staci nahradit soubory resource a restartovat. Chovani zustane stejne, pokud v configu **nepridas** `BuiltinKeybind` — chybi-li klic, bere se jako zapnute E (jako drive).
- Chces-li **jen** target/export bez E: pridej `BuiltinKeybind = false` do `Config.Interaction`.
- Zadna zmena v `server.cfg` ani v nazvech eventu/callbacku oproti 1.0.0.

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
- `Config.Interaction.BuiltinKeybind` - zapnute/vypnute defaultni E u auta.

## Export (spusteni mimo E)

Na **klientovi** je export `TryScrapVehicle`. Pouziva stejny server callback jako klavesa — job, required item, owned vozidla a dalsi pravidla zustavaji.

```lua
local ok, err = exports['DW_CarScrapping']:TryScrapVehicle(vehicleEntity)
if not ok then
    -- err = text chyby (stejne hlasky jako hraci)
end
```

Bez vlastni notifikace z tohoto resource (hlasku si posles sam):

```lua
local ok, err = exports['DW_CarScrapping']:TryScrapVehicle(vehicleEntity, { silent = true })
```

- `vehicleEntity` musi byt existujici **vehicle** (`GetEntityType` == 2).
- Funkce je **blokujici** az do konce progress baru (nebo chyby) — z `ox_target` obvykle volas z callbacku v threadu.

Vypnuti E u auta (jen export / vlastni UI):

```lua
Config.Interaction.BuiltinKeybind = false
```

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
  - pokud mas `BuiltinKeybind = false`, E se nepouziva — pouzij export `TryScrapVehicle`
  - zkontroluj `Config.Interaction.Key` a `Radius`
  - nastav `Config.Debug = true` a sleduj logy
- Hrac nemuze rozebrat auto:
  - zkontroluj `JobRestriction`, `RequiredItem`, `AllowedVehicleClasses`, `BlacklistedModels`
- Owned auto je bloknute:
  - over `Config.OwnedVehiclePolicy`

---