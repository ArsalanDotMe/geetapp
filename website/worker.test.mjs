import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.mjs';

const env = {
  ASSETS: { fetch: () => new Response('website') },
  DISCOVER: { get: async key => key === 'discover/v1.json' ? {
    body: '{"schemaVersion":1}', httpEtag: '"feed-1"',
    writeHttpMetadata: headers => headers.set('Content-Type', 'application/json')
  } : null }
};
test('website uses the static assets binding', async () => {
  assert.equal(await (await worker.fetch(new Request('https://geet.test/'), env)).text(), 'website');
});
test('Discover stays available at its existing path, including HEAD and conditional refresh', async () => {
  const url = 'https://geet.test/discover/v1.json';
  const result = await worker.fetch(new Request(url), env);
  assert.equal(result.status, 200);
  assert.equal(result.headers.get('Content-Type'), 'application/json');
  assert.equal(await result.text(), '{"schemaVersion":1}');
  assert.equal((await worker.fetch(new Request(url, {headers:{'If-None-Match':'"feed-1"'}}), env)).status, 304);
  assert.equal(await (await worker.fetch(new Request(url, {method:'HEAD'}), env)).text(), '');
  assert.equal((await worker.fetch(new Request(url, {method:'POST'}), env)).status, 405);
  assert.equal((await worker.fetch(new Request('https://geet.test/discover/missing'), env)).status, 404);
});
