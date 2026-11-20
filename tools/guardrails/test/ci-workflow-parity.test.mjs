import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { stepList } from '../src/index.mjs';

const WORKFLOW = '.github/workflows/ci.yml';
// Normalized to LF: Windows checkouts (core.autocrlf) give the workflow CRLF line endings.
const workflowText = readFileSync(fileURLToPath(new URL(`../../../${WORKFLOW}`, import.meta.url)), 'utf8').replace(
  /\r\n/g,
  '\n'
);

/**
 * Minimal reader for the shape ci.yml uses: `jobs:` -> `  <job>:` -> `steps:` -> `- name:` / `- uses:` items with
 * single-line `run:` values. Returns { <job>: [{ name, run }] } for the steps that run a command.
 */
function runStepsByJob(text) {
  const jobs = {};
  let inJobs = false;
  let job;
  let step;
  for (const line of text.split(/\r?\n/)) {
    if (/^jobs:\s*$/.test(line)) {
      inJobs = true;
      continue;
    }
    if (/^\S/.test(line)) inJobs = false;
    if (!inJobs) continue;
    const jobMatch = line.match(/^ {2}([\w-]+):\s*$/);
    if (jobMatch) {
      job = jobMatch[1];
      jobs[job] = [];
      step = undefined;
      continue;
    }
    const item = line.match(/^\s+- (name|uses|run):\s*(.*)$/);
    if (item) {
      step = {};
      jobs[job].push(step);
    }
    const field = item ?? line.match(/^\s+(name|run):\s*(.*)$/);
    if (field && step && (field[1] === 'name' || field[1] === 'run')) step[field[1]] = field[2].trim();
  }
  for (const name of Object.keys(jobs)) jobs[name] = jobs[name].filter((s) => s.run !== undefined);
  return jobs;
}

const expectedByJob = () => {
  const jobs = {};
  for (const step of stepList('ci')) (jobs[step.job] ??= []).push({ name: step.name, run: step.command.join(' ') });
  return jobs;
};

const asYaml = (steps) => steps.map((s) => `      - name: ${s.name}\n        run: ${s.run}`).join('\n\n');

test(`${WORKFLOW} runs exactly the ci tier of the shared step list`, () => {
  const actual = runStepsByJob(workflowText);
  for (const [job, steps] of Object.entries(actual)) {
    for (const step of steps) {
      assert.notEqual(step.run, '|', `${WORKFLOW} job "${job}": step "${step.name}" uses a multi-line run. Use one command per step so it can be checked against the step list.`);
    }
  }
  const expected = expectedByJob();
  for (const job of Object.keys(expected)) {
    assert.deepEqual(
      actual[job],
      expected[job],
      `${WORKFLOW} job "${job}" has drifted from the ci tier in tools/guardrails/src/steps.mjs. ` +
        `Change the step list first, then make the job's run steps (after its setup "uses:" steps) exactly:\n\n${asYaml(expected[job])}\n`
    );
  }
  assert.deepEqual(Object.keys(actual).sort(), Object.keys(expected).sort(), `${WORKFLOW} must have exactly the jobs of the ci tier.`);
});

test(`${WORKFLOW} runs on pull requests and on pushes to main`, () => {
  const on = workflowText.match(/^on:\s*\n((?:[ \t]+.*\n|\s*\n)*)/m)?.[1] ?? '';
  assert.match(on, /^ {2}pull_request:/m, `${WORKFLOW} must trigger on pull_request so a PR is checked before it merges.`);
  assert.match(on, /^ {2}push:\s*\n\s+branches:\s*\[\s*main\s*\]/m, `${WORKFLOW} must keep triggering on pushes to main.`);
});
