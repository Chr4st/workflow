#!/usr/bin/env node
/**
 * Mentor Stop Hook (Post-Response Analysis)
 *
 * Fires after each Claude response. Saves significant decisions
 * and patterns to Engram. Lightweight — skips trivial interactions.
 */

const { spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const COUNTER_FILE = path.join(os.tmpdir(), 'mentor-stop-counter.json');
const SAVE_EVERY_N = 5; // Only save every 5th response to avoid noise

function getCounter() {
  try {
    if (!fs.existsSync(COUNTER_FILE)) return 0;
    const data = JSON.parse(fs.readFileSync(COUNTER_FILE, 'utf8'));
    return data.count || 0;
  } catch {
    return 0;
  }
}

function setCounter(count) {
  try {
    fs.writeFileSync(COUNTER_FILE, JSON.stringify({ count, ts: Date.now() }));
  } catch { /* non-critical */ }
}

function saveToEngram(title, content, type, project) {
  try {
    const child = spawn('engram', [
      'save', title, content,
      '--type', type,
      '--project', project || 'unknown',
      '--scope', 'project',
    ], {
      detached: true,
      stdio: 'ignore',
    });
    child.unref();
  } catch { /* fire and forget */ }
}

function getProjectName() {
  try {
    const { getProjectName } = require('../lib/mentor-detect');
    return getProjectName(process.cwd());
  } catch {
    return path.basename(process.cwd()).toLowerCase();
  }
}

async function main() {
  // Increment counter
  const count = getCounter() + 1;
  setCounter(count);

  // Only process every Nth response
  if (count % SAVE_EVERY_N !== 0) {
    process.exit(0);
    return;
  }

  // Read stdin for any stop hook data
  let input = '';
  try {
    for await (const chunk of process.stdin) {
      input += chunk;
    }
  } catch { /* no input is fine */ }

  // Save a session checkpoint to Engram
  const project = getProjectName();
  const title = `Session checkpoint (${count} responses)`;
  const content = `What: Active development session in ${project}, ${count} responses deep\nWhy: Periodic checkpoint for session continuity\nWhere: ${process.cwd()}\nLearned: Session active — check Engram for recent observations`;

  saveToEngram(title, content, 'learning', project);

  process.exit(0);
}

main();
