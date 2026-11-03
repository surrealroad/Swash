#!/usr/bin/env node
// Generates Swash/Markdown/FormatManifest.generated.swift from the format-command manifest in
// @pixerate/markdown-conformance (node_modules). The generated file is committed, so Xcode
// builds never need Node. CI regenerates it and fails when the committed copy is stale.
//
// Fails when the manifest uses a surface or `enabledWhen` condition that Swash doesn't
// implement (the cases of FormatSurface / FormatCondition in FormatManifest.swift), or a
// command id that FormatCommand(manifestID:) doesn't map.
//
//   node scripts/generate_format_manifest.mjs            write the Swift file
//   node scripts/generate_format_manifest.mjs --check    exit 1 if the Swift file is stale

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const packageDir = join(root, 'node_modules/@pixerate/markdown-conformance');
const manifestPath = join(packageDir, 'manifest.json');
const outputPath = join(root, 'Swash/Markdown/FormatManifest.generated.swift');
const typesPath = join(root, 'Swash/Markdown/FormatManifest.swift');
const commandPath = join(root, 'Swash/Markdown/FormatCommand.swift');

const errors = [];
const fail = (message) => errors.push(message);

if (!existsSync(manifestPath)) {
  console.error(`error: ${manifestPath} not found. Run \`npm ci\` first.`);
  process.exit(1);
}
const manifest = JSON.parse(readFileSync(manifestPath, 'utf8'));
const packageVersion = JSON.parse(readFileSync(join(packageDir, 'package.json'), 'utf8')).version;

/** The `case` names of a Swift enum in `source`. */
function enumCases(source, name) {
  const match = source.match(new RegExp(`enum ${name}\\b[^{]*\\{([\\s\\S]*?)\\n\\}`));
  if (!match) throw new Error(`enum ${name} not found`);
  return new Set([...match[1].matchAll(/^\s*case\s+(\w+)/gm)].map((m) => m[1]));
}

const types = readFileSync(typesPath, 'utf8');
const surfaces = enumCases(types, 'FormatSurface');
const conditions = enumCases(types, 'FormatCondition');
const mappedIDs = new Set([...readFileSync(commandPath, 'utf8').matchAll(/case "(format\.\w+)"/g)].map((m) => m[1]));

const swiftString = (value) =>
  '"' + String(value).replace(/\\/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n') + '"';

const modifierNames = { Mod: '.command', Cmd: '.command', Shift: '.shift', Alt: '.option', Option: '.option', Ctrl: '.control' };

/** `Mod+Shift+8` → a FormatShortcut initializer. */
function shortcut(chord, where) {
  const parts = chord.split('+');
  const key = parts.pop();
  if (!key || [...key].length !== 1) {
    fail(`${where}: shortcut "${chord}" must end in a single key`);
    return 'nil';
  }
  const modifiers = [];
  for (const part of parts) {
    const swift = modifierNames[part];
    if (!swift) fail(`${where}: unknown modifier "${part}" in "${chord}"`);
    else modifiers.push(swift);
  }
  if (!modifiers.includes('.command')) fail(`${where}: shortcut "${chord}" has no Mod key`);
  return `FormatShortcut(key: ${swiftString(key.toLowerCase())}, modifiers: [${modifiers.join(', ')}], chord: ${swiftString(chord)})`;
}

/** A parameter value, typed by the command's params schema. */
function paramValue(command, name, raw) {
  const type = command.params?.properties?.[name]?.type;
  const types = Array.isArray(type) ? type : [type];
  if (raw === 'null' && types.includes('null')) return '.null';
  if (types.includes('integer')) {
    if (!/^-?\d+$/.test(raw)) fail(`${command.id}: "${name}=${raw}" is not an integer`);
    return `.int(${raw})`;
  }
  if (types.includes('boolean') && (raw === 'true' || raw === 'false')) return `.bool(${raw})`;
  if (!command.params?.properties?.[name]) fail(`${command.id}: shortcut parameter "${name}" is not in its params schema`);
  return `.string(${swiftString(raw)})`;
}

const commandLines = manifest.commands.map((command) => {
  const where = command.id;
  if (!mappedIDs.has(command.id)) fail(`${where}: FormatCommand(manifestID:) has no case for this id`);
  for (const surface of command.surfaces) {
    if (!surfaces.has(surface)) fail(`${where}: surface "${surface}" is not a FormatSurface case`);
  }
  for (const condition of command.enabledWhen ?? []) {
    if (!conditions.has(condition)) fail(`${where}: enabledWhen "${condition}" is not implemented (add it to FormatCondition and MarkdownFormatting.satisfies)`);
  }
  const variants = Object.entries(command.shortcuts ?? {}).map(([selector, chord]) => {
    const params = selector.split(',').map((pair) => {
      const [name, raw] = pair.split('=');
      if (raw === undefined) fail(`${where}: shortcut selector "${selector}" must be name=value`);
      return [name, raw ?? ''];
    });
    const swiftParams = params.map(([name, raw]) => `${swiftString(name)}: ${paramValue(command, name, raw)}`).join(', ');
    const label = [command.label, ...params.map(([, raw]) => raw)].join(' ');
    return `                FormatCommandVariant(params: [${swiftParams}], label: ${swiftString(label)}, shortcut: ${shortcut(chord, where)}),`;
  });
  return [
    '        FormatCommandDefinition(',
    `            id: ${swiftString(command.id)},`,
    `            label: ${swiftString(command.label)},`,
    `            group: ${swiftString(command.group)},`,
    `            surfaces: [${command.surfaces.map((s) => '.' + s).join(', ')}],`,
    `            enabledWhen: [${(command.enabledWhen ?? []).map((c) => '.' + c).join(', ')}],`,
    `            shortcut: ${command.shortcut ? shortcut(command.shortcut, where) : 'nil'},`,
    variants.length ? `            variants: [\n${variants.join('\n')}\n            ]` : '            variants: []',
    '        ),',
  ].join('\n');
});

const languageLines = manifest.codeLanguages.map(
  (language) =>
    `        CodeLanguage(id: ${swiftString(language.id)}, label: ${swiftString(language.label)}, shortLabel: ${
      language.shortLabel ? swiftString(language.shortLabel) : 'nil'
    }),`
);

if (errors.length) {
  for (const message of errors) console.error(`error: ${message}`);
  process.exit(1);
}

const output = `// DO NOT EDIT. Generated by scripts/generate_format_manifest.mjs from
// @pixerate/markdown-conformance ${packageVersion} (manifest.json).
// To change it, bump the package in package.json, run \`npm ci\`, then
// \`node scripts/generate_format_manifest.mjs\`.

import Foundation

enum FormatManifest {
    /// The package version this file was generated from.
    static let version = ${swiftString(packageVersion)}

    static let commands: [FormatCommandDefinition] = [
${commandLines.join('\n')}
    ]

    static let codeLanguages: [CodeLanguage] = [
${languageLines.join('\n')}
    ]
}
`;

if (process.argv.includes('--check')) {
  const current = existsSync(outputPath) ? readFileSync(outputPath, 'utf8') : '';
  if (current !== output) {
    console.error(`error: ${outputPath} is stale. Run \`node scripts/generate_format_manifest.mjs\` and commit it.`);
    process.exit(1);
  }
  console.log('FormatManifest.generated.swift is up to date.');
} else {
  writeFileSync(outputPath, output);
  console.log(`Wrote ${outputPath} (${manifest.commands.length} commands, ${manifest.codeLanguages.length} languages).`);
}
