#version 460 core

// A pane of liquid glass laid over the backdrop: a light frost in the middle, and towards the
// rim a lens that pulls in what lies beyond the edge, splits it faintly by colour and catches a
// highlight. Everything is in physical pixels of the screen.

#include <flutter/runtime_effect.glsl>

precision highp float;

// Set by the engine: the size of the backdrop texture.
uniform vec2 uTexSize;
// The clipped pane, as x, y, width, height.
uniform vec4 uPane;
// The lens shape (the pane, pushed out past any edge that should not bend).
uniform vec4 uShape;
uniform float uRadius;
// Width of the rim band that bends, and how far its outer edge reaches out.
uniform float uBezel;
uniform float uRefraction;
uniform float uDispersion;
uniform float uBlur;
uniform float uSaturation;
uniform float uHighlight;
uniform vec2 uLight;

uniform sampler2D uTexture;

out vec4 fragColor;

float roundedBox(vec2 p, vec2 halfSize, float r) {
  vec2 q = abs(p) - halfSize + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float shapeDistance(vec2 p) {
  vec2 halfSize = uShape.zw * 0.5;
  return roundedBox(p - (uShape.xy + halfSize), halfSize, min(uRadius, min(halfSize.x, halfSize.y)));
}

// The backdrop is either the whole screen or just the pane's bounds, depending on the backend;
// [shift] is where the texture's origin sits on screen.
vec3 sampleAt(vec2 screen, vec2 shift) {
  vec2 uv = clamp((screen - shift) / uTexSize, vec2(0.0), vec2(1.0));
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uTexture, uv).rgb;
}

vec3 frosted(vec2 screen, vec2 shift) {
  if (uBlur < 0.5) return sampleAt(screen, shift);
  float r = uBlur;
  vec3 sum = sampleAt(screen, shift) * 0.2;
  sum += sampleAt(screen + vec2(r, 0.0), shift) * 0.1;
  sum += sampleAt(screen - vec2(r, 0.0), shift) * 0.1;
  sum += sampleAt(screen + vec2(0.0, r), shift) * 0.1;
  sum += sampleAt(screen - vec2(0.0, r), shift) * 0.1;
  float d = r * 0.7071;
  sum += sampleAt(screen + vec2(d, d), shift) * 0.1;
  sum += sampleAt(screen + vec2(-d, d), shift) * 0.1;
  sum += sampleAt(screen + vec2(d, -d), shift) * 0.1;
  sum += sampleAt(screen + vec2(-d, -d), shift) * 0.1;
  return sum;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  bool paneSized = abs(uTexSize.x - uPane.z) < 3.0 && abs(uTexSize.y - uPane.w) < 3.0;
  vec2 shift = paneSized ? uPane.xy : vec2(0.0);
  vec2 p = frag + shift;

  float d = shapeDistance(p);
  if (d > 0.0) {
    fragColor = vec4(sampleAt(p, shift), 1.0);
    return;
  }

  // 1 on the rim, falling to 0 a bezel in: a rounded lip, steep at the very edge.
  float rim = clamp(1.0 + d / max(uBezel, 1.0), 0.0, 1.0);
  float lens = rim * rim * rim;

  float e = 1.0;
  vec2 grad = vec2(
    shapeDistance(p + vec2(e, 0.0)) - shapeDistance(p - vec2(e, 0.0)),
    shapeDistance(p + vec2(0.0, e)) - shapeDistance(p - vec2(0.0, e))
  );
  vec2 normal = length(grad) > 1e-4 ? normalize(grad) : vec2(0.0);

  vec2 bend = normal * uRefraction * lens;
  vec3 color;
  if (uDispersion > 0.001 && lens > 0.002) {
    color = vec3(
      frosted(p + bend * (1.0 + uDispersion), shift).r,
      frosted(p + bend, shift).g,
      frosted(p + bend * (1.0 - uDispersion), shift).b
    );
  } else {
    color = frosted(p + bend, shift);
  }

  float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
  color = mix(vec3(luma), color, uSaturation);

  // A highlight on the lit side of the lip and a fainter one opposite, plus a hairline rim.
  float facing = dot(normal, uLight);
  float sheen = pow(rim, 5.0) * (max(facing, 0.0) + 0.35 * max(-facing, 0.0));
  float hairline = smoothstep(-1.6, 0.0, d);
  color += vec3(uHighlight * (0.55 * sheen + 0.22 * hairline));

  fragColor = vec4(clamp(color, 0.0, 1.0), 1.0);
}
