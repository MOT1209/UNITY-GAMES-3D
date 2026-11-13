# Database integration report (database phase 8)

`tests/db_integration_validation.tscn` drives the REAL systems (MatchManager, TransferMarket, Academy/PromotionSystem, CrestRegistry/CrestService, SaveManager/AppHub, CareerState, the hub screens). 54 checks; the run found **one gap**, now fixed.

## Flows verified
| Flow | What is checked |
|---|---|
| Club -> match | the match XI is the XI of squad management (same ids and slots); every player entry holds the very same `PlayerData` object as `TeamDB`; the away side are the away club's players; every home player wears the home crest on the 3D shirt; the HUD shows both crests, home first |
| Transfer | buying a player keeps the object, permanent id and stored appearance; both `squad_ids` lists follow; the card shows the new club with the same ratings; the portrait key changes (new shirt + crest); the squad and transfer screens still work; relations stay consistent |
| Loan | the player moves, keeps id/object, remembers the owner, the card shows the borrower, he returns after the loan |
| Youth -> first team -> match | promotion keeps id, object and appearance; the promoted player is placed in the XI and plays the match as the same object |
| Crest change | an alternative crest changes the crest texture, the kit texture and the portrait keys at once; team selection and the Database tools screen draw from the same registry; switching back restores the original cache entry |
| Save and reload | after save -> reset the world -> load: the transferred player is still at his new club (id and appearance identical); the alternative crest design **(fixed)**, the imported custom crest and a user-made club (CUSTOM type, full squad) survive; season/competition statistics are identical; the reloaded database validates |
| Fictional third-tier career | career with a fictional club: league screen with 20+ crests, squad pitch shows the real XI, career dashboard and team details show crest and kits, cards carry club + kit + crest, relations consistent |

## Gap found and fixed
Alternative crest designs added in play (`CrestRegistry.add_alternative`) lived only in memory: after a save and reload the club's `crest_id` pointed at a design that no longer existed and the club silently fell back to its original crest. Now `SaveManager` writes them under `"crests"` and restores them (validated, invalid records reported, never fatal). The key is optional, so older saves load unchanged.

## Known limits (not fixed, documented)
- The demo scene `TeamPlayer.setup` (teams demo) has no database players at all; its look is a fixed seed per team and shirt number (not random per run). Real matches use the stored appearance (tested). Left as it is on purpose.
- (Fixed later) Yellow/red cards and clean sheets are now tracked per season and competition.
- (Fixed later) Repaired kits are stored in the pack files; `KitEditor.repair` stays as a safety net at load.
- (Done in phase 9) Save format is v3 with a backup.
