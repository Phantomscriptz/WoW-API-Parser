# WoW API Workbench 2.5.0

## Current phase

**Verified expansion-specific API inventory.** The immediate engineering task is to finish understanding and normalizing the existing 2.4.5 dataset before any large-scale example generation.

## Project goal

Build a complete, evidence-backed WoW API knowledge base and example workbench that:

1. Enumerates the available WoW API surface for each supported product/expansion.
2. Separates product/build-specific APIs so an API unavailable in one product can never be silently used there.
3. Uses the verified API inventory to create practical in-game Lua functions.
4. Produces Basic, Moderate, and Advanced examples covering many different in-game scenarios. Examples may combine any number of other APIs, provided every dependency is verified for the target product/build.
5. Produces no more than **20 Advanced examples per API/product target**. The Advanced examples should be genuinely useful and varied rather than repetitive.
6. Uses authoritative and community technical sources for API discovery, documentation, history, signatures, and examples. Sources may include Ketho, Blizzard UI source, Warcraft Wiki, WoWInterface, CurseForge, and other relevant technical references.
7. Treats example-source material as research/inspiration only. A source that merely mentions an API does not establish that the API exists for a target product/build.

## Supported products

- Retail
- Classic
- Classic Era
- Classic Anniversary

PTR/beta/titan branches may be retained as source/reference data, but must not be silently promoted into the four production product inventories.

## Source roles

- Ketho BlizzardInterfaceResources / vscode-wow-api — primary API discovery and version/build-specific source
- KethoDoc — documentation/signature enrichment
- Blizzard UI Source — implementation, availability, and deprecation/source verification
- Warcraft Wiki — documentation, history, and cross-reference
- WoWInterface — real addon usage/example research
- CurseForge — real addon usage/example research
- Other technical/community sources — supplemental example and historical research, subject to verification

## Hard rules

- An API may be used in an example only if it is verified for the target product/build.
- Product/build separation is mandatory; no global availability assumptions.
- Unknown or unverified APIs must not be silently substituted or included.
- Global Functions documentation does not imply availability in every expansion.
- Examples may combine multiple verified WoW APIs.
- Example dependencies must be extracted and validated before an example is accepted.
- Examples should be standalone functions where practical.
- Examples target practical in-game/addon automation scenarios.
- Advanced examples are capped at 20 per API/product target.
- The final example corpus must not be generated until the verified inventory and dependency validator are working.

## Immediate engineering tasks

1. Run `Inspect_Database_Schema.bat` on the existing 2.4.5 dataset.
2. Review the generated schema report and identify the actual record model, product fields, source fields, signatures, and identifiers already present.
3. Preserve the working 2.4.5 ingestion/diagnostic behavior; do not rewrite it blindly.
4. Define the canonical 2.5.0 API record model from the observed data.
5. Add product/build-aware canonical records for Retail, Classic, Classic Era, and Classic Anniversary.
6. Import/normalize the relevant Ketho branches into the canonical model.
7. Attach source evidence, build, product, availability, and verification status to each API.
8. Implement an availability query such as `IsAPIAvailable(apiName, product, build)`.
9. Implement Lua example dependency extraction and validation. Every API referenced by an example must resolve to the verified inventory for the target product/build.
10. Only then build the Basic / Moderate / Advanced example engine.

## Example goals

For every verified API where useful:

- **Basic:** at least one clear, direct example.
- **Moderate:** at least one realistic example showing practical composition.
- **Advanced:** up to 20 genuinely useful examples covering different scenarios. Advanced examples may combine many other verified APIs available to that product/build.

The example corpus is intended to become the practical foundation for a future addon/automation project, so examples must favor real, useful game-state interactions over toy snippets.

## Next checkpoint

The next deliverable is **database schema discovery and architecture mapping**, not mass example generation. Once that report is reviewed, the next code change should establish the canonical product/build-aware inventory without destroying the existing 2.4.5 baseline.
