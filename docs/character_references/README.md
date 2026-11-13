# Character references (Asthya)

Shared references used to keep characters consistent across sprites, portraits
and the opening cinematic (not loaded by the game: `.gdignore`).

| State | Source | Used for |
|---|---|---|
| Child before exile (~8): fully ash-brown hair, plain ivory linen, no mark | `create-character-pro` from the child-after sprite, protagonist sprite style | cinematic scenes 1-2 |
| Child after exile (~8): silver strands, ceremonial tunic, sash, wrist cuff, neck mark | `create-character-pro` from the adult portrait, protagonist sprite style | scenes 3-5 |
| Adult (~18): game sprite (authoritative) + 192 px portrait | existing sprite; portrait from `generate-image-v2` guided by the sprite | gameplay, dialogue |
| Eldric ten years earlier (~40): no gray, no pendant, wooden carrying frame | `create-character-pro` from Eldric's portrait, Eldric sprite style | scene 5 |
| Eldric (~50): game sprite + 192 px portrait (open-circle brass pendant) | portrait: `generate-image-v2` guided by a first sprite, protagonist portrait as style; sprite: `create-character-pro` from that portrait in the style of his younger self (same carrying frame), hair grays recoloured to chestnut on every frame (`tools/pixellab/recolor_hair.py`) | gameplay, dialogue |

Scenes 1-5 (`assets/story/`) were generated with `generate-image-v2` using the
same style image, scene 1 as the architecture reference for scenes 2-4, and the
character references above as subject references. 3b and 5b are text edits of
3 and 5 (`edit-images-v2`), so the framing is identical for the crossfades.
All illustrations are 480x254 and shown 1:1 in the same letterbox.

Lore notes: the adult's outfit was remade by Eldric from the original
ceremonial garment (fabric, patterns, surviving metal pieces); Eldric found the
open-circle brass pendant near the child on the day of the arrival, which is
why he does not wear it in scene 5.
