# API tools in 1.2

Monkeytail is a native request debugger. No Monkeytail login is required. iPhone, iPad, and Mac use the same workspace format and optional iCloud Drive container. Credentials remain local.

## Folders and authentication

Collection and nested-folder defaults supply headers, variables, authentication, and scripts. Request values override folder values; environment variables override collection/folder variables, and request variables override the environment. Disabled child headers suppress matching parent headers. Choose **Inherit** for authentication. Imported scripts require an explicit per-device opt-in.

Auth supports Basic, Bearer, API key in a header or query, OAuth 2.0 authorization code with S256 PKCE, refresh tokens and client credentials, and AWS SigV4. OAuth callbacks use `monkeytail://oauth`; configure that exact callback with your provider. OAuth credentials and tokens stay in the device Keychain. The provider may require its own sign-in. This is independent of Monkeytail, which has no accounts.

## Cookies and client certificates

Enable **Use cookie jar** in Request → Auth. Cookies & certificates manages separate jars per environment: edit name/value/domain/path, expiration, host-only, HTTPS-only, and HttpOnly. Cookie domains use the bundled Public Suffix List. Explicit Cookie headers override the jar. Neither jars nor client certificates sync through iCloud.

Import a PKCS#12 identity and password, then associate it with an exact HTTPS host and port. Client identities and certificate-chain diagnostics use **System TLS**. Browser TLS profiles and WebSocket/SSE do not share the browser impersonation transport. Mac identity import requires macOS 15; other Mac features support macOS 14. Trust verification remains enabled.

## Contracts and tests

Import Swagger 2 or OpenAPI 3 JSON/YAML from Import & export. Local references are resolved; bundle external references first. Paths become requests, tags become folders, and parameter hints, examples, supported auth, and JSON schemas are retained. Generated examples are editable starting points.

Request → Tests adds status, maximum duration, header, JSONPath, or JSON Schema checks. Results appear under Response → Tests. Status/header/JSON checks can be inserted as editable JavaScript. Response schemas are checked by adding a schema assertion. Request schemas validate before sending.

The portable schema subset includes local `$ref`, Boolean schemas, type, enum/const, required/properties/additionalProperties, object/array/string/numeric bounds, items/uniqueItems, and allOf/anyOf/oneOf/not. Regex patterns support a bounded simple subset. Unsupported advanced keywords produce an explicit error, rather than a false pass. Format annotations, external references, remote schema loading, tuple/prefixItems and unevaluated/dependent schema features are outside this subset. Schema/body/node/depth limits keep validation bounded.

## GraphQL and streams

Choose GraphQL in the protocol menu, then Body for query, variables, and operation name. **Load schema** fetches introspection using the selected request settings. Search the returned fields and insert a field suggestion. Introspection must be enabled by the server. GraphQL errors remain visible in the JSON response; this is a schema browser, not a full IDE language server.

WebSocket and SSE use System TLS and the selected proxy/authentication settings. Choose Connect; WebSocket can send text or hex bytes and ping. The timeline supports filtering and JSON/binary inspection. Reconnect uses SSE retry hints and Last-Event-ID. Events are bounded to 500 entries and 8 MB, with a 1 MB message/event limit. Connections are scoped to the request view.

## Code and mocks

Export client code from Workspace actions. Swift URLSession, JavaScript fetch, Python requests, and Kotlin OkHttp are supported for HTTP/GraphQL. Known credential headers, query items, marked fields, JSON credential keys, and form credential keys are hidden by default. Inspect raw bodies, scripts, and attachments yourself before sharing; arbitrary embedded secrets cannot be detected reliably. Snippets show basic transport calls; browser TLS profiles, proxies, local identities, cookie jars, and the Monkeytail scripting runtime are not reproduced.

Request → Mock enables an offline UTF-8 response up to 2 MB, with status, headers, delay, or a simulated error. Use the current response or a saved snapshot. Cookies & certificates → Mock server exposes enabled routes on an ephemeral `127.0.0.1` port while the app is active. Routes match method and path, ignoring query values. Duplicate routes are rejected. Other devices cannot reach this loopback server. Responses and mocks are development fixtures, not a hosted service.
