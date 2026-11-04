#!/usr/bin/env node
// Execute the repository's ACTUAL CDLOD and camera-matrix functions in Node.
// This extracts unchanged JS source; it does not port the algorithm to another
// language. WebGPU uploads are replaced by a no-op. No GPU timing is measured.
//
// Usage:
// node validate-cdlod-count.mjs --source /path/to/web-ocean/js/main.js \
//   --output /path/to/cdlod_actual_js.json [--commit COMMIT_LABEL]

import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const args = new Map();
for (let i = 2; i < process.argv.length; i += 2) {
  if (!process.argv[i].startsWith('--') || process.argv[i + 1] === undefined) {
    throw new Error('Expected --source PATH, optional --output PATH and --commit LABEL');
  }
  args.set(process.argv[i], process.argv[i + 1]);
}
const here = path.dirname(fileURLToPath(import.meta.url));
const sourcePath = path.resolve(args.get('--source') || path.join(here, '../../web-ocean/js/main.js'));
const commonPath = path.join(path.dirname(sourcePath), 'wgsl/common.js');
const main = fs.readFileSync(sourcePath, 'utf8');
const common = fs.readFileSync(commonPath, 'utf8');
const sha256 = text => crypto.createHash('sha256').update(text).digest('hex');
const extracted = [];

function record(file, text, start, end, name) {
  const code = text.slice(start, end);
  extracted.push({ name, file, firstLine: text.slice(0, start).split('\n').length,
    lastLine: text.slice(0, end).split('\n').length,
    sha256: sha256(code) });
  return code;
}

function statement(name, text = main, file = 'js/main.js') {
  // The requested declarations are single-line statements in this source.
  const re = new RegExp(`^[ \\t]*(?:export )?(?:const|let) ${name}\\b[^\\n]*;`, 'm');
  const match = re.exec(text);
  if (!match) throw new Error(`Cannot find single-line declaration: ${name}`);
  return record(file, text, match.index, match.index + match[0].length, name)
    .replace(/\bexport\s+/, '');
}

function functionSource(name) {
  // An outer closing brace has exactly the same indentation as its function.
  // This intentionally fails for a changed source layout rather than silently
  // substituting a separately implemented version of the algorithm.
  const startRE = new RegExp(`^([ \\t]*)function ${name}\\([^\\n]*\\) \\{`, 'm');
  const start = startRE.exec(main);
  if (!start) throw new Error(`Cannot find function: ${name}`);
  const closingRE = new RegExp(`^${start[1]}\\}`, 'gm');
  closingRE.lastIndex = start.index + start[0].length;
  const end = closingRE.exec(main);
  if (!end) throw new Error(`Cannot find outer closing brace: ${name}`);
  const code = record('js/main.js', main, start.index, end.index + end[0].length, name);
  new vm.Script(`(${code})`); // Reject an extraction that is not a whole function.
  return code;
}

const pStart = main.indexOf('export const P = {');
const pEnd = main.indexOf('\n};', pStart);
if (pStart < 0 || pEnd < 0) throw new Error('Cannot locate default parameter object P');
const pSource = record('js/main.js', main, pStart, pEnd + 3, 'P').replace('export ', '');

const declarations = [pSource, statement('D2R'), statement('CASC_L'),
  statement('CASCADES', common, 'js/wgsl/common.js'), statement('C'),
  ...['GRID', 'LEAF', 'R0', 'LODS', 'MAX_DIST', 'MAX_NODES', 'HB', 'XB',
      'FOAM_LEVEL_SIZE', 'cam', 'instData', 'frameF', 'proj', 'ranges', 'planes',
      'nodeCount'].map(name => statement(name))];
const rangeInit = main.match(/^[ \t]*for \(let l = 0; l < LODS; l\+\+\) ranges\[l\] = [^\n]*;/m);
if (!rangeInit) throw new Error('Cannot find LOD range initialization');
declarations.push(record('js/main.js', main, rangeInit.index,
  rangeInit.index + rangeInit[0].length, 'ranges initialization'));

const functions = ['mat4Mul', 'writeFrame', 'sphereHit', 'inFrustum',
  'addNode', 'selectNode', 'selectAll'].map(functionSource);
const code = `
  'use strict';
  ${declarations.join('\n')}
  ${functions.join('\n')}
  const DBG = 0, frameIndex = 0, frameUBO = {};
  const device = { queue: { writeBuffer() {} } };
  let W = 0, H = 0;
  globalThis.evaluateViewport = (width, height) => {
    W = width; H = height;
    writeFrame(0);
    selectAll();
    const lodCounts = Object.fromEntries(Array.from({ length: LODS }, (_, lod) => [lod, 0]));
    for (let i = 0; i < nodeCount; i++) lodCounts[instData[i * 4 + 3]]++;
    return {
      viewport: [W, H], aspect: W / H,
      camera: { position_m: [cam.x, cam.y, cam.z], yaw_deg: cam.yaw / D2R,
        pitch_deg: cam.pitch / D2R, fovy_deg: cam.fovY / D2R },
      selected_nodes: nodeCount, nodes_by_lod: lodCounts,
      triangles_per_grid_instance: GRID * GRID * 2,
      submitted_triangles: nodeCount * GRID * GRID * 2,
      sum_of_unique_vertex_indices_per_instance: nodeCount * (GRID + 1) ** 2,
      node_capacity: MAX_NODES, node_capacity_reached: nodeCount === MAX_NODES,
      grid_quads_per_axis: GRID, lod_levels: LODS,
      max_distance_m: MAX_DIST
    };
  };
`;
const context = vm.createContext({});
new vm.Script(code, { filename: 'actual-repository-cdlod-extract.js' }).runInContext(context);
const results = [[2560, 1440], [2560, 1600]].map(([w, h]) =>
  vm.runInContext(`evaluateViewport(${w}, ${h})`, context));
const output = {
  classification: 'Actual repository JavaScript functions executed unchanged on CPU; not a GPU benchmark',
  upstream_commit_label: args.get('--commit') || null,
  source_files: { main: sourcePath, common: commonPath },
  source_sha256: { main: sha256(main), common: sha256(common) },
  extraction: extracted,
  results,
  interpretation: [
    'Default camera, default settings, and no user movement; no URL overrides.',
    'The repository\'s Float32Array matrices and Float64Array culling planes are preserved.',
    'Only the WebGPU uniform upload is stubbed out.',
    'Triangle counts are submitted index/instance work before GPU clipping, culling, and rasterization.',
    'Unique vertex-index count is not a measured number of vertex-shader invocations.',
    'Counts do not establish frame time, power use, or the speedup of any alternative geometry.'
  ]
};
const json = JSON.stringify(output, null, 2) + '\n';
if (args.has('--output')) {
  const outputPath = path.resolve(args.get('--output'));
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, json);
}
process.stdout.write(json);
