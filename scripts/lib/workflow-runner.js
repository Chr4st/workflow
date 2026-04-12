'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');

const STATE_FILE = path.join(os.homedir(), '.claude', 'sessions', 'workflow-state.json');

function readStateFile() {
  try { return JSON.parse(fs.readFileSync(STATE_FILE, 'utf8')); } catch (_) { return null; }
}

function writeStateFile(state) {
  fs.mkdirSync(path.dirname(STATE_FILE), { recursive: true });
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2), 'utf8');
}

function findState(states, id) {
  return states.find(s => s.id === id) || null;
}

// --- Public API ---

function loadWorkflow(jsonPath) {
  const parsed = JSON.parse(fs.readFileSync(jsonPath, 'utf8'));
  return Array.isArray(parsed) ? parsed : parsed.states;
}

function initWorkflow(workflowName, states, workflowPath) {
  const initial = states[0] ? [states[0].id] : [];
  const state = {
    workflow: workflowName,
    workflow_path: workflowPath || null,
    started_at: new Date().toISOString(),
    current_states: initial,
    completed: [],
    skipped: [],
    parallel_pending: {},
  };
  writeStateFile(state);
  return state;
}

function getCurrentState() { return readStateFile(); }
function getWorkflowState() { return readStateFile(); }

function advanceState(stateId, states) {
  const wf = readStateFile();
  if (!wf) return null;

  if (!wf.current_states.includes(stateId)) {
    throw new Error(`State "${stateId}" is not in current_states: [${wf.current_states.join(', ')}]`);
  }

  const def = findState(states, stateId);
  const newCompleted = [...wf.completed, stateId];
  const remaining = wf.current_states.filter(id => id !== stateId);
  let newCurrent = remaining;
  let newPending = Object.assign({}, wf.parallel_pending);

  if (def) {
    if (def.type === 'parallel' && Array.isArray(def.next)) {
      newCurrent = [...remaining, ...def.next];
      const childEntries = def.next.map(id => [id, def.join]);
      newPending = Object.assign({}, newPending, Object.fromEntries(childEntries));
    } else if (newPending[stateId]) {
      // Fan in: remove this child's pending entry; advance to join when all siblings done
      const joinTarget = newPending[stateId] || def.join;
      // Remove only this child's entry
      newPending = Object.fromEntries(Object.entries(newPending).filter(([id]) => id !== stateId));
      // Siblings still waiting = those with the same join target that are not yet completed
      const stillWaiting = Object.keys(newPending).filter(id => newPending[id] === joinTarget);
      if (stillWaiting.length === 0 && joinTarget) {
        newCurrent = [...remaining, joinTarget];
      }
    } else if (def.type === 'conditional' && def.predicate === false) {
      if (def.next) newCurrent = [...remaining, def.next];
    } else if (def.next) {
      newCurrent = [...remaining, def.next];
    }
  }

  const updated = Object.assign({}, wf, {
    current_states: newCurrent,
    completed: newCompleted,
    parallel_pending: newPending,
  });
  writeStateFile(updated);
  return newCurrent;
}

function skipState(stateId, reason, states) {
  const wf = readStateFile();
  if (!wf) return null;

  const def = findState(states, stateId);
  const newSkipped = [...wf.skipped, { id: stateId, reason }];
  const remaining = wf.current_states.filter(id => id !== stateId);
  const newCurrent = def && def.next ? [...remaining, def.next] : remaining;

  writeStateFile(Object.assign({}, wf, { current_states: newCurrent, skipped: newSkipped }));
  return newCurrent;
}

function getProgress(states) {
  const wf = readStateFile();
  if (!wf) return null;

  const total = states.length;
  const completedCount = wf.completed.length;
  const percentage = total > 0 ? Math.round((completedCount / total) * 100) : 0;
  const currentStep = wf.current_states[0] || null;
  const currentDef = currentStep ? findState(states, currentStep) : null;
  const phase = currentDef && currentDef.phase != null ? currentDef.phase : null;

  return { completed: completedCount, total, percentage, current_step: currentStep, phase };
}

function resetWorkflow() {
  try { fs.unlinkSync(STATE_FILE); } catch (_) { /* already gone */ }
}

module.exports = {
  loadWorkflow,
  initWorkflow,
  getCurrentState,
  getWorkflowState,
  advanceState,
  skipState,
  getProgress,
  resetWorkflow,
};
