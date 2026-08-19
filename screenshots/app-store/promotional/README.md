# Moro App Store promotional screenshots

This set uses the continuous-story structure of template 22 from the referenced
Figma community file. Screens 1-3 are cut from one panoramic master, screens
4-6 are independent, screens 7-8 share a second master, and screens 9-10 are
independent.

The UI is rendered deterministically. Fictional avatars, covers, and post media
are generated editorial illustrations, so the screens remain legible and
accurate without exposing real accounts or timelines.

The primary README showcase highlights four complementary states:

- `04-moro.png` — multilingual timeline with photo, poll, and emoji reactions
- `07-moro.png` + `08-moro.png` — continuous post-editor story with poll,
  media, alt-text status, emoji, visibility, drafts, and language controls
- `09-moro.png` — categorized notifications with mentions, reactions, follows,
  media context, and poll results

Render the ten 1320 x 2868 screenshots with:

```sh
node screenshots/app-store/promotional/render.mjs
```

Outputs are written to `screenshots/app-store/en-US/promotional/`.
Combined masters and a contact sheet are written to the `masters/` subfolder.
