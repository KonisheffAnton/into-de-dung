"use strict";

function pointOnSegment(x, y, a, b) {
  const cross = (x - a[0]) * (b[1] - a[1]) - (y - a[1]) * (b[0] - a[0]);
  if (Math.abs(cross) > 1e-8) return false;
  const dot = (x - a[0]) * (b[0] - a[0]) + (y - a[1]) * (b[1] - a[1]);
  if (dot < -1e-8) return false;
  const lengthSquared = (b[0] - a[0]) ** 2 + (b[1] - a[1]) ** 2;
  return dot <= lengthSquared + 1e-8;
}

function pointInPolygon(x, y, polygon) {
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    const a = polygon[j];
    const b = polygon[i];
    if (pointOnSegment(x, y, a, b)) return true;
    const crosses = (a[1] > y) !== (b[1] > y) &&
      x < ((b[0] - a[0]) * (y - a[1])) / (b[1] - a[1]) + a[0];
    if (crosses) inside = !inside;
  }
  return inside;
}

function maskContains(mask, x, y) {
  const index = y * 256 + x;
  return (mask[index >> 3] & (1 << (index & 7))) !== 0;
}

function actorContains(actor, x, y, mask) {
  const [sx, sy, sw, sh] = actor.source;
  const [dx, dy, dw, dh] = actor.destination;
  if (x < dx || y < dy || x >= dx + dw || y >= dy + dh) return false;
  let localX = Math.floor((x - dx) / dw * sw);
  const localY = Math.floor((y - dy) / dh * sh);
  if (actor.flipX) localX = sw - 1 - localX;
  return maskContains(mask, sx + localX, sy + localY);
}

function hitTest(actors, x, y, masksByGroup, framesByGroup, foregroundZ, occlusionPolygons) {
  const topFirst = actors.slice().sort((left, right) => right.z - left.z);
  for (const actor of topFirst) {
    const frameMasks = masksByGroup[actor.group];
    const frameIndex = framesByGroup[actor.group] || 0;
    const mask = frameMasks && frameMasks[frameIndex];
    if (!mask || !actorContains(actor, x, y, mask)) continue;
    if (actor.z < foregroundZ && occlusionPolygons.some((polygon) => pointInPolygon(x, y, polygon))) continue;
    return actor;
  }
  return null;
}

const DioramaInteraction = { pointInPolygon, maskContains, actorContains, hitTest };
if (typeof window !== "undefined") window.DioramaInteraction = DioramaInteraction;
if (typeof module !== "undefined" && module.exports) module.exports = DioramaInteraction;
