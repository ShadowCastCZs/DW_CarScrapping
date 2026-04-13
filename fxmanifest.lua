fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'DW_CarScrapping'
author 'DarkWave'
description 'Optimized ESX vehicle scrapping with ox_lib'
version '1.0.0'

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
