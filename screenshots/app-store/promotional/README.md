# Moro App Store promotional screenshots

Each slide frames a real iPhone capture from `../<locale>/iphone/` (made by
`scripts/capture-iphone-screenshots.sh`) on a designed background with a title.
Screens 1-3 are cut from one panoramic master, screens 4-6 are independent,
screens 7-8 share a second master, and screens 9-10 are independent.

| Slide | Capture |
| --- | --- |
| 01-03 | `home-light` |
| 04 | `thread` |
| 05 | `explore` |
| 06 | `profile` |
| 07-08 | `compose` |
| 09 | `inbox` |
| 10 | `display` |

Demo content uses fictional accounts and Unsplash photos; see
`../showcase-assets/CREDITS.md`.

Render the ten 1320 x 2868 screenshots for every locale with:

```sh
node screenshots/app-store/promotional/render.mjs            # zh-Hans,en-US
node screenshots/app-store/promotional/render.mjs en-US      # one locale
```

Outputs are written to `screenshots/app-store/<locale>/promotional/`, flattened
without alpha for App Store Connect. Combined masters and a contact sheet are
written to the `masters/` subfolder.
