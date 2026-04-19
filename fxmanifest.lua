fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'DW_CarScrapping'
author 'DarkWave'
description 'ESX + ox_lib vehicle scrapping (export TryScrapVehicle, optional builtin E)'
version '1.1.0'

shared_scripts {
    '@ox_lib/init.lua',
    'config.lua'
}

client_scripts {
    'client/main.lua'
}

server_scripts {
    '@oxmysql/lib/MySQL.lua',
    'server/main.lua'
}

dependencies {
    'es_extended',
    'ox_lib',
    'oxmysql'
}
