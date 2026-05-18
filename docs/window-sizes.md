# CharacterForge Window Sizes

All dialogs must use fixed dimensions. When content exceeds the available space, use a canvas with scroll support instead of letting the dialog grow unbounded.

Any new dialog type MUST be added to this registry.

## Non-Modal Panels

| ID | Title | Width | Height | Notes |
|---|---|---|---|---|
| main-panel | CharacterForge | 340 | 260 | Canvas with scroll. Always open during workflow. |
| details | CharacterForge — Details | 340 | 280 | Canvas-based structure preview. |
| settings | CharacterForge Settings | 280 | auto | Small, few controls. Uses native dialog sizing. |

## Modal: Create Wizard

| ID | Title Pattern | Width | Height | Notes |
|---|---|---|---|---|
| create-step1 | Create Character | 360 | 420 | Lists rebuild on add/remove. Fixed height with scroll canvas for part/outfit/effect/animation lists. |
| create-step2 | Step 2: {part} | 320 | 300 | Per-part outfit setup. Rebuilds on part switch. |
| direction-setup | Direction Setup | 280 | auto | Preset dropdown + 8 direction checkboxes. Small, fixed content. |

## Modal: Blueprint Editor Hub + Sub-dialogs

| ID | Title Pattern | Width | Height | Notes |
|---|---|---|---|---|
| edit-hub | Edit: {name} | 280 | auto | 3 buttons + close. Small, no scroll needed. |
| edit-parts | Edit Parts ({n}) | 320 | 300 | Current parts list in scroll canvas. Add/remove below. |
| edit-outfits | Outfits / Effects: {part} | 340 | 320 | Per-part, rebuilds on switch. List in scroll canvas. |
| edit-animations | Edit Animations ({n}) | 320 | 300 | Animation list in scroll canvas. Add/remove below. |

## Modal: Animation Editor Hub + Sub-dialogs

| ID | Title Pattern | Width | Height | Notes |
|---|---|---|---|---|
| edit-anim-hub | Edit Animation: {name} | 280 | auto | Hub buttons + checkbox. Small. |
| edit-anim-outfits | Outfits: {part} | 340 | 320 | Same layout as blueprint outfits editor. |
| edit-anim-parts | Edit Parts ({n}) | 320 | 300 | Same layout as blueprint parts editor. |

## Modal: Blueprint Actions

| ID | Title Pattern | Width | Height | Notes |
|---|---|---|---|---|
| new-animation | New Animation from Blueprint | 320 | auto | Blueprint picker + name entry. Native sizing OK. |
| link-animation | Link Animation to Character | 320 | auto | Blueprint picker + name entry. Native sizing OK. |
| from-current | Blueprint From Current Sprite | 280 | auto | Name entry only. Native sizing OK. |

## Modal: Alerts

| ID | Notes |
|---|---|
| app.alert | Use `app.alert{ title, text, buttons }` for short messages only. Never put long lists in alert text — show them in a scroll canvas dialog instead. |

## Rules

1. **Fixed width**: Every dialog with dynamic content must set width explicitly.
2. **Canvas for lists**: When showing a list of items (parts, outfits, animations), use a canvas widget with scroll support instead of labels. Labels cause ghost artifacts and unbounded growth.
3. **Max text in alerts**: Alert text must not exceed 3 lines. For longer content, open a dialog with a canvas.
4. **Rebuild over modify**: When content changes, close and rebuild the dialog rather than using `dlg:modify` on labels.
5. **This file is the registry**: Any new dialog type must be added here before implementation.
