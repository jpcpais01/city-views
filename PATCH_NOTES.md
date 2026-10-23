# City Views patch notes

## 2026-10-23 19:00 UTC
- The lighthouse beam now shows out over the sea, not only where it crosses land. It is a softer, brighter double cone that leans down towards the water.
- As the beam sweeps, it lights up whatever it passes over: a glittering path across the waves, the grass, the sand and the buildings.
- Seagulls are rebuilt: grey wings with black tips, white undersides, a hooked yellow beak and pink feet. Their wings bend at the shoulder and the elbow, so they glide in the classic gull "M" shape and beat their wings properly.
- Gulls now soar in circles, fly off somewhere new, dive into the sea for fish, and come down to stand on the beach or bob on the water before flapping off again. They rest more at night.
- Gulls call out as they fly near you, sometimes in a laughing run of cries.

## 2026-10-23 18:30 UTC
- Every new version now comes with a Windows download too: grab CityViews-Windows.zip from the release, unzip it and run CityViews.exe.

## 2026-10-23 18:30 UTC
- City goals: three goals at a time, picked to fit your town, such as growing to the next size, trying a newly unlocked building, opening a café on the seafront or making everyone happier.
- Finish a goal and its Collect button lights up. Tap it to send a shower of coins into your purse and get a fresh goal. Tap the panel's header to fold it away.
- Tip bubbles: every so often a happy home floats a heart, or a shop or office floats a coin. Tap it for a thank-you bonus. They work while building too, and fade away if you leave them.

## 2026-10-23 18:00 UTC
- New build bar: Roads, Homes, Shops, Work, Parks, Nature, Landmarks, Land and Clear. Tap a category to pick from its types, each with its own price and perks.
- 22 new things to build. Roads come as streets, tree-lined avenues and cobbled lanes. Homes come as cottages, row houses, villas and apartments. Shops come as corner shops, cafés, markets and department stores. Work comes as office towers, studios and seaside hotels.
- Parks now include playgrounds, ponds, plazas and sports fields. Nature includes oak woods, pines, palms, cherry blossom and wildflower meadows. Three new landmarks: a bandstand, a pier out over the sea, and an observatory.
- Buildings react to where they stand. Corner plots grow side wings and wrap shopfronts round the corner. Row houses alternate colours, and neighbouring ponds, plazas, markets and pitches join into one. Palms lean out to sea, pines grow taller on hills, and each district has its own wall and roof colours.
- Every home gets its own front and back garden, such as a shed, a swing, a washing line or a vegetable patch. A town that mixes every type still stays under 100k triangles.

## 2026-10-23 17:00 UTC
- The regular grid of light blotches on the open sea is gone. Sunlight on the wave crests now shows as scattered, drifting glints instead of a repeating pattern.
- Shadows no longer fade out when you zoom out: buildings, trees and clouds keep their shadows at every zoom level.
- Clouds no longer cast grey shadows onto themselves.
- On Windows, City Views now has its own sunset-skyline icon on the .exe, the taskbar and the window, instead of the Godot logo.

## 2026-10-23 16:00 UTC
- City Views now runs on Windows PCs. Builds are made on request and posted next to the Android download.
- Keyboard and mouse controls on PC: WASD or arrow keys move around (hold Shift to go faster), Q and E rotate, R/F or +/- zoom, the mouse wheel zooms, right-drag rotates and middle-drag pans. F11 or Alt+Enter toggles fullscreen.

## 2026-10-23 15:00 UTC
- Sea foam now follows the real, curving shoreline instead of tile squares, and the little gaps where water showed through the beach are gone.
- Trees have leafy, lobed outlines, clumps of light and shade, and bark that darkens towards the ground. Hedges and roof gardens get the same leafy look.
- More detail everywhere at no extra cost: meadows drift between lush and dry patches across tiles, the ground has fine grain up close, roofs show rows of tiles, and walls and roads have a subtle texture.
- Placing things is smooth again: each placement does about a seventh of the work it did, and neighbouring tiles catch up over the next few frames.
- In landscape, the HUD and menus stay 3% in from the left and right edges, while the island still fills the whole screen.

## 2026-10-23 14:00 UTC
- The whole island now draws in under 100k triangles (it was over 400k) and looks the same: trees, trunks, posts and clouds are perfectly round sprites, shadows use simple stand-in shapes, and each row of windows is a single piece.
- Hills and coasts are reshaped as one smooth landscape: eroded slopes, rocky faces and soft grass lips between terraces, scree at the foot of big drops, and beaches that run down into the water. There are no more hard steps.
- Townsfolk now stroll the sidewalks, cross at the corners and stop now and then to look around. There are more of them as your town grows.
- The interface is lighter to draw too: rounded panels and icons use just enough detail to stay perfectly smooth.
- The FPS counter's triangle count now has a test behind it, so future updates can't push the game back over 100k.

## 2026-10-23 13:00 UTC
- Another big speed boost: rounded shapes use a third of the triangles with the same soft look, windows and road paint skip the shadow pass, and all the cars are drawn together.
- The ground now flows: grass and sand blend smoothly from tile to tile instead of a checkerboard, and terrace corners are rounded off.
- Cliffs and coastlines now wander naturally: open ground spills over terrace edges in soft, irregular curves like real terrain, and tiny gaps at inner corners are sealed.
- The FPS counter now also shows how many triangles are drawn each frame.
- The island comes alive: little sailboats and fishing boats roam the bays, rocking on the swell and lighting lanterns at night, while seagulls glide and flap overhead, often following where you look.

## 2026-10-23 12:15 UTC
- A new loading screen: a soft sunset in the icon's colours with drifting clouds and a slim glowing progress bar, which melts away to show your island blooming into view.
- A new app icon: a sunset waterfront of pastel towers and gabled homes, with a little sailboat on the bay. It also adapts to round, squircle and teardrop launcher shapes.
- The menu is reorganised into tabs (Island, Co-op, Account, Settings, What's new) and only shows the buttons that make sense right now, like Leave only when you're in a room.
- A tiny FPS counter sits under your city name. You can hide it in Settings.
- Big speed boost: the town is now drawn in a few large pieces instead of one per tile, the sea and glass menus are much cheaper to draw, shadows are rendered once instead of twice, and phones render the 3D at a slightly lower resolution while the interface stays sharp.

## 2026-10-23 12:00 UTC
- A brand new sea: clear turquoise shallows you can see the sand through, deep blue water further out, rolling swell, dancing caustics and foam that laps at the beach.
- Undo and Redo buttons. Undo gives back every coin a stroke cost, and Redo charges exactly the same again, never more.
- A fresh frosted-glass look: the white toolbar is gone, every tool floats as its own glass key, and the one you pick lifts up.
- Smoother, softer shadows that stay calm while you build instead of flickering.
- Gentler hills with half-height terrace steps, and two-finger rotation now turns the way your fingers do.

## 2026-10-23 11:00 UTC
- Online is live! Host your city from the menu and share the 5-letter code so up to 3 friends can build with you in real time.
- You get a cloud save automatically, and you can create an account to keep your city across phones.
- Terraces on the hills now have clearer colours, so slopes read at a glance.

## 2026-10-23 10:00 UTC
- Welcome to City Views! A hand-crafted island appears every time you start, with beaches, terraced hills and forests.
- Draw roads, then paint homes, shops and offices that face the street, join into rows and grow taller as your town thrives.
- Seaside homes get pastel walls and blue domes, hillside cottages get stone and slate, downtown sprouts glass towers.
- A full day and night cycle: windows glow, streetlamps light up, stars come out and the lighthouse beam sweeps the sea.
- Build together online with up to 3 friends, and sign in to keep your city safe in the cloud.
