# Re-exporting the muscle layer from Blender (per-muscle names)

The 3D body map resolves marking strokes to anatomical muscle groups by
hit-testing an **invisible muscle proxy** mesh (`Resources/Models3D/BodyMuscle.obj`)
loaded alongside the visible skin. Each muscle must arrive as its own **named
object** (`o Biceps brachii.l`, `o Rectus femoris.r`, …) so
`MuscleNameResolver` can map it to a `MuscleGroup`.

The current `BodyMuscle.obj` is a single **merged** object (`o AnatomyExport`).
It still loads and aligns, but resolves to no muscle names — so marking falls
back to a coarse position heuristic (head / hands / feet + nearest group by
height) and marked muscles do **not** glow. Dropping in a per-muscle re-export
turns full accuracy on with **no code change**.

---

## Export steps (Z-Anatomy `.blend`)

1. Open the Z-Anatomy Blender file.
2. In the Outliner, select the **muscular-system collection** (all the muscle
   objects). Do **not** join them — each object stays separate so it keeps its
   name.
3. `File ▸ Export ▸ Wavefront (.obj)`.
4. In the export sidebar (right side of the file dialog):
   - **Limit to ▸ Selected Only**: **ON**
   - **Objects ▸ OBJ Objects**: **ON** (writes each object as its own `o`
     block — this is what preserves per-muscle names)
   - **Objects ▸ OBJ Groups**: optional (leave off)
   - **Geometry ▸ Apply Modifiers**: **ON**
   - **Geometry ▸ Triangulated Mesh**: **ON**
   - **Transform ▸ Forward Axis**: **−Z**
   - **Transform ▸ Up Axis**: **Y**
   (Forward −Z / Up Y matches the previous export; the app re-normalises scale
   and centre anyway, so exact scale doesn't matter — but axes must match so the
   proxy lines up with the skin.)
5. Export as `BodyMuscle.obj`.

> **Do not** enable any "Join Objects" / "Merge" option, and do not join in the
> viewport first. A merged mesh exports as a single `o` block and defeats name
> resolution.

---

## Decimate first (keep it under ~8 MB)

The raw muscular system is large. Before exporting, decimate so the shipped OBJ
stays small (the proxy is never drawn, so heavy geometry is pure waste):

- Select all muscle objects, add a **Decimate** modifier (Collapse) with ratio
  **≈ 0.1**, and **Apply** it — or use Blender's batch/"copy modifier to
  selected" to apply the same ratio across every object.
- Target total file size **< 8 MB**. The current merged export is ~3 MB; a
  decimated per-muscle export in the same ballpark is fine.

---

## Verify the export

```sh
grep -c "^o " Resources/Models3D/BodyMuscle.obj
```

- **Hundreds** → success (one `o` line per muscle object). Full accuracy.
- **1** → still merged; the export options were wrong. Redo with *OBJ Objects*
  ON and no join.

You can spot-check names too:

```sh
grep "^o " Resources/Models3D/BodyMuscle.obj | head
```

Expect Latin/English muscle names, usually with `.l` / `.r` (or `_L` / `_R`)
side suffixes — e.g. `o Gastrocnemius.l`, `o Rectus abdominis`. These are exactly
what `MuscleNameResolver`'s keyword table matches (see
`Views/BodyMap/MuscleNameResolver.swift`); add a keyword there if a muscle name
isn't recognised.

---

## Where it goes

Replace the file at:

```
Breath - Relax & Stretch/Resources/Models3D/BodyMuscle.obj
```

It's inside a synchronized file group, so Xcode picks it up automatically — no
project changes, **no code changes**. Rebuild and run; marking now resolves to
real muscles and the x-ray glow appears on the correct anatomy at every
rotation.

---

## Left/right convention (one-time check)

Our vocabulary is **screen-relative** ("Left" = the viewer's left when the
figure faces front), matching the exercise seed data — while Blender's `.l`
suffix is **anatomical left** (the figure's own left = screen right at front).
`MuscleNameResolver.group(forNodeName:localX:)` already swaps for this. After
the named export lands, verify once: temporarily set the proxy material's
`transparency` to `0.4` in `BodyRig.applyProxyMaterial`, run, screenshot the
front view, and confirm a `.l`-suffixed muscle renders on the viewer's **right**.
If it's flipped, adjust the side-swap in `MuscleNameResolver`, then revert the
transparency.
