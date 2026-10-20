import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const tokens = readFileSync(new URL('../../EXP [design]/UI/DesignTokens.swift', import.meta.url), 'utf8');
const glass = readFileSync(new URL('../../EXP [design]/UI/GlassSurface.swift', import.meta.url), 'utf8');
const css = readFileSync(new URL('../../design/EXP [design] Design System/tokens/colors.css', import.meta.url), 'utf8');
function token(name) {
  const match = tokens.match(new RegExp(`static (?:var|let) ${name}:\\s*(?:Color|NSColor) \\{ dyn(?:NS)?\\(0x([\\dA-Fa-f]+), ([\\d.]+), 0x([\\dA-Fa-f]+), ([\\d.]+)\\)`));
  assert.ok(match, `Read the actual ${name} color definition`);
  return [[parseInt(match[1], 16), +match[2]], [parseInt(match[3], 16), +match[4]]];
}
const rgb = hex => [hex >> 16 & 255, hex >> 8 & 255, hex & 255].map(v => v / 255);
const over = (front, alpha, back) => front.map((v, i) => v * alpha + back[i] * (1 - alpha));
function luminance(color) {
  return color.map(v => v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4)
    .reduce((sum, v, i) => sum + v * [0.2126, 0.7152, 0.0722][i], 0);
}
const ratio = (a, b) => (Math.max(luminance(a), luminance(b)) + 0.05) / (Math.min(luminance(a), luminance(b)) + 0.05);

test('native text alpha matches the canonical design tokens in dark, light and forced-light scopes', () => {
  for (const tier of ['secondary', 'tertiary', 'quaternary']) {
    const values = [...css.matchAll(new RegExp(`--text-${tier}:\\s*rgba\\([^,]+,[^,]+,[^,]+,\\s*([\\d.]+)\\)`, 'g'))].map(match => +match[1]);
    const native = token(`text${tier[0].toUpperCase()}${tier.slice(1)}`);
    assert.deepEqual(values, [native[0][1], native[1][1], native[1][1]]);
  }
});

test('small chrome text clears 4.5:1 over bounded window glass and solid chrome in both appearances', () => {
  const alpha = +glass.match(/\.overlay\(EXPColor\.surfacePanelSolid\.opacity\(([\d.]+)\)\)/)?.[1];
  assert.ok(alpha > 0 && alpha <= 1, 'Read the actual wallpaper bound');
  for (let appearance = 0; appearance < 2; appearance++) {
    const plate = rgb(token('surfacePanelSolidNS')[appearance][0]);
    // Include saturated wallpapers, not only black/white, before text compositing.
    const backgrounds = Array.from({ length: 8 }, (_, n) => over(plate, alpha, [n & 1, n >> 1 & 1, n >> 2 & 1]));
    for (const name of ['n0', 'n50', 'n100', 'n150', 'n200', 'n300', 'n400', 'n500']) {
      backgrounds.push(rgb(token(name)[appearance][0]));
    }
    for (const name of ['textPrimary', 'textSecondary', 'textTertiary', 'textQuaternary']) {
      const [hex, opacity] = token(name)[appearance];
      for (const background of backgrounds) {
        const contrast = ratio(over(rgb(hex), opacity, background), background);
        assert.ok(contrast >= 4.5, `${name}, appearance ${appearance}: ${contrast.toFixed(3)}:1`);
      }
    }
  }
});
