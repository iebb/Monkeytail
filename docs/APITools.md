# API tools in 1.2

Monkeytail is a native request debugger. No Monkeytail login is required. iPhone, iPad, and Mac use the same workspace format and iCloud Drive container. iCloud sync is on by default and syncs everything, including credentials. Turn off **Include credentials** to keep credentials on the device, or **iCloud sync** to stay local.

## Folders and authentication

Collection and nested-folder defaults supply headers, variables, authentication, and scripts. Request values override folder values. Variable precedence, lowest first: workspace globals, collection/folder variables, the active environment, then request variables. Disabled child headers suppress matching parent headers. Choose **Inherit** for authentication. Imported scripts require an explicit per-device opt-in.

Auth supports Basic, Digest, Bearer, API key in a header or query, OAuth 1.0 (HMAC-SHA1, HMAC-SHA256 or PLAINTEXT, signed in the Authorization header over query and URL-encoded body parameters), OAuth 2.0 authorization code with S256 PKCE, refresh tokens, client credentials and password credentials, JWT Bearer, and AWS SigV4. JWT Bearer signs a fresh token on every send with HS256/384/512 (UTF-8 or Base64 secret), RS or PS 256/384/512 (unencrypted PKCS#8 or PKCS#1 PEM), or ES256/384/512 (P-256, P-384, P-521; PKCS#8 or SEC1 PEM). The payload and extra header fields are JSON with `{{variables}}`, including `{{$timestamp}}` for `iat`; the token goes in `Authorization: <prefix> <token>` or a query parameter, as in Postman, whose `jwt` auth imports and exports. Secrets and private keys follow the same credential storage as other auth; code snippets show `<JWT>` unless credentials are included; the Watch companion does not support it. Digest answers the server's 401 challenge with one retry, supporting MD5, SHA-256 and their `-sess` variants with `qop=auth` or `auth-int`; the Watch companion does not support it. OAuth callbacks use `monkeytail://oauth`; configure that exact callback with your provider. OAuth credentials and tokens use local workspace storage, with optional Keychain storage and optional inclusion in iCloud. The provider may require its own sign-in. This is independent of Monkeytail, which has no accounts.

## Variables

Edit environments and **Globals** from the environment sheet. Postman globals exports import as globals. Below the URL, each `{{name}}` shows the value it resolves to; values marked sensitive stay masked and unresolved names are highlighted. Typing `{{` in the URL, a key/value table, or a bearer/basic/API-key field suggests defined and dynamic variables. `{{$guid}}`, `{{$timestamp}}`, `{{$isoTimestamp}}`, `{{$randomInt}}`, `{{$randomUUID}}`, `{{$randomEmail}}` and similar dynamic variables generate a new value on each use; a defined variable of the same name wins. URL segments such as `/users/:id` appear under Params → Path variables and import/export with Postman's `url.variable`. Every key/value table offers **Bulk edit**: one `name:value` per line, with `//` disabling a row.

## Collection runner

Run a collection from its header menu, or a folder from its menu. Choose requests, iterations, delay, and an optional CSV or JSON data file (up to 1,000 rows and 10 MB). Each data row overrides variables for one iteration. Variables set by scripts carry to later requests in the run and persist to the active environment. WebSocket and SSE requests are skipped. Scripts can change the order with `pm.execution.setNextRequest(name)` or stop with `null`. Results show each request's status, time, and tests. Reports export as JSON or JUnit XML without response bodies. Runs are capped at 10,000 requests, and Send is disabled while one is active. There is no scheduled or cloud runner.

## Cookies and client certificates

Enable **Use cookie jar** in Request → Auth. Cookies & certificates manages separate jars per environment: edit name/value/domain/path, expiration, host-only, HTTPS-only, and HttpOnly. Cookie domains use the bundled Public Suffix List. Explicit Cookie headers override the jar. Neither jars nor client certificates sync through iCloud.

Import a PKCS#12 identity and password, then associate it with an exact HTTPS host and port. Client identities and certificate-chain diagnostics use **System TLS**. Browser TLS profiles and WebSocket/SSE do not share the browser impersonation transport. Mac identity import requires macOS 15; other Mac features support macOS 14. Certificate verification stays on. A server with a self-signed or private-CA certificate fails with its SHA-256 fingerprint and a **Trust for host:port and resend** action. That pins the exact certificate for that one host and port, on this device only, over System TLS, HTTP, WebSocket and SSE. Other hosts and changed certificates are still verified. Review or remove trusts under Network settings → Trusted server certificates.

## Contracts and tests

Import Swagger 2 or OpenAPI 3 JSON/YAML from Import & export. Local references are resolved; bundle external references first. Paths become requests, tags become folders, and parameter hints, examples, supported auth, and JSON schemas are retained. Generated examples are editable starting points.

Request → Tests adds status, maximum duration, header, JSONPath, or JSON Schema checks. Results appear under Response → Tests. Status/header/JSON checks can be inserted as editable JavaScript. Response schemas are checked by adding a schema assertion. Request schemas validate before sending.

The portable schema subset includes local `$ref`, Boolean schemas, type, enum/const, required/properties/additionalProperties, object/array/string/numeric bounds, items/uniqueItems, and allOf/anyOf/oneOf/not. Regex patterns support a bounded simple subset. Unsupported advanced keywords produce an explicit error, rather than a false pass. Format annotations, external references, remote schema loading, tuple/prefixItems and unevaluated/dependent schema features are outside this subset. Schema/body/node/depth limits keep validation bounded.

## GraphQL and streams

Choose GraphQL in the protocol menu, then Body for query, variables, and operation name. **Load schema** fetches introspection using the selected request settings. Search the returned fields and insert a field suggestion. Introspection must be enabled by the server. GraphQL errors remain visible in the JSON response; this is a schema browser, not a full IDE language server.

WebSocket and SSE use System TLS and the selected proxy/authentication settings. Choose Connect; WebSocket can send text or hex bytes and ping. The timeline supports filtering and JSON/binary inspection. Reconnect uses SSE retry hints and Last-Event-ID. Events are bounded to 500 entries and 8 MB, with a 1 MB message/event limit. Connections are scoped to the request view.

## Code and mocks

Export client code from Workspace actions: cURL, JavaScript fetch, Node.js axios, Python requests, Go net/http, Java HttpClient, C# HttpClient, PHP cURL, Ruby Net::HTTP, Swift URLSession, Kotlin OkHttp, HTTPie, and PowerShell are supported for HTTP/GraphQL. Printable UTF-8 bodies stay readable; binary bodies are embedded as base64. Known credential headers, query items, marked fields, JSON credential keys, and form credential keys are hidden by default. Inspect raw bodies, scripts, and attachments yourself before sharing; arbitrary embedded secrets cannot be detected reliably. Snippets show basic transport calls; browser TLS profiles, proxies, local identities, cookie jars, and the Monkeytail scripting runtime are not reproduced.

Request → Mock enables an offline UTF-8 response up to 2 MB, with status, headers, delay, or a simulated error. Use the current response or a saved snapshot. Cookies & certificates → Mock server exposes enabled routes on an ephemeral `127.0.0.1` port while the app is active. Routes match method and path, ignoring query values. Duplicate routes are rejected. Other devices cannot reach this loopback server. Responses and mocks are development fixtures, not a hosted service.

Request → Mock → **Saved examples** stores named responses with the request (up to 20, each a UTF-8 body up to 2 MB). Examples sync and export as Postman `response` examples, import from Postman collections, and **Use as mock** turns one into the offline mock.

## Documentation, tabs, and previews

Request → Docs, and collection/folder settings, hold Markdown documentation. Postman and Insomnia descriptions and OpenAPI operation descriptions import into it, and Postman export writes it back. Preview renders inline Markdown such as emphasis, code, and links.

On Mac and iPad, opened requests appear as tabs above the editor. Close a tab, close the others, or duplicate the request from the tab's context menu. Open tabs and the selected request are restored on the next launch.

HTML responses offer a **Preview** format. It renders without JavaScript, navigation, or remote loads: a content security policy allows only inline styles and `data:` images.
