# JavaScript hooks

Each request has **Before request** and **After response** scripts. Enable hooks in the Scripts tab. Imported scripts are always disabled initially. Each hook runs in its own fresh context. Use a selected environment to persist values between requests. Sandbox startup has a separate 10-second deadline; the three-second execution timer begins after it is ready.

Before-request scripts run before variable resolution and authentication. Edits apply to that send, not to the saved request definition. The `request` object contains `method`, `url`, `headers` (a name/value dictionary), and `body` (the raw text body). Form fields are edited in the Form UI; the raw-body scripting API does not replace form encoding.

```js
request.headers['X-Trace-ID'] = crypto.randomUUID();
request.url = '{{base_url}}/post';
request.method = 'POST';
request.body = JSON.stringify({ message: 'Hello from Swift' });
console.log('Sending', request.method, request.url);
```

The configured authentication mode is applied after the before-request hook. To manage Authorization entirely in a script, set the Auth tab to None.

After-response scripts can access `response.status`, `response.headers`, `response.body`, `response.json()` and `response.text()`.

```js
test('HTTP 200', () => {
  assert(response.status === 200, 'Expected a successful response');
});

test('Has a token', () => {
  const data = response.json();
  assert(typeof data.token === 'string', 'Missing token');
  environment.set('token', data.token);
});

console.log(response.json());
```

Available helpers:

| API | Behavior |
| --- | --- |
| `environment.get(name)` | Read an active environment value |
| `environment.set(name, value)` | Store a value as a string |
| `environment.unset(name)` | Remove a value |
| `console.log/warn/error(...values)` | Append a Console entry |
| `assert(condition, message)` | Throw if the condition is false |
| `test(name, synchronousFunction)` | Record a passing/failing assertion group |

`pm.environment`, `pm.variables`, `pm.request`, `pm.response`, `pm.test`, and basic `pm.expect(value).to.equal(...)` / `.to.eql(...)` aliases are available. `pm.response.to.have.status(200)` and `pm.request.headers.add/upsert/remove` are also supported. These are intentionally a small compatibility subset, not the Postman runtime. Asynchronous test callbacks, `pm.sendRequest`, Node modules, Chai chains beyond these examples, and Insomnia APIs are unsupported.

Uncaught before-request errors prevent sending. After-response errors appear in Console while keeping the received response. Failed tests remain visible in Console. Logs are bounded to 200 entries of 10,000 characters each. Network access is blocked; top-level `await` is permitted for local asynchronous JavaScript work within the three-second deadline. Avoid top-level `return`, because it bypasses the result envelope.
