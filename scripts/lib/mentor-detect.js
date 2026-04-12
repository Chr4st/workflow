/**
 * Mentor Auto-Detection Module
 *
 * Detects the current project, checks GitNexus indexing status,
 * loads relevant Engram memories, and returns mentor context.
 */

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const os = require('os');

const GITNEXUS_REGISTRY = path.join(os.homedir(), '.gitnexus', 'registry.json');

// Map directory basenames to canonical project names
// Populate with your own project dir -> canonical name mapping.
// Example: 'MyAwesomeProject': 'myawesomeproject'
const PROJECT_NAMES = {};

/**
 * Get canonical project name from current working directory
 */
function getProjectName(cwd) {
  const basename = path.basename(cwd);
  if (PROJECT_NAMES[basename]) {
    return PROJECT_NAMES[basename];
  }
  // Fallback: use lowercase basename
  return basename.toLowerCase().replace(/[^a-z0-9-]/g, '-');
}

/**
 * Check if project is indexed in GitNexus
 */
function isGitNexusIndexed(cwd) {
  try {
    if (!fs.existsSync(GITNEXUS_REGISTRY)) return false;
    const registry = JSON.parse(fs.readFileSync(GITNEXUS_REGISTRY, 'utf8'));
    const repos = registry.repos || registry;
    if (Array.isArray(repos)) {
      return repos.some(r => r.path === cwd || r.directory === cwd);
    }
    // Object-style registry
    return Object.values(repos).some(r => r.path === cwd || r.directory === cwd);
  } catch {
    return false;
  }
}

/**
 * Trigger GitNexus indexing in background (non-blocking)
 */
function triggerGitNexusIndex(cwd) {
  try {
    const child = spawn('gitnexus', ['analyze'], {
      cwd,
      detached: true,
      stdio: 'ignore',
    });
    child.unref();
    return true;
  } catch {
    return false;
  }
}

/**
 * Load relevant Engram memories for a project (with timeout)
 */
function loadEngramMemories(projectName, limit = 5) {
  try {
    const result = execSync(
      `engram search "${projectName}" --project ${projectName} --limit ${limit}`,
      { timeout: 4000, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }
    );
    return result.trim();
  } catch {
    // Also try cross-project memories
    try {
      const result = execSync(
        `engram search "${projectName}" --limit ${limit}`,
        { timeout: 3000, encoding: 'utf8', stdio: ['pipe', 'pipe', 'pipe'] }
      );
      return result.trim();
    } catch {
      return '';
    }
  }
}

/**
 * Build mentor context string for Claude
 */
function buildMentorContext(projectName, isIndexed, memories) {
  const lines = [];
  lines.push(`[Mentor] Project: ${projectName}`);
  lines.push(`[Mentor] GitNexus: ${isIndexed ? 'Indexed (use gitnexus tools for impact analysis)' : 'Not indexed (indexing in background...)'}`);
  lines.push(`[Mentor] Engram: ${memories ? 'Memories loaded' : 'No memories yet'}`);

  if (memories && memories.length > 0) {
    // Extract just the titles from engram output
    const titleLines = memories.split('\n')
      .filter(l => l.includes('—'))
      .map(l => {
        const match = l.match(/— (.+)/);
        return match ? `  - ${match[1].trim()}` : null;
      })
      .filter(Boolean)
      .slice(0, 5);

    if (titleLines.length > 0) {
      lines.push('[Mentor] Key memories:');
      lines.push(...titleLines);
    }
  }

  lines.push('[Mentor] Growth edges: testing discipline, production infra, security, file size, refactoring');
  return lines.join('\n');
}

/**
 * Main detection function — call from session-start.js
 */
async function detectAndLoadMentorContext(cwd) {
  try {
    // Check if we're in a git repo
    try {
      execSync('git rev-parse --show-toplevel', { cwd, stdio: 'pipe', timeout: 2000 });
    } catch {
      // Not a git repo, minimal context
      return '[Mentor] Not in a git repository. Mentor context limited.';
    }

    const projectName = getProjectName(cwd);
    const isIndexed = isGitNexusIndexed(cwd);

    // Trigger indexing if not already indexed
    if (!isIndexed) {
      triggerGitNexusIndex(cwd);
    }

    // Load memories (with timeout protection)
    const memories = loadEngramMemories(projectName);

    return buildMentorContext(projectName, isIndexed, memories);
  } catch (err) {
    // Never block session start
    console.log('[Mentor] Warning: mentor context loading failed:', err.message);
    return `[Mentor] Context loading failed: ${err.message}`;
  }
}

module.exports = { detectAndLoadMentorContext, getProjectName, isGitNexusIndexed };
