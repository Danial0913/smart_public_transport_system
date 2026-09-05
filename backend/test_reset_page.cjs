const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const {test} = require('node:test');

const source = fs.readFileSync(path.join(__dirname, 'static/reset.js'), 'utf8');

function page(fetch, hash = '#requestId=test-request&token=test-link') {
  let click, timeout, cleared = false;
  const button = {disabled: false, addEventListener: (_, handler) => { click = handler; }};
  const status = {textContent: ''};
  vm.runInNewContext(source, {
    URLSearchParams, AbortController, TypeError, fetch,
    location: {hash}, history: {replaceState() {}},
    document: {getElementById: id => id === 'confirm' ? button : status},
    setTimeout: (handler, delay) => {
      assert.equal(delay, 20000);
      timeout = handler;
      return 1;
    },
    clearTimeout: () => { cleared = true; },
  });
  return {button, status, click: () => click(), expire: () => timeout(), cleared: () => cleared};
}

test('hanging confirmation times out and permits retry', async () => {
  let calls = 0;
  const view = page((url, options) => {
    assert.equal(url, '/v1/recovery/link');
    if (++calls > 1) return Promise.resolve({ok: true, json: async () => ({verified: true})});
    return new Promise((_, reject) => options.signal.addEventListener('abort', () => {
      const error = new Error('Aborted');
      error.name = 'AbortError';
      reject(error);
    }));
  });
  const pending = view.click();
  assert.equal(view.button.disabled, true);
  assert.match(view.status.textContent, /Confirming/);
  view.expire();
  await pending;
  assert.equal(view.button.disabled, false);
  assert.match(view.status.textContent, /Could not reach/);
  assert.equal(view.cleared(), true);
  await view.click();
  assert.equal(view.button.disabled, true);
  assert.match(view.status.textContent, /Email confirmed/);
});

test('unverified responses never display success', async () => {
  const view = page(async () => ({ok: true, json: async () => ({verified: false})}));
  await view.click();
  assert.equal(view.button.disabled, false);
  assert.match(view.status.textContent, /Could not confirm/);
  assert.equal(view.cleared(), true);
});

test('incomplete links disable confirmation', () => {
  const view = page(() => assert.fail('Must not send a request'), '');
  assert.equal(view.button.disabled, true);
  assert.match(view.status.textContent, /incomplete/);
});
