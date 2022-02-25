# [L4D2 Only] Spit Spread Patch

### Introduction
- Fix various spit spread issues.
	1. Spit bursts under entities rather than on their surfaces.
	2. Spit doesn't spread on entities (i.e. in elevator).
	3. Spit doesn't spread in saferoom/area.
		- Optional feature, controls provided to turn it off accordingly.
	4. Death spit doesn't land (game insists to create it whilst the trace fails to ground).
		- Fix is not there but a ConVar is provided to modify the trace length.

<hr>

### Installation
1. Put the **l4d2_spit_spread_patch.smx** to your _plugins_ folder.
2. Put the **l4d2_spit_spread_patch.txt** to your _gamedata_ folder.

<hr>

### Changelog
(v1.0 2022/2/25 UTC+8) Initial release.