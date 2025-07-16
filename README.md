I was basically trying to write some sort of detour "hooking" framework in [Zig](https://ziglang.org/), so experimented with a relatively easy to hack around modern game called [Need for Speed Unbound](https://store.steampowered.com/app/1846380/Need_for_Speed_Unbound/). The framework is almost finished for x86_64(not 32bit or x86) architecture, mainly tested on Windows as it is a gaming OS afterall.

Since I was testing with Need for Speed Unbound the framework is kind of tangled with the full pawning Need for Speed Unbound state. I do plan to seperate them.

## PawnedNFSUnbound
*Last tested June, 2025, with the Steam version, might not work currently/in future or with the raw origin/ea play version.*

"Hacked" two things:
  1. All normal story mode races are available everyday in single player.
  2. Copy Audi R8 Race Vehicle Config to Razor's BMW M3 GTR Race Vehicle Config
     * So, basically Razor's Custom BMW M3 GTR will pretty much behave(handle, accelerate, performance upgrades etc..) like Audi R8. Except the stock engine will still sound same.
     * Yes, it is possible to do this kind of "copy" from one car to any other car. If you play around for enough time you will find a way to do with current Source Code. If not open a discussion or something.
  3. Unlock most of the items.
     * Unlocked all cars including Bonus/Custom, (Traffic, Cop probably need offline mode) cars and also bikes.
     * Unlocked all bodykits.
     * Unlocked all character models online.
     * Unlocked all banner customizations.

## Build/Install Dlls?
Last tested with `zig-x86_64-windows-0.15.0-dev.1034+bd97b6618`.
  * `git clone https://github.com/IamSanjid/PawnedNFSUnbound.git`
  * `cd PawnedNFSUnbound && zig build all`
These command should build two DLL's one loader and another main, the loader needs to get injected I just use `CheatEngine`'s inject dll thingie.

## How to use
* Build the loader and main dll. Both of them should be in the `<path to>/PawnedNFSUnbound/zig-out/bin`
* Make sure you're in the main start scene, the place where you can choose to play Single Player or Online, make sure you've not joined any lobby/party just go to the start scene.
* Inject the loader Dll `PawnedNFSUnboundLoader.dll` to the Need for Speed Unbound's process, easiest way will be by using `CheatEngine`.
* A console screen should popup, type/copy paste `load "<Full absolute path to PawnedNFSUnbound.dll>"` the `"` double quotes are recommended then press enter.
* Now go to your single player compaign or online, your Razor's Custom BMW M3 should now perform like Audi R8. And in single player campaign you should see all the normal races are available each day.

## Caveats/Disclaimer
Most of the things are marely reverse engineering issues just lazy to fix it.

It seems the `EngineStructureItemData` doesn't get properly copied on resource loading, so you've to manually go to `Performance` choose the engine and then do a *handling* synchronization(just move any of the handling slider left and right).

You need to "Find Game"/enter a lobby for things to get applied for online mode.

Random crashes, when switching from one mode to another...


## Generate Hooks templates
`zig build hook -Dhook-name=<name> -Dhook-offset=<0x hex>`

this command will generate some sort of template in the `src/hooks` directory the offset is relative to the main module `NeedForSpeedUnbound.exe` if you want to change it through command you can pass `-Dhook-base-module=<name>` command arg.

## Credits

*   [HarGabt/FrostyToolsuite](https://github.com/HarGabt/FrostyToolsuite/)
*   CheatEngine (used for DLL injection and debugging)

## License
MIT