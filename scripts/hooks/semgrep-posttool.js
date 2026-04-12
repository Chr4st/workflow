#!/usr/bin/env node
const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const DEBOUNCE_FILE = path.join(os.tmpdir(), 'semgrep-hook-debounce.json');
const DEBOUNCE_MS = 10000;

const CODE_EXTS = new Set([
  '.ts', '.tsx', '.js', '.jsx', '.mjs', '.cjs',
  '.py', '.go', '.rs', '.java', '.rb', '.php',
  '.c', '.cpp', '.h', '.hpp', '.cs', '.swift', '.kt'
]);

const SKIP_DIRS = ['node_modules', 'dist', '.next', 'build', '__pycache__', '.git', 'vendor'];

function isDebounced(key) {
  try {
    if (!fs.existsSync(DEBOUNCE_FILE)) return false;
    const data = JSON.parse(fs.readFileSync(DEBOUNCE_FILE, 'utf8'));
    return data[key] && (Date.now() - data[key]) < DEBOUNCE_MS;
  } catch { return false; }
}

function setDebounce(key) {
  let data = {};
  try { data = JSON.parse(fs.readFileSync(DEBOUNCE_FILE, 'utf8')); } catch {}
  data[key] = Date.now();
  const now = Date.now();
  for (const k of Object.keys(data)) {
    if (now - data[k] > DEBOUNCE_MS * 10) delete data[k];
  }
  fs.writeFileSync(DEBOUNCE_FILE, JSON.stringify(data));
}

function shouldScan(filePath) {
  if (!filePath) return false;
  const ext = path.extname(filePath).toLowerCase();
  if (!CODE_EXTS.has(ext)) return false;
  const parts = filePath.split(path.sep);
  return !parts.some(p => SKIP_DIRS.includes(p));
}

function hasSemgrep() {
  try {
    execFileSync('semgrep', ['--version'], { stdio: 'pipe', timeout: 5000 });
    return true;
  } catch { return false; }
}

function runSemgrep(filePath) {
  try {
    const result = execFileSync('semgrep', [
      '--config', 'auto',
      '--json',
      '--quiet',
      '--timeout', '10',
      filePath
    ], { stdio: 'pipe', timeout: 15000 });

    const parsed = JSON.parse(result.toString());
    const findings = (parsed.results || []).map(r => ({
      severity: r.extra?.severity || 'WARNING',
      rule: r.check_id || 'unknown',
      message: r.extra?.message || r.extra?.metadata?.message || 'no message',
      line: r.start?.line || 0,
      file: path.basename(filePath)
    }));

    return findings;
  } catch (e) {
    if (e.stdout) {
      try {
        const parsed = JSON.parse(e.stdout.toString());
        if (parsed.results && parsed.results.length === 0) return [];
      } catch {}
    }
    return [];
  }
}

async function main() {
  let input = '';
  for await (const chunk of process.stdin) {
    input += chunk;
  }

  try {
    const data = JSON.parse(input);
    const toolName = data.tool_name;
    const toolInput = data.tool_input || {};

    if (toolName !== 'Write' && toolName !== 'Edit') {
      process.exit(0);
    }

    const filePath = toolInput.file_path;
    if (!shouldScan(filePath)) process.exit(0);
    if (isDebounced(filePath)) process.exit(0);

    if (!hasSemgrep()) {
      process.exit(0);
    }

    setDebounce(filePath);
    const findings = runSemgrep(filePath);

    if (findings.length > 0) {
      console.log(`\n[Semgrep] ${findings.length} finding(s) in ${path.basename(filePath)}:`);
      for (const f of findings) {
        console.log(`  ${f.severity} L${f.line}: ${f.rule} — ${f.message}`);
      }
    }
  } catch {
    // Silent failure — never block Claude
  }

  process.exit(0);
}

main();
