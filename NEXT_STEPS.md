# WoW API Workbench 2.5.0

## Current phase

**Verified expansion-specific API inventory.** Do not mass-generate examples yet.

## Product targets

- Retail
- Classic
- Classic Era
- Classic Anniversary

## Source roles

- Ketho BlizzardInterfaceResources — primary API discovery/version-specific source
- KethoDoc — documentation/signature enrichment
- Blizzard UI Source — implementation/deprecation/source verification
- Warcraft Wiki — documentation/history/cross-reference
- WoWInterface — real addon usage/example research
- CurseForge — real addon usage/example research
- Baneto Source Code — example complexity/style inspiration ONLY

## Hard rule

Baneto is **not** an API source. If an API is not independently verified for the target product/build, it must not appear in that product's examples. `TraceLine` is the canonical example of something that must not enter the example system merely because it occurs in Baneto.

## What you do next

1. Open the Workbench and verify the 2.4.5 baseline still works.
2. Read `PROJECT_STATE_2.5.0.json`.
3. Identify the existing inventory/parser/database architecture.
4. Add the four product/build model without breaking the existing database.
5. Import the four Ketho branches and normalize them into one canonical API model.
6. Attach source evidence, build, and availability status to each API.
7. Add an availability check such as `IsAPIAvailable(apiName, product/build)`.
8. Add Lua example dependency extraction and validation. Every API referenced by an example must resolve to the verified inventory for the target product/build.
9. Only then build the Basic / Modern / Advanced example engine.

## Eventual example goal

For every verified API in every supported product: Basic, Modern, and up to 20 genuinely useful advanced examples. Advanced examples may combine any number of other **verified** WoW APIs available to that product. They should resemble serious addon/bot automation logic in sophistication, using Baneto only as a style/complexity reference.

## Future continuation

Give this ZIP to the next chat and say:

> Continue the WoW API Workbench from `PROJECT_STATE_2.5.0.json`. Continue from the listed next tasks. Do not regenerate the project from scratch.
