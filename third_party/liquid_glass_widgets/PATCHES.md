# Local patches

This directory is the pub.dev package `liquid_glass_widgets` copied in whole, so the upgrade is
"re-copy, re-apply, rebuild". Only `lib/`, `shaders/` and `pubspec.yaml` are kept: the tarball's
`example/`, `skills/`, `analysis_options.yaml`, `CHANGELOG.md` and `README.md` are not vendored, and
`ios/` plus the two licence files are byte-identical to upstream, so they are never touched on an
upgrade.

Upgrading:

```bash
curl -sSL "https://pub.dev/api/archives/liquid_glass_widgets-<version>.tar.gz" -o /tmp/lgw.tar.gz
mkdir -p /tmp/lgw && tar xzf /tmp/lgw.tar.gz -C /tmp/lgw
cd third_party/liquid_glass_widgets && rm -rf lib shaders && cp -a /tmp/lgw/lib /tmp/lgw/shaders . && cp -a /tmp/lgw/pubspec.yaml .
# re-apply the patches below, then:
diff -rq /tmp/lgw/lib lib   # only the files listed here may differ
```

`pubspec.lock` records the version, so bump it too (`flutter pub get` rewrites the entry).

## Current: 1.17.3 (2026-11-14)

### `lib/src/widgets/surfaces/tab_bar_vertical_layout.dart` — upright lens

`_lensSize` is `Size(64, 104)` rather than upstream's `Size(89.3, 86.7)`. Upstream's lens is the
iPad side rail's, which rounds to a circle; INF's side rail is dragged up and down, so the lens is an
upright capsule with its long side along the drag. Nothing else in the file is touched.

### `lib/src/engine/rendering/liquid_glass_render_object.dart` — a black edge while animating

`_recordGeometryPicture` inflates the geometry matte's bounds by a margin so the shader's
anti-aliased SDF edge has texels to land on. A matte rasterised below the screen's pixel ratio (the
`capped` path, taken while a surface's shape changes every frame) turns that margin into fewer than
two texels, the edge falls past the texture, and the shader reads beyond it — a band of black along
the side of the panel nearest the texture boundary. It showed on a menu opening out of a card, over
its lower half, and only on `premium`: `standard` draws no geometry matte.

The margin now grows with the shrink (`devicePixelRatio / matteDevicePixelRatio`). Upstream reads
`bounds.snapToPixels(devicePixelRatio).inflate(2.0)`; check whether a later release has fixed this
before re-applying, and report it upstream either way.

### Two patches that are no longer needed

Until 1.17.0 this directory also carried the materialize content channel in
`lib/src/engine/liquid_glass.dart` and the materialize settings resolution in
`lib/src/engine/liquid_glass_layer.dart`, both marked `[LOCAL PATCH]`. Upstream 1.17.3 ships both
verbatim (`GlassMaterializeScope.wrapContent` / `GlassMaterializeScope.resolveSettings`), so on an
upgrade they need no rework — check that the `GlassMaterializeScope` calls are still there and leave
them alone.
