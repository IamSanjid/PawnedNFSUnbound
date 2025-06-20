I was basically trying to write some sort of detour "hooking" framework in [Zig](https://ziglang.org/), so was testing with a relatively easy to hack around modern game called [Need for Speed Unbound](https://store.steampowered.com/app/1846380/Need_for_Speed_Unbound/). So the framework is almost finished for x86_64 architecture, mainly tested on Windows as it is a gaming OS afterall.

Since I was testing with Need for Speed Unbound the framework is kind of entangled with the full pawning Need for Speed Unbound project. I do plan to seperate them, just for now.

# PawnedNFSUnbound
*Works with the Steam version might not work with the raw origin/ea play version.*

"Hacked" two things:
  1. All normal story mode races available everyday in single player.
  2. Copy Audi R8 Race Vehicle Config to Razor's BMW M3 GTR Race Vehicle Config
     * So, basically Razor's Custom BMW M3 GTR will pretty much behave(handle, accelerate, performance upgrades etc..) like Audi R8. Except the stock engine will still sound same.
     * Yes, it is possible to do this kind of "copy" from one car to any other car. If you play around for enough time you will find a way to do with current Source Code. If not open an discussion or something.

# Build/Install/Dlls?
Last tested with `zig-x86_64-windows-0.15.0-dev.848+f3940ad85`.
  * `git clone https://github.com/IamSanjid/PawnedNFSUnbound.git`
  * `cd PawnedNFSUnbound && zig build all`
These command should build two DLL's one loader and another main, the loader needs to get injected I just use `CheatEngine`'s inject dll thingie.

# How to use
* Build the loader and main dll. Both of them should be in the `<path to>/PawnedNFSUnbound/zig-out/bin`
* Make sure you're in the main start scene, the place where you can choose to play Single Player or Online, make sure you've not joined any lobby/party just go to the start scene.
* Inject the loader Dll `PawnedNFSUnboundLoader.dll` to the Need for Speed Unbound's process, easiest way will be by using `CheatEngine`.
* A console screen should popup, type/copy paste `load "<Full absolute path to PawnedNFSUnbound.dll>"` the `"` double quotes are recommended then press enter.
* Now go to your single player compaign or online, your Razor's Custom BMW M3 should now perform like Audi R8. And in single player campaign you should see all the normal races are available each day.
* Do `unload 0` and press enter before exiting a mode like exiting from single player or online mode. So do `unload 0` before you press "Leave Game". To use the hacks do `load` once again by following above instructions.

# Caveats/Disclaimer
The game crashes after doing the `load "<Full absolute path to PawnedNFSUnbound.dll>"` command.
  * Make sure you're at the start screen where you choose Signle Player or Online mode, and only that time do the load command.

The game crashes after I exit a mode.
  * Enter `unload 0` in the console and press enter before exiting a mode.

Why all of these issues? I am too lazy to properly find a function where I can hook to detect Loading/Unloading/Exiting etc state. So many of the invalid state still remains when exiting a mode.

So basically didn't wanna do hardcore reverse engineering.

# Generate Hooks templates
`zig build hook -Dhook-name=<name> -Dhook-offset=<0x hex>`

this command will generate some sort of template in the `src/hooks` directory the offset is relative to the main module `NeedForSpeedUnbound.exe` if you want to change it through command you can pass `-Dhook-base-module=<name>` command arg.
