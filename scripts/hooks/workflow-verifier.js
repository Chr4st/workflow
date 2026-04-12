#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const os = require('os');

const STATE_FILE = path.join(os.homedir(), '.claude', 'sessions', 'workflow-state.json');

function readJSON(p) { return JSON.parse(fs.readFileSync(p, 'utf8')); }
function allStates(m) { return Array.isArray(m) ? m : (m.states || []); }
function stateTool(def) { return def.tool || def.agent || def.skill || null; }

/** BFS from current states, collecting all reachable future state ids. */
function futureStates(states, currentIds) {
  const seen = new Set(currentIds);
  const queue = states.filter(s => currentIds.includes(s.id));
  const future = [];
  while (queue.length) {
    const def = queue.shift();
    const nexts = Array.isArray(def.next) ? def.next : [def.next];
    for (const nid of [...nexts, def.join].filter(Boolean)) {
      if (!seen.has(nid)) {
        seen.add(nid);
        future.push(nid);
        const nd = states.find(s => s.id === nid);
        if (nd) queue.push(nd);
      }
    }
  }
  return future;
}

function main() {
  const raw = fs.readFileSync('/dev/stdin', 'utf8');
  const input = JSON.parse(raw);
  const { tool_name: toolName } = input;

  let wfState;
  try { wfState = readJSON(STATE_FILE); } catch { process.stdout.write('{}'); return; }
  if (!wfState || !wfState.workflow_path) { process.stdout.write('{}'); return; }

  let machine;
  try { machine = readJSON(wfState.workflow_path); } catch { process.stdout.write('{}'); return; }

  const states = allStates(machine);
  const total = states.length;
  if (!total) { process.stdout.write('{}'); return; }

  const completed = wfState.completed || [];
  const currentIds = wfState.current_states || [];
  const pct = Math.round((completed.length / total) * 100);
  const currentId = currentIds[0] || null;
  const currentDef = states.find(s => s.id === currentId) || null;

  // Gate: requires_user_input
  if (currentDef && currentDef.requires_user_input && toolName !== 'AskUserQuestion') {
    process.stdout.write(JSON.stringify({
      result: 'approve',
      reason: `[Workflow] Current step ${currentId} requires user input. Use AskUserQuestion before proceeding.`,
    }));
    return;
  }

  // Skip-ahead detection
  const futureIds = futureStates(states, currentIds);
  const futureMatch = futureIds.find(id => {
    const def = states.find(s => s.id === id);
    return def && stateTool(def) === toolName;
  });

  if (futureMatch) {
    const curIdx = states.findIndex(s => s.id === currentId);
    const futIdx = states.findIndex(s => s.id === futureMatch);
    const skipped = states.slice(curIdx + 1, futIdx).map(s => s.id).join('-');
    process.stdout.write(JSON.stringify({
      result: 'approve',
      reason: `[Workflow] Warning: calling tool for step ${futureMatch} but current state is ${currentId}. Steps ${skipped || '?'} not yet complete.`,
    }));
    return;
  }

  // Progress report
  const last = completed[completed.length - 1] || currentId || 'start';
  const nextId = currentDef && currentDef.next;
  const nextDef = nextId ? states.find(s => s.id === nextId) : null;
  const nextLabel = nextId
    ? ` Next: ${nextId}${nextDef && stateTool(nextDef) ? ` — Agent(${stateTool(nextDef)})` : ''}`
    : '';

  process.stdout.write(JSON.stringify({
    result: 'approve',
    reason: `[Workflow] Step ${last} complete (${pct}%).${nextLabel}`,
  }));
}

try { main(); } catch { process.stdout.write('{}'); }
