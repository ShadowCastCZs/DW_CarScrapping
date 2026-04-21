fx_version 'cerulean'
game 'gta5'

lua54 'yes'

name 'DW_CarScrapping'
author 'DarkWave'
description 'ESX + ox_lib multi-step vehicle scrapping (worksites, part delivery, final shell step)'
version '2.0.0'

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
