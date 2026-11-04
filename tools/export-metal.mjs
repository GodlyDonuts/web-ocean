// One-time shader migration tool. The shipped app builds from macos/Shaders/*.metal.
import fs from 'node:fs';
import { execFileSync } from 'node:child_process';
import * as sim from '../js/wgsl/sim.js';
import * as sky from '../js/wgsl/sky.js';
import * as ocean from '../js/wgsl/ocean.js';
import * as post from '../js/wgsl/post.js';
const shaders = { ...sim, ...sky, ...ocean, ...post };
const names = ['SIM_INIT','SIM_EVOLVE','FFT_ROWS','FFT_COLS','SIM_MIPS','FOAM_TEX','RGBA8_MIPS','FOAM_UPDATE','ARRAY16_MIPS','TRANS_LUT','MS_LUT','SKYVIEW_LUT','ENV_CUBE','CUBE_MIPS','SUN_VIS','SKY_BG','SKY_CACHED','OCEAN','BLOOM_DOWN','BLOOM_UP','COMPOSITE'];
fs.mkdirSync('macos/build/port', { recursive: true });
const outputDirectory = 'macos/build/migrated-shaders';
fs.mkdirSync(outputDirectory, { recursive: true });
const manifest = {};
for (const name of names) {
  let code = shaders[name];
  if (name === 'OCEAN') {
    const start = code.indexOf('@vertex fn vs(');
    const end = code.indexOf('\nfn fresnelWater', start);
    code = code.slice(0, start) + `
// Project a guard-banded screen grid onto the ocean plane. No world quadtree.
@vertex fn vs(@builtin(vertex_index) vi: u32) -> VSOut {
  let columns = u32(F.lodP.x);
  let rows = u32(F.lodP.y);
  let grid = vec2f(f32(vi % (columns + 1u)) / f32(columns), f32(vi / (columns + 1u)) / f32(rows));
  let horizon = -F.camFwd.y / F.camUp.y;
  // Put most vertices in the viewport, with a sparse guard region for wave
  // displacement. The nearest waves can move much farther than 15% onscreen.
  var sx: f32;
  if (grid.x < 0.04) { sx = mix(-3.0, -1.15, grid.x / 0.04); }
  else if (grid.x > 0.96) { sx = mix(1.15, 3.0, (grid.x - 0.96) / 0.04); }
  else { sx = mix(-1.15, 1.15, (grid.x - 0.04) / 0.92); }
  var sy: f32;
  if (grid.y < 0.05) { sy = mix(-4.0, -1.15, grid.y / 0.05); }
  else { sy = mix(-1.15, horizon - 0.00008, (grid.y - 0.05) / 0.95); }
  let ndc = vec2f(sx, sy);
  let ray = F.camFwd.xyz + ndc.x * F.camRight.xyz + ndc.y * F.camUp.xyz;
  let t = min(160000.0, F.camPos.y / max(-ray.y, 0.00001));
  let xz = F.camPos.xz + ray.xz * t;
  let dx = select(2.3 / 0.92, 1.85 / 0.04, grid.x < 0.04 || grid.x > 0.96);
  let dy = select((horizon + 1.15) / 0.95, 2.85 / 0.05, grid.y < 0.05);
  let spacingX = t * dx * length(F.camRight.xyz) / f32(columns);
  let spacingY = t * abs(dy * F.camUp.y / max(-ray.y, 0.00001)) / f32(rows);
  let spacing = max(spacingX, min(spacingY, 3000.0));
  var disp = vec3f(0.0);
  for (var c = 0u; c < 6u; c++) {
    let lod = log2(max(spacing * TEX_N * F.cascInvL[c >> 2u][c & 3u], 1.0));
    if (lod < 8.0) {
      let uv = xz * F.cascInvL[c >> 2u][c & 3u];
      var wave = textureSampleLevel(dispTex, sampR, uv, c, lod);
      if (c < 2u && lod < 1.0) { wave = mix(cubicWave(dispTex, uv, c), wave, smoothstep(0.0, 1.0, lod)); }
      disp += wave.xyz;
    }
  }
  var o: VSOut;
  o.rel = vec3f(xz.x + disp.x, disp.y, xz.y + disp.z) - F.camPos.xyz;
  o.pos = F.viewProj * vec4f(o.rel, 1.0);
  o.xz = xz;
  o.height = disp.y;
  return o;
}
` + code.slice(end);
  }
  if (name === 'FOAM_UPDATE') {
    code = code.replace('  var jxx = 0.0;', `  // Skip foam behind the fixed camera and outside its horizontal guard band.
  if (p.y > 16.0 || abs(p.x) > 16.0 + max(-p.y, 0.0) * U.p1.w) {
    textureStore(dst, id.xy, lvl, vec4f(0.0));
    return;
  }
  var jxx = 0.0;`);
  }
  const input = `macos/build/port/${name}.wgsl`;
  const output = `${outputDirectory}/${name}.metal`;
  fs.writeFileSync(input, code);
  const functions = execFileSync('tools/wgsl-to-metal/target/release/ocean-wgsl-to-metal', [input, output], { encoding: 'utf8' }).trim().split('\n');
  // Give workgroup arrays static storage inside each native kernel.
  let metal = fs.readFileSync(output, 'utf8');
  metal = metal.replace(/(kernel void main_\([\s\S]*?)(\) \{)/g, (whole, signature, opening) => {
    const shared = [];
    signature = signature.replace(/, threadgroup (\w+)& (\w+)\n/g, (_, type, variable) => {
      shared.push(`    threadgroup ${type} ${variable};`);
      return '';
    });
    return signature + opening + '\n' + shared.join('\n');
  });
  fs.writeFileSync(output, metal);
  manifest[name] = functions;
  console.log(name, functions.join(', '));
}
fs.writeFileSync(`${outputDirectory}/manifest.json`, JSON.stringify(manifest, null, 2)+'\n');
