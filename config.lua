--[[
  Konfigurace DW_CarScrapping
  Nahoře obecné věci, dole texty pro hráče. Úpravy stačí tady.
]]

Config = {}

-- Debug: do konzole F8 půjdou hlášky z resource (spíš pro vývoj).
Config.Debug = false

-- Rezimy systemu:
--  - 'pro' = aktualni detailni workflow (body + dily + odevzdani)
--  - 'off' = vypne interakce i flow v tomto resource
Config.Profile = {
    Mode = 'pro'
}

-- Jak hráč spouští rozebírání u bodů (klávesa, intervaly smyčky).
Config.Interaction = {
    BuiltinKeybind = true,
    Key = 38, -- E — seznam kláves: https://docs.fivem.net/docs/game-references/controls/
    ShowStartPromptOnlyWhenDriver = true,
    ScanIntervalFar = 1000,
    ScanIntervalNear = 100
}

--[[
  Všechny dosahy na jednom místě (klient + server).
  Staré hodnoty zůstávají jako výchozí ekvivalent dřívějšího chování.
]]
Config.Distances = {
    -- Klient: prompt [E] u startu / dropu / demontáže (dříve Interaction.Radius)
    InteractionPrompt = 3.0,
    -- Klient: max vzdálenost od auta při demontáži (dříve Scrapping.WorkRadiusFromVehicle)
    WorkNearVehicle = 4.0,
    -- Klient: max vzdálenost od konkrétního dílu (bone)
    PartInteract = 2.0,
    -- Klient: marker cílového dílu se kreslí jen do této vzdálenosti od hráče
    PartMarkerDrawRange = 8.0,
    -- Klient: marker rozebírání auta (dílů na autě) se kreslí jen pokud jsi blízko auta
    VehicleMarkerDrawRange = 12.0,
    -- Klient: kreslit markery jen pokud je hráč blízko pracoviště (optimalizace; 0 = vždy kreslit)
    MarkerDrawRange = 10.0,

    -- Server: max vzdálenost hráč ↔ vozidlo při schválení startu (dříve Radius + 1.5)
    ServerPedToVehicle = 4.5,
    -- Server: max vzdálenost hráč ↔ StartPoint pracoviště
    ServerStartPointMax = 8.5,
    -- Server: max vzdálenost hráč ↔ DropPoint při odevzdání dílu
    ServerDropPointMax = 7.5
}

Config.Security = {
    -- Minimální prodleva mezi odevzdáními dílů (ms), proti spamu
    DeliverCooldownMs = 400
}

-- Pracoviště rozebírání (libovolný počet bodů + libovolný počet jobů na každé lokaci).
-- allowedJobs:
--  - prázdné / nil = kdokoliv (pak platí globální Config.JobRestriction)
--  - vyplněné = whitelist jen pro tu lokaci
Config.Worksites = {
    {
        id = 'city_mechanic',
        label = 'Mestsky vrakoviste',
        StartPoint = vec3(-1157.969971, -2021.020020, 13.140000),
        DropPoint = vec3(-1154.979980, -2022.910034, 13.170000),
        allowedJobs = {
            mechanic = true,
            police = true
        }
    }
    --[[
    ,{
        id = 'sandy_mechanic',
        label = 'Sandy vrakoviste',
        StartPoint = vec3(2349.27, 3132.49, 48.20),
        DropPoint = vec3(2356.10, 3140.80, 48.20),
        allowedJobs = {
            mechanic = true
        }
    }
    ]]
}

Config.Points = {
    Marker = {
        enabled = true,
        type = 1,
        scale = vec3(1.2, 1.2, 0.35),
        color = { r = 0, g = 170, b = 255, a = 130 },
        bobUpAndDown = false,
        rotate = false
    },
    Blip = {
        enabled = true,
        sprite = 365,
        color = 3,
        scale = 0.8,
        shortRange = true
    },
    PartGuide = {
        enabled = true,
        marker = {
            enabled = true,
            type = 6,
            scale = vec3(0.82, 0.82, 0.82),
            color = { r = 255, g = 180, b = 0, a = 180 },
            forwardOffset = 0.0,
            zOffset = 0.0
        }
    }
}

-- Rozborka: validace vozidla + časování akcí + požadovaný item.
Config.Scrapping = {
    PartActionSeconds = 6,
    DeliveryActionSeconds = 4,
    WorkRadiusFromVehicle = 4.0, -- zrcadlo pro kompatibilitu; používá se Distances.WorkNearVehicle pokud je nastaveno
    PartInteractDistance = 2.0,  -- zrcadlo; používá se Distances.PartInteract
    AutoDeleteVehicleOnComplete = true,

    Progress = {
        UseStartProgress = false,   -- false = bez progressu při přípravě auta
        UseDeliveryProgress = false, -- false = bez progressu při odevzdání/pokládání dílu
        RemoveLabel = 'Demontujes dil...',
        DeliverLabel = 'Odnasis dil...',
        StartLabel = 'Pripravuji vozidlo k rozebrani...'
    },
    FinalVehicleStep = {
        enabled = true, -- true = po vsech dilech je nutne jeste rozebrat zbytek karoserie
        ActionSeconds = 8,
        ProgressLabel = 'Rozebiras zbytek karoserie...'
    },

    RequiredItem = {
        enabled = true,
        item = 'car_toolbox',
        count = 1,
        -- true = odečte item hned po schválení startu (ne až na konci)
        consumeOnStart = true
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
    DeleteOwnedRecordWhenAllowed = false,
    TableName = 'owned_vehicles'
}

-- Jen vybrané joby — když je enabled false, job se nekontroluje.
Config.JobRestriction = {
    enabled = false,
    allowedJobs = {
        mechanic = true
    }
}

-- Odemčené části rozborky v pořadí.
-- id = interní klíč, label = text ve checklistu.
Config.TaskOrder = {
    { id = 'wheels', label = 'Demontuj kola', countMode = 'wheels' },
    { id = 'doors', label = 'Demontuj dvere', countMode = 'doors' },
    { id = 'hood', label = 'Demontuj kapotu', count = 1 },
    { id = 'trunk', label = 'Demontuj kufr', count = 1 },
    { id = 'bumpers', label = 'Demontuj narazniky', count = 2 },
    { id = 'battery', label = 'Demontuj baterii', count = 1 },
    { id = 'exhaust', label = 'Demontuj vyfuk', count = 1 },
    { id = 'plate', label = 'Demontuj SPZ', count = 1 },
    { id = 'engine', label = 'Demontuj motor', count = 1 }
}

-- Odrměny za odevzdání JEDNOHO kusu daného typu.
-- Můžeš přidat víc řádků pro stejný partType (rolluje se každý řádek zvlášť).
Config.PartRewards = {
    wheels = {
        { item = 'car_parts', min = 1, max = 2, chance = 100 }
    },
    doors = {
        { item = 'car_parts', min = 1, max = 2, chance = 100 }
    },
    hood = {
        { item = 'car_parts', min = 1, max = 2, chance = 100 }
    },
    trunk = {
        { item = 'car_parts', min = 1, max = 2, chance = 100 }
    },
    bumpers = {
        { item = 'car_parts', min = 1, max = 2, chance = 100 }
    },
    battery = {
        { item = 'car_parts', min = 1, max = 1, chance = 70 }
    },
    exhaust = {
        { item = 'metalscrap', min = 1, max = 3, chance = 100 }
    },
    plate = {
        { item = 'metalscrap', min = 1, max = 1, chance = 100 }
    },
    engine = {
        { item = 'carparts', min = 2, max = 4, chance = 100 },
        { item = 'metalscrap', min = 2, max = 5, chance = 100 }
    },
    shell = {
        { item = 'metalscrap', min = 4, max = 8, chance = 100 }
    }
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

-- Progress z ox_lib.
Config.Progress = {
    type = 'bar',
    useWhileDead = false,
    canCancel = false,
    useAnim = false, -- neměnit!
    disable = { move = true, car = true, combat = true }
}

-- Emote vrstva (default pro rpemotes-reborn exports).
-- provider:
--  - 'rpemotes' = používá exports[scriptName]:EmoteCommandStart / EmoteCancel
--  - 'none' = emote se nepouští
--
-- allowCancel:
--  - false = během fáze nepovolí cancel progressu
--  - true = hráč může fázi zrušit
--
-- Pokud chceš vlastní script, nastav provider='custom' a doplň customStartEvent/customStopEvent. Jedná se o triggerEvent.
Config.Emotes = {
    provider = 'rpemotes',
    scriptName = 'rpemotes-reborn',-- nebo dpemotes
    customStartEvent = nil,
    customStopEvent = nil,
    stopOnActionEnd = true,

    -- Přepsání animací podle typu dílu.
    -- Pokud je typ uvedený, použije se místo globální remove/carry.
    -- Podporované klíče: wheels, doors, hood, trunk, bumpers, battery, exhaust, plate, engine, shell
    byPart = {
        wheels = {
            remove = { emote = 'mechanic4', allowCancel = false },
            carry = { emote = 'wheel', allowCancel = false }
        },
        doors = {
            remove = { emote = 'weld', allowCancel = false },
            carry = { emote = 'door', allowCancel = false }
        },
        hood = {
            remove = { emote = 'weld', allowCancel = false },
            carry = { emote = 'hood', allowCancel = false }
        },
        trunk = {
            remove = { emote = 'mechanic2', allowCancel = false },
            carry = { emote = 'trunk', allowCancel = false }
        },
        bumpers = {
            remove = { emote = 'mechanic4', allowCancel = false },
            carry = { emote = 'bumper', allowCancel = false }
        },
        battery = {
            remove = { emote = 'mechanic', allowCancel = false },
            carry = { emote = 'batery', allowCancel = false }
        },
        exhaust = {
            remove = { emote = 'mechanic3', allowCancel = false },
            carry = { emote = 'exhaust', allowCancel = false }
        },
        plate = {
            remove = { emote = 'mechanic4', allowCancel = false },
            carry = { emote = 'plate', allowCancel = false }
        },
        engine = {
            remove = { emote = 'mechanic2', allowCancel = false },
            carry = { emote = 'engine', allowCancel = false }
        },
        shell = {
            remove = { emote = 'weld', allowCancel = false }
        }
    }
}

-- Všechny věty, které uvidí hráč (můžeš přepsat podle serveru).
Config.Locale = {
    StartPrompt = '[E] Spustit rozebirani vozidla',
    DropPrompt = '[E] Odevzdat dil',
    WorkPrompt = '[E] Demontovat dalsi kus',
    FinalWorkPrompt = '[E] Rozebrat zbytek vozidla',

    InProgress = 'Prave neco rozebiras.',
    TooFar = 'Jsi prilis daleko od vozidla.',
    InvalidVehicle = 'Toto vozidlo nelze rozebrat.',
    MustBeDriver = 'Musis sedet na miste ridice v aute.',
    SessionMissing = 'Rozebirani neni aktivni.',
    WrongPartOrder = 'Ted musis pokracovat v aktualnim ukolu.',
    NotAtDropPoint = 'S dilcem musis k odevzdacimu bodu.',
    NotAtWorkPoint = 'Pro demontaz musis byt u rozebiraneho auta.',
    TooFarFromPart = 'Postav se bliz k dilu, ktery chces demontovat.',
    NoPartToDeliver = 'Nemas co odevzdat.',
    DriverSeatOccupied = 'Ridicske sedadlo musi byt volne — vystup, nebo nech ridit nekoho jineho.',
    CannotCarryReward = 'Mas plny inventar — uvolni misto, pak to zkus znovu.',
    OwnedBlocked = 'Soukrome vozidlo nelze rozebrat.',
    MissingRequiredItem = 'Potrebujes sadu na rozebirani auta.',
    JobNotAllowed = 'Tvuj job nema opravneni rozebirat vozidla.',

    StartFailed = 'Rozebrani se nepodarilo spustit.',
    Cancelled = 'Rozebirani bylo zruseno.',
    Success = 'Vozidlo bylo kompletne rozebrano.',
    VehicleLocked = 'Vozidlo je uzamcene. Zacni rozborku.',
    PartDetached = 'Dilec je sundany. Odnes ho do bodu odevzdani.',
    PartDelivered = 'Dilec byl odevzdan.',
    FinalStepReady = 'Vsechny dily jsou odevzdane. Rozebir zbytek vozidla.',
    FinalStepLabel = 'Rozebrat zbytek vozidla',
    NextTask = 'Hotovo. Pokracuj dalsim ukolem.',
    ChecklistTitle = 'SEZNAM ROZBORKY',
    GenericError = 'Neco se pokazilo, zkus to znovu.'
}
