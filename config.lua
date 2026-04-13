--[[
  Konfigurace DW_CarScrapping
  Nahoře obecné věci, dole texty pro hráče. Úpravy stačí tady.
]]

Config = {}

-- Debug: do konzole F8 půjdou hlášky z resource (spíš pro vývoj).
Config.Debug = false

-- Jak hráč spouští rozebírání u auta (klávesa, dosah, jak často se kontroluje okolí).
Config.Interaction = {
    Key = 38, -- E — seznam kláves: https://docs.fivem.net/docs/game-references/controls/
    Radius = 3.0,
    ScanIntervalFar = 1000,
    ScanIntervalNear = 50
}

-- Délka akce, text v progress baru, která auta jdou / nejdou, povinný předmět v inventáři.
Config.Scrapping = {
    DurationSeconds = 12,
    ProgressLabel = 'Rozebiras vozidlo...',

    RequiredItem = {
        enabled = true,
        item = 'scrap_kit',
        count = 1,
        -- true = odečte item hned po schválení startu (ne až na konci)
        consumeOnStart = false
    },

    -- Které třídy aut smíš rozebrat (čísla podle GTA — přehled: GetVehicleClass na wiki / docs).
    AllowedVehicleClasses = {
        [0] = true, [1] = true, [2] = true, [3] = true, [4] = true,
        [5] = true, [6] = true, [7] = true, [8] = true, [9] = true,
        [10] = true, [11] = true, [12] = true, [13] = true,
        [18] = true, [20] = true
    },

    -- Modely navždy zakázané: název spawnu jako klíč, např. police = true
    BlacklistedModels = {}
}

-- Auta z garáže (owned_vehicles): jestli vůbec jdou rozebrat a jestli se má smazat záznam v DB.
Config.OwnedVehiclePolicy = {
    AllowOwnedVehicles = false,
    DeleteOwnedRecordWhenAllowed = false
}

-- Jen vybrané joby — když je enabled false, job se nekontroluje.
Config.JobRestriction = {
    enabled = false,
    allowedJobs = {
        mechanic = true
    }
}

-- Co hráč dostane po úspěchu: item, rozmezí množství, šance v procentech.
Config.Rewards = {
    { item = 'scrap', min = 1, max = 3, chance = 100 },
    { item = 'carparts', min = 2, max = 5, chance = 100 }
}

-- Jak se zobrazují hlášky: ox_lib, klasické ESX, nebo vlastní event (customEvent).
Config.Notify = {
    system = 'ox_lib',
    title = 'Car Scrapping',
    duration = 4000,
    position = 'top-right',
    icon = 'screwdriver-wrench',
    customEvent = nil
}

-- Progress z ox_lib — pruh nebo kruh. Animace: buď scenario, nebo dict + clip (záleží na type uvnitř anim).
Config.Progress = {
    type = 'bar',
    useWhileDead = false,
    canCancel = true,
    disable = { move = true, car = true, combat = true },
    anim = {
        type = 'scenario',
        scenario = 'WORLD_HUMAN_WELDING',
        dict = 'amb@world_human_welding@male@base',
        clip = 'base',
        flag = 49
    }
}

-- Všechny věty, které uvidí hráč (můžeš přepsat podle serveru).
Config.Locale = {
    Prompt = '[E] Rozebrat vozidlo',

    Busy = 'Nekdo uz toto vozidlo rozebira.',
    InProgress = 'Prave neco rozebiras.',
    TooFar = 'Jsi prilis daleko od vozidla.',
    InvalidVehicle = 'Toto vozidlo nelze rozebrat.',
    OwnedBlocked = 'Soukrome vozidlo nelze rozebrat.',
    MissingRequiredItem = 'Potrebujes sadu na rozebirani auta.',
    JobNotAllowed = 'Tvuj job nema opravneni rozebirat vozidla.',

    StartFailed = 'Rozebrani se nepodarilo spustit.',
    Cancelled = 'Rozebirani bylo zruseno.',
    Success = 'Vozidlo bylo rozebrano a odklizeno.',
    GenericError = 'Neco se pokazilo, zkus to znovu.'
}
