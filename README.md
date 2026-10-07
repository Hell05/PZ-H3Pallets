# PZ-H3Pallets

Stack items on pallets! You can now interact with the empty pallets and stack 39 different items on them!

Pallets accept partially filled sacks, propane tanks and damaged or worn tires and will return them in the same condition when taken.
You can also pickup the pallets with items on them (unless they are too heavy of course).

Use existing pallets in the world or make your own from the building menu Storage category.
Vanilla pallets have their values updated so they match the displayed quantity.
Empty pallets will list all categories and items compatible.
Pallets with items on them only display relevant options.

Mix and match, some pallets accept multiple different items e.g. Ammo Cartons.

Every stage has a visual change in quantity!
Add or Remove in steps or larger quantities in one go.


Safe to add mid save (pallets that have already been loaded will still show the vanilla take choice but once you interact it goes away).
Since this mod adds tiles removing it mid save is not recommended!
Fully MP compatible! Server authoritative logic that has been tested on a dedicated server.
Unlikely to be compatible with other Pallet mods that rely on or modify the vanilla ISTakeBricks TimedAction.


Items stackable on pallets:
- All ingots
- Propane Tanks
- Sacks of Material (Dirt, Sand, Gravel, Clay)
- Bags of Concrete
- Bags of Plaster
- Logs & Planks
- Metal Sheets
- Tires
- Cash
- Ammo Cartons
- Fuel (Coal, Charcoal, Coke)
- Bricks

New logic client side is as follows:
- ClickHook -> palletMenu onto the right click context menu when there is a valid sprite in square clicked
- GetClient -> Read in data from the sprite object, things like spriteName, modData if it has any. Also client inventory.
- GetShared -> Based on GetClient, get the shared items tables for populating the context window.
- Construct -> Using the data, generate the context menu options
- Send Auth -> If an option is clicked, ISTimedActionQueue.add ( H3_InteractPallet:new(data))

Shared logic (Authoritative):
- Run :new  	-> Read in the information and initialise
- Run :isValid  -> Checks if pallet exists
- Run :actions  -> handles animations, walking etc (unchanged from vanilla ISTakeBricks)
- Run :complete -> Validates inventories and calls UpdateInventory and UpdateModData as well as changes the sprite


This mod was created primarily for SpaghettiZ's Bolognese server but anyone is welcome to use it and repack it in their own server mods.

Join Bolognese here - https://discord.gg/fhbA3vnrr9

Workshop link - https://steamcommunity.com/sharedfiles/filedetails/?id=3814418428
