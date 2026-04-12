#!/usr/bin/env node
/**
 * PostToolUse Learning Hook
 *
 * Captures learnings from code changes and test runs, saves to Engram.
 * Fire-and-forget: never blocks Claude. Debounced per file (20s).
 */

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const DEBOUNCE_FILE = path.join(os.tmpdir(), 'mentor-hook-debounce.json');
const DEBOUNCE_MS = 20000; // 20 seconds

function getProjectName(filePath) {
  const { getProjectName } = require('../lib/mentor-detect');
  // Walk up from file path to find project root
  const homeDir = os.homedir();
  const relative = filePath.replace(homeDir + '/', '');
  const topDir = relative.split('/')[0];
  return getProjectName(path.join(homeDir, topDir));
}

function isDebounced(key) {
  try {
    if (!fs.existsSync(DEBOUNCE_FILE)) return false;
    const data = JSON.parse(fs.readFileSync(DEBOUNCE_FILE, 'utf8'));
    const lastSeen = data[key];
    if (!lastSeen) return false;
    return (Date.now() - lastSeen) < DEBOUNCE_MS;
  } catch {
    return false;
  }
}

function markDebounced(key) {
  try {
    let data = {};
    if (fs.existsSync(DEBOUNCE_FILE)) {
      data = JSON.parse(fs.readFileSync(DEBOUNCE_FILE, 'utf8'));
    }
    // Clean old entries (>5 min)
    const now = Date.now();
    for (const [k, v] of Object.entries(data)) {
      if (now - v > 300000) delete data[k];
    }
    data[key] = now;
    fs.writeFileSync(DEBOUNCE_FILE, JSON.stringify(data));
  } catch {
    // Non-critical
  }
}

function saveToEngram(title, content, type, project) {
  try {
    const child = spawn('engram', [
      'save', title, content,
      '--type', type,
      '--project', project,
      '--scope', 'project',
    ], {
      detached: true,
      stdio: 'ignore',
    });
    child.unref();
  } catch {
    // Fire and forget
  }
}

function handleWriteEdit(toolInput) {
  const filePath = toolInput.file_path;
  if (!filePath) return;

  // Skip non-code files
  const ext = path.extname(filePath);
  const codeExts = ['.ts', '.tsx', '.js', '.jsx', '.py', '.go', '.rs', '.java', '.kt', '.swift', '.c', '.cpp', '.h'];
  if (!codeExts.includes(ext)) return;

  // Skip test files, configs, and generated files
  const basename = path.basename(filePath);
  if (basename.includes('.test.') || basename.includes('.spec.')) return;
  if (basename === 'package.json' || basename === 'tsconfig.json') return;
  if (filePath.includes('node_modules') || filePath.includes('.next') || filePath.includes('dist/')) return;

  // Debounce
  if (isDebounced(filePath)) return;
  markDebounced(filePath);

  const project = getProjectName(filePath);
  const fileName = path.basename(filePath);
  const dirName = path.basename(path.dirname(filePath));

  // Build observation
  const title = `Modified ${fileName} in ${dirName}`;
  const content = `What: Code change to ${fileName}\nWhy: Part of active development session\nWhere: ${filePath}\nLearned: File modified during session — review for patterns`;

  saveToEngram(title, content, 'discovery', project);
}

function handleBash(toolInput, toolOutput) {
  const cmd = toolInput.command || '';
  const output = (toolOutput && toolOutput.output) || '';

  // Detect test runs
  const isTestRun = /\b(vitest|jest|pytest|go test|npm test|pnpm test|npx vitest)\b/.test(cmd);
  if (!isTestRun) return;

  // Debounce test runs
  if (isDebounced('test-run')) return;
  markDebounced('test-run');

  const hasFailures = /fail|FAIL|error|ERROR|✗|✘/.test(output);
  const hasPass = /pass|PASS|✓|✔|ok/.test(output);

  // Extract project from cwd or command
  let project = 'unknown';
  try {
    const cwd = process.cwd();
    project = getProjectName(cwd);
  } catch { /* ignore */ }

  if (hasFailures) {
    const title = `Test failures detected`;
    const failLines = output.split('\n')
      .filter(l => /fail|FAIL|error|✗/i.test(l))
      .slice(0, 3)
      .join('\n');
    const content = `What: Test run with failures\nWhy: Tests catching bugs before deploy\nWhere: ${cmd}\nLearned: ${failLines || 'Check test output for details'}`;
    saveToEngram(title, content, 'bugfix', project);
  } else if (hasPass) {
    const title = `Tests passing`;
    const content = `What: All tests passed\nWhy: Code changes validated\nWhere: ${cmd}\nLearned: Tests confirmed implementation correctness`;
    saveToEngram(title, content, 'learning', project);
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
    const toolOutput = data.tool_output || {};

    if (toolName === 'Write' || toolName === 'Edit') {
      handleWriteEdit(toolInput);
    } else if (toolName === 'Bash') {
      handleBash(toolInput, toolOutput);
    }
  } catch {
    // Silent failure — never block Claude
  }

  process.exit(0);
}

main();
