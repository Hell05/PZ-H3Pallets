# PZ-H3Pallets

Stack items on pallets! You can now interact with the empty pallets (or build new ones from the build menu) and stack over 20 different items on them!

Items stackable on pallets:
- All ingots
- Propane Tanks
- Sacks of Material (Gravel, Sand, Concrete etc)
- Logs & Planks
- Metal Sheets
- Tires
- Cash
- Bricks

To Do:
- finish clientside logic (item removal)
- fix shared logic
- Scale down Tires texture
- Ammo Pallets
- Charcoal Pallet
- Bricks (needs more sprites)

New logic client side is as follows:
- ClickHook -> palletMenu onto the right click context menu when there is a valid sprite in square clicked
- GetClient -> Read in data from the sprite object, things like spriteName, modData if it has any. Also client inventory.
- GetShared -> Based on GetClient, get the shared items tables for populating the context window.
- Construct -> Using the data, generate the context menu options
- Send Auth -> If an option is clicked, ISTimedActionQueue.add ( H3_InteractPallet:new(data))

Shared logic:
- Run :new  	-> Read in the information and initialise
- Run :isValid  -> Confirm information independently
- Run :actions  -> handles animations, walking etc (unchanged from vanilla ISTakeBricks)
- Run :complete -> This calls UpdateInventory and UpdateModData as well as changes the sprite


This mod was created primarily for SpaghettiZ's Bolognese server but anyone is welcome to use it and repack it in their own server mods.

Join Bolognese here - https://discord.gg/fhbA3vnrr9

Workshop link - 