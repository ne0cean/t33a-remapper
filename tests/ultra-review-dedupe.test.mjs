import test from 'node:test';
import assert from 'node:assert/strict';
import { scoreFindings } from '../scripts/ultra-review.mjs';

test('scores normalized exact duplicates once and preserves each lens finding', async () => {
  const findings = [
    { title: '  Cache   invalidation ', file: 'src/cache.js', line: '12', lens: 'bugs', why: 'evidence A' },
    { title: 'cache invalidation', file: 'src/cache.js', line: '12', lens: 'security', why: 'evidence B' },
    { title: 'cache invalidation', file: 'src/cache.js', line: '13', lens: 'siblings', why: 'different location' },
  ];
  const calls = [];
  const result = await scoreFindings(findings, async issue => {
    calls.push(issue);
    return calls.length * 10;
  });
  assert.equal(calls.length, 2);
  assert.deepEqual(result.map(({ score }) => score), [10, 10, 20]);
  assert.deepEqual(result.map(({ lens }) => lens), ['bugs', 'security', 'siblings']);
  assert.deepEqual(result.map(({ why }) => why), ['evidence A', 'evidence B', 'different location']);
});

test('does not merge findings without a non-empty title and complete location', async () => {
  const findings = [
    { title: 'same', file: 'a.js', line: 1 },
    { title: 'same', file: 'a.js' },
    { title: 'same', file: 'a.js' },
    { title: 'same' },
    { title: 'same' },
    { file: 'a.js', line: 1 },
    { file: 'a.js', line: 1 },
  ];
  let calls = 0;
  const result = await scoreFindings(findings, async () => ++calls);
  assert.equal(calls, 7);
  assert.deepEqual(result.map(({ score }) => score), [1, 2, 3, 4, 5, 6, 7]);
});
