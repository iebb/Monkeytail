# JavaScript hooks

Each request has **Before request** and **After response** scripts. Scripts run on every send and collection run, as in Postman, including scripts in imported or synced collections; collection and folder scripts run first. Turn off **Run scripts** in a request's Scripts tab, or **Run inherited scripts** in collection or folder settings, to skip them. Workspaces saved by earlier versions kept scripts off: use **Collection settings → Run scripts in every request and folder** to enable them at once. Each hook runs in its own fresh context. Use a selected environment to persist values between requests. Sandbox startup has a separate 10-second deadline; the three-second execution timer begins after it is ready.

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

## Postman compatibility

Most everyday Postman scripts run unchanged:

| API | Notes |
| --- | --- |
| `pm.environment` | `get/set/unset/has/clear/replaceIn/toObject`; values persist to the active environment |
| `pm.collectionVariables` | Same methods; values persist to the request's collection variables. An environment value with the same name still wins when resolving `{{name}}` |
| `pm.variables` | Local scope: `get` returns the narrowest value (local → environment → collection → globals), `set` lasts for this send, or for the whole collection run, and is never saved |
| `pm.globals` | Workspace globals, lowest precedence. Before-request edits apply to the same send |
| `pm.request` | `method`, `url`, `body`, and `headers.get/has/add/upsert/remove/toObject` |
| `pm.response` | `code`, `status`, `responseTime`, `json()`, `text()`, case-insensitive `headers.get/has/toObject` |
| `pm.response.to.have.status/header/body/jsonBody/responseTime`, `pm.response.to.be.ok/success/error/json…` | Supports `.not` |
| `pm.expect` | Chai subset: `equal/eql/deep.equal`, `a/an`, `include/contain`, `property`, `lengthOf`, `keys`, `match`, `above/below/least/most/within`, `oneOf`, `true/false/null/undefined/exist/empty/ok`, `.not`, `and/that/which` chaining |
| `pm.test(name, fn)` | Synchronous or `async` callbacks; `pm.test.skip` |
| `pm.sendRequest(urlOrRequest, callback?)` | Callback or `await`. Up to 10 HTTP(S) requests per script through the selected proxy using System TLS, without the cookie jar. The 3-second timer pauses while requests are in flight |
| `pm.info`, `pm.iterationData` | Runner iteration, request name/ID, and the current data row |
| `pm.cookies` | Read-only list for the request URL: `get/has/one/all/toObject/count/each/filter/find/map`. After the response it holds the updated jar, or the response's `Set-Cookie` cookies when the jar is off. Before the send it holds jar cookies. `pm.cookies.jar()` is unavailable |
| `CryptoJS`, `_`, `moment`, `require(...)` | Built in, no download, and redeclarable with `var CryptoJS = require('crypto-js')`. CryptoJS 4.2: `MD5`, `SHA1`, `SHA224`, `SHA256`, `SHA384`, `SHA512` and their `Hmac*` variants, progressive `algo.SHA256.create().update().finalize()` and `algo.HMAC`, `PBKDF2` (default SHA-256 with 250,000 iterations, as in crypto-js 4.2; pass a lower `iterations` to stay within the 3-second limit) and `EvpKDF`, `AES.encrypt/decrypt` with a passphrase (OpenSSL-compatible `Salted__` output) or a key `WordArray` plus `iv`, modes `CBC/ECB/CTR/CFB/OFB`, paddings `Pkcs7/NoPadding/ZeroPadding/AnsiX923/Iso10126/Iso97971`, `format.OpenSSL/Hex`, `enc.Hex/Latin1/Utf8/Base64/Base64url`, and `lib.WordArray.create/random`. Output matches crypto-js byte for byte. lodash 4 subset as `_` and `require('lodash')` (`lodash/get` style too): paths (`get/set/has/unset/pick/omit`), collections (`map/filter/reject/find/some/every/reduce/includes/groupBy/keyBy/countBy/partition/sortBy/orderBy`), arrays (`uniq/uniqBy/flatten/chunk/compact/difference/intersection/union/zip/range/head/last/take/drop`), math (`sum/sumBy/mean/max/min/maxBy/minBy/random/clamp`), objects (`merge/cloneDeep/defaults/mapValues/mapKeys/pickBy/omitBy/invert`), `isEqual/isMatch/isEmpty` and `is*` checks, string case and padding helpers, and `_.chain`/`_(value)` wrappers. moment 2 subset as `moment` and `require('moment')`: ISO, epoch, array, object and format-string parsing (`YYYY MM DD HH mm ss SSS A Z X` and friends), `format`, `utc/local`, `add/subtract/startOf/endOf`, `diff`, `isBefore/isAfter/isSame/isBetween`, getters and setters, `fromNow`, and `moment.duration`. English locale only; no time zones beyond UTC and the device zone. `require` also returns `crypto-js` and its `crypto-js/hmac-sha256`-style submodules, `atob`, `btoa`, and `uuid` (`v4`). DES, TripleDES, RC4, Rabbit, SHA3 and RIPEMD160 are unavailable |
| `pm.execution.setNextRequest(name or null)`, `pm.execution.skipRequest()` | Honoured by the collection runner; `skipRequest` in a before-request hook also skips a single send |
| Legacy `tests[...]`, `responseBody`, `responseCode`, `responseTime`, `responseHeaders`, `responseCookies`, `data`, `postman.*` | Supported for older collections |

Dynamic variables such as `{{$guid}}`, `{{$timestamp}}`, `{{$isoTimestamp}}`, `{{$randomInt}}`, and `{{$randomEmail}}` resolve on every use. Other modules (cheerio, chai, tv4, moment-timezone and similar), CryptoJS DES/RC4/Rabbit/SHA3, `pm.cookies.jar()`, `pm.vault`, `pm.visualizer`, and Insomnia APIs are unsupported.

Uncaught before-request errors prevent sending. After-response errors appear in Console while keeping the received response. Failed tests remain visible in Console. Logs are bounded to 200 entries of 10,000 characters each. Direct network access (`fetch`, XHR, navigation) is blocked; use `pm.sendRequest`. Top-level `await` is permitted within the three-second deadline. Avoid top-level `return`, because it bypasses the result envelope.
