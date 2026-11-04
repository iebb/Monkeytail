import XCTest
@testable import MonkeytailCore

final class InterchangeImportTests: XCTestCase {
    func testInsomniaV5YAMLKeepsFoldersEnvironmentsAndScripts() throws {
        let source = """
        type: collection.insomnia.rest/5.0
        schema_version: "5.1"
        name: Variable Inheritance
        meta:
          id: wrk_1
        collection:
          - name: grandparent
            meta:
              id: fld_1
            children:
              - name: parent
                meta:
                  id: fld_2
                children:
                  - url: https://insomnia-airlines-api.onrender.com/test/extra-data
                    name: Child Request
                    meta:
                      id: req_1
                    method: GET
                    headers:
                      - name: x-test-value
                        value: "{{ _['test-value'] }}"
                        disabled: false
                    authentication:
                      type: basic
                      username: "{{ _.user }}"
                      password: ""
                    settings:
                      followRedirects: "off"
            environment:
              test-value: grandparent
            authentication:
              type: bearer
              token: folder-token
          - url: "{{ _.base }}/flights"
            name: Create flight
            meta:
              id: req_2
            method: POST
            body:
              mimeType: application/json
              text: '{"origin": "YYZ"}'
            parameters:
              - name: dryRun
                value: "true"
                disabled: true
            scripts:
              preRequest: insomnia.environment.set('x', '1');
              afterResponse: insomnia.test('ok', () => insomnia.expect(insomnia.response.code).to.eql(200));
          - url: wss://echo.example.com
            name: Socket
            meta:
              id: ws-req_1
          - url: grpc://example.com
            name: Greeter
            meta:
              id: greq_1
        environments:
          name: Base Environment
          meta:
            id: env_1
          data:
            base: https://example.com
            nested:
              key: value
          subEnvironments:
            - name: Staging
              meta:
                id: env_2
              data:
                base: https://staging.example.com
        """
        let result = try InterchangeImport.decode(source, filename: "insomnia.yaml")
        let collection = try XCTUnwrap(result.workspace.collections.first)
        XCTAssertEqual(collection.name, "Variable Inheritance")
        XCTAssertEqual(collection.folders?.map(\.name), ["grandparent", "parent"])
        XCTAssertEqual(collection.folders?[1].parentID, collection.folders?[0].id)
        XCTAssertEqual(collection.folders?[0].defaults.variables.first?.value, "grandparent")
        XCTAssertEqual(collection.folders?[0].defaults.auth.token, "folder-token")
        XCTAssertEqual(collection.defaults?.variables.map(\.name), ["base", "nested.key"])
        let child = collection.requests[0]
        XCTAssertEqual(child.folderID, collection.folders?[1].id)
        XCTAssertEqual(child.headers.first?.value, "{{test-value}}")
        XCTAssertEqual(child.auth.kind, .basic); XCTAssertEqual(child.auth.username, "{{user}}")
        XCTAssertFalse(child.followRedirects)
        let create = collection.requests[1]
        XCTAssertEqual(create.url, "{{base}}/flights"); XCTAssertEqual(create.bodyKind, .json); XCTAssertEqual(create.auth.kind, .inherit)
        XCTAssertFalse(create.query[0].enabled)
        XCTAssertTrue(create.preScript.contains("insomnia.environment.set")); XCTAssertTrue(create.postScript.contains("insomnia.test"))
        XCTAssertEqual(collection.requests[2].transport, .websocket)
        XCTAssertEqual(collection.requests.count, 3)
        XCTAssertEqual(result.workspace.environments.map(\.name), ["Staging"])
        XCTAssertTrue(result.warnings.contains { $0.contains("gRPC") })
        let resolved = try RequestInheritance.resolve(child, collection: collection, environment: [:])
        XCTAssertEqual(resolved.variables["test-value"], "grandparent")
    }

    func testInsomniaV4YAMLBuildsFoldersPerWorkspace() throws {
        let source = """
        _type: export
        __export_format: 4
        __export_source: insomnia.desktop.app:v8.0.0
        resources:
          - _id: wrk_1
            _type: workspace
            name: Shop
          - _id: fld_1
            _type: request_group
            parentId: wrk_1
            name: Orders
            environment:
              page: "2"
          - _id: req_1
            _type: request
            parentId: fld_1
            name: List orders
            method: GET
            url: "{{ _.base_url }}/orders"
            metaSortKey: 2
          - _id: req_2
            _type: request
            parentId: wrk_1
            name: GraphQL
            method: POST
            url: https://example.com/graphql
            body:
              mimeType: application/graphql
              text: '{"query":"{ shop { name } }","variables":{"id":1}}'
          - _id: req_3
            _type: request
            parentId: wrk_1
            name: GraphQL without variables
            method: POST
            url: https://example.com/graphql
            body:
              mimeType: application/graphql
              text: '{"query":"{ ping }","variables":null}'
          - _id: env_1
            _type: environment
            parentId: wrk_1
            name: Base Environment
            data:
              base_url: https://example.com
          - _id: env_2
            _type: environment
            parentId: env_1
            name: Production
            data:
              base_url: https://shop.example.com
              origin: "{{ scheme }}://{{host }}{{ _.base_path }}"
        """
        let result = try InterchangeImport.decode(source)
        XCTAssertEqual(result.workspace.collections.count, 1)
        let collection = result.workspace.collections[0]
        XCTAssertEqual(collection.name, "Shop")
        XCTAssertEqual(collection.folders?.first?.name, "Orders")
        XCTAssertEqual(collection.requests.first { $0.name == "List orders" }?.folderID, collection.folders?.first?.id)
        XCTAssertEqual(collection.defaults?.variables.first?.value, "https://example.com")
        XCTAssertEqual(result.workspace.environments.map(\.name), ["Production"])
        XCTAssertEqual(result.workspace.environments[0].values["origin"], "{{scheme}}://{{host}}{{base_path}}")
        let graphql = try XCTUnwrap(collection.requests.first { $0.name == "GraphQL" })
        XCTAssertEqual(graphql.transport, .graphql); XCTAssertEqual(graphql.graphql?.query, "{ shop { name } }")
        XCTAssertEqual(collection.requests.first { $0.name == "GraphQL without variables" }?.graphql?.query, "{ ping }")
    }

    func testBrunoFolderImportsTreeAuthScriptsAndEnvironments() throws {
        let files = [
            ImportFile(path: "bruno.json", text: #"{"version":"1","name":"Shop API","type":"collection"}"#),
            ImportFile(path: "collection.bru", text: """
            headers {
              X-Client: monkeytail
            }

            auth {
              mode: bearer
            }

            auth:bearer {
              token: {{token}}
            }
            """),
            ImportFile(path: "users/folder.bru", text: """
            meta {
              name: Users
              seq: 1
            }
            """),
            ImportFile(path: "users/create.bru", text: """
            meta {
              name: Create user
              type: http
              seq: 2
            }

            post {
              url: {{baseUrl}}/users?notify=true
              body: json
              auth: inherit
            }

            params:query {
              notify: true
              ~debug: 1
            }

            headers {
              "X-Quoted:Key": yes
              Content-Type: application/json
            }

            body:json {
              {
                "name": "Ada"
              }
            }

            vars:post-response {
              userId: res.body.id
            }

            assert {
              res.status: eq 201
              res.body.name: isString
            }

            script:pre-request {
              req.setHeader("X-Trace", "1");
            }

            tests {
              test("created", function() {
                expect(res.getStatus()).to.equal(201);
              });
            }

            docs {
              Creates a **user**.
            }
            """),
            ImportFile(path: "users/list.bru", text: """
            meta {
              name: List users
              seq: 1
            }

            get {
              url: {{baseUrl}}/users
              body: none
              auth: apikey
            }

            auth:apikey {
              key: api_key
              value: secret
              placement: queryparams
            }
            """),
            ImportFile(path: "upload.bru", text: """
            meta {
              name: Upload
            }

            post {
              url: https://example.com/upload
              body: multipartForm
              auth: none
            }

            body:multipart-form {
              caption: '''
                line one
                line two
              '''
              file: @file(images/a.png|images/b.png) @contentType(image/png)
            }
            """),
            ImportFile(path: "environments/Local.bru", text: """
            vars {
              baseUrl: http://localhost:3000
            }
            vars:secret [
              token
            ]
            """)
        ]
        let result = try InterchangeImport.decode(files: files, name: "folder")
        let collection = try XCTUnwrap(result.workspace.collections.first)
        XCTAssertEqual(collection.name, "Shop API")
        XCTAssertEqual(collection.defaults?.auth.kind, .bearer); XCTAssertEqual(collection.defaults?.auth.token, "{{token}}")
        XCTAssertEqual(collection.defaults?.headers.first?.name, "X-Client")
        XCTAssertEqual(collection.folders?.map(\.name), ["Users"])
        let users = collection.requests.filter { $0.folderID == collection.folders?.first?.id }
        XCTAssertEqual(users.map(\.name), ["List users", "Create user"])
        let create = users[1]
        XCTAssertEqual(create.method, "POST"); XCTAssertEqual(create.url, "{{baseUrl}}/users")
        XCTAssertEqual(create.query.map(\.enabled), [true, false])
        XCTAssertEqual(create.headers.first?.name, "X-Quoted:Key")
        XCTAssertEqual(create.bodyKind, .json); XCTAssertEqual(create.body, "{\n  \"name\": \"Ada\"\n}")
        XCTAssertEqual(create.auth.kind, .inherit)
        XCTAssertTrue(create.preScript.contains("req.setHeader"))
        XCTAssertTrue(create.postScript.contains(#"bru.setVar("userId", res.body.id)"#))
        XCTAssertTrue(create.postScript.contains("expect(res.status).to.eql(201);"))
        XCTAssertTrue(create.postScript.contains("expect(res.body.name).to.be.a('string');"))
        XCTAssertTrue(create.postScript.contains("expect(res.getStatus())"))
        XCTAssertEqual(create.description, "Creates a **user**.")
        XCTAssertEqual(users[0].auth.kind, .apiKey); XCTAssertEqual(users[0].auth.apiKey?.inQuery, true)
        let upload = try XCTUnwrap(collection.requests.first { $0.name == "Upload" })
        XCTAssertEqual(upload.multipart?.first?.value, "line one\nline two")
        XCTAssertEqual(upload.multipart?.dropFirst().map { $0.file?.filename }, ["a.png", "b.png"])
        XCTAssertEqual(upload.multipart?.last?.file?.mimeType, "image/png")
        XCTAssertEqual(upload.auth.kind, .none)
        let environment = try XCTUnwrap(result.workspace.environments.first)
        XCTAssertEqual(environment.name, "Local"); XCTAssertEqual(environment.values["baseUrl"], "http://localhost:3000")
        XCTAssertEqual(environment.variables.first { $0.name == "token" }?.secret, true)
    }

    func testBrunoJSONExport() throws {
        let source = #"""
        {"version":"1","name":"Exported","items":[
          {"type":"folder","name":"Auth","seq":1,"root":{"request":{"auth":{"mode":"basic","basic":{"username":"u","password":"p"}}}},"items":[
            {"type":"http-request","name":"Login","seq":1,"request":{"url":"https://example.com/login/:tenant","method":"POST","headers":[{"name":"Accept","value":"*/*","enabled":true}],
             "params":[{"name":"tenant","value":"acme","type":"path","enabled":true}],"body":{"mode":"formUrlEncoded","formUrlEncoded":[{"name":"user","value":"ada","enabled":true}]},
             "auth":{"mode":"inherit"},"script":{"req":"","res":"bru.setEnvVar('token', res.body.token)"},"vars":{"req":[],"res":[]},"assertions":[],"tests":"","docs":""},
             "examples":[{"name":"OK","response":{"status":200,"headers":[{"name":"Content-Type","value":"application/json","enabled":true}],"body":{"type":"json","content":{"token":"t"}}}}]}]},
          {"type":"graphql-request","name":"Query","seq":2,"request":{"url":"https://example.com/graphql","method":"POST","headers":[],"params":[],"body":{"mode":"graphql","graphql":{"query":"{ me { id } }","variables":""}},"auth":{"mode":"none"}}}],
         "environments":[{"name":"Dev","variables":[{"name":"host","value":"localhost","enabled":true,"secret":false,"type":"text"}]}]}
        """#
        let result = try InterchangeImport.decode(source)
        let collection = result.workspace.collections[0]
        XCTAssertEqual(collection.folders?.first?.defaults.auth.kind, .basic)
        let login = collection.requests[0]
        XCTAssertEqual(login.pathVariables?.first?.value, "acme"); XCTAssertEqual(login.bodyKind, .form); XCTAssertEqual(login.form.first?.name, "user")
        XCTAssertEqual(login.examples?.first?.status, 200); XCTAssertTrue(login.examples?.first?.body.contains("\"token\"") == true)
        XCTAssertEqual(collection.requests[1].transport, .graphql)
        XCTAssertEqual(result.workspace.environments.first?.values["host"], "localhost")
    }

    func testHoppscotchCollectionsAndEnvironments() throws {
        let collections = #"""
        [{"v":12,"name":"Hopp","folders":[{"v":12,"name":"Nested","folders":[],"requests":[
          {"v":"17","name":"Form","method":"POST","endpoint":"<<baseUrl>>/form","params":[],"headers":[{"key":"X-A","value":"<<a>>","active":false,"description":""}],
           "preRequestScript":"pw.env.set('a', '1');","testScript":"pw.test('ok', () => { pw.expect(pw.response.status).toBe(200); });",
           "auth":{"authType":"api-key","authActive":true,"key":"k","value":"v","addTo":"QUERY_PARAMS"},"body":{"contentType":"application/x-www-form-urlencoded","body":"a: 1\n#b: 2"},"requestVariables":[]}],
          "auth":{"authType":"inherit","authActive":true},"headers":[]}],
         "requests":[{"v":"17","name":"Me","method":"GET","endpoint":"https://example.com/me","params":[{"key":"q","value":"x","active":true}],"headers":[],"preRequestScript":"","testScript":"",
           "auth":{"authType":"bearer","authActive":true,"token":"<<token>>"},"body":{"contentType":null,"body":null},"requestVariables":[{"key":"id","value":"1","active":true}]}],
         "auth":{"authType":"none","authActive":true},"headers":[{"key":"X-Collection","value":"1","active":true}],"variables":[{"key":"baseUrl","initialValue":"https://a","currentValue":"","secret":false}]}]
        """#
        let result = try InterchangeImport.decode(collections)
        let collection = result.workspace.collections[0]
        XCTAssertEqual(collection.defaults?.variables.first?.value, "https://a")
        XCTAssertEqual(collection.defaults?.headers.first?.name, "X-Collection")
        let form = try XCTUnwrap(collection.requests.first { $0.name == "Form" })
        XCTAssertEqual(form.folderID, collection.folders?.first?.id)
        XCTAssertEqual(form.url, "{{baseUrl}}/form"); XCTAssertEqual(form.headers.first?.value, "{{a}}"); XCTAssertFalse(form.headers[0].enabled)
        XCTAssertEqual(form.form.map(\.enabled), [true, false]); XCTAssertEqual(form.auth.apiKey?.inQuery, true)
        let me = try XCTUnwrap(collection.requests.first { $0.name == "Me" })
        XCTAssertEqual(me.auth.token, "{{token}}"); XCTAssertEqual(me.variables?.first?.name, "id")
        let environments = #"[{"v":2,"id":"1","name":"Prod","variables":[{"key":"token","initialValue":"i","currentValue":"c","secret":true}]}]"#
        let environment = try InterchangeImport.decode(environments).workspace.environments[0]
        XCTAssertEqual(environment.values["token"], "c"); XCTAssertEqual(environment.variables[0].secret, true)
    }

    func testThunderClientCollectionConvertsTests() throws {
        let source = #"""
        {"clientName":"Thunder Client","collectionName":"Shop API","version":"1.2",
         "folders":[{"_id":"f-admin","name":"admin","containerId":"","sortNum":10000,"settings":{"auth":{"type":"bearer","bearer":"{{adminToken}}"},"headers":[{"name":"X-Scope","value":"admin"}]}},
                    {"_id":"f-orders","name":"orders","containerId":"f-admin","sortNum":10000}],
         "requests":[
          {"_id":"r-create","containerId":"f-orders","name":"Create order","url":"/orders/{orderId}/items?dryRun=true","method":"POST","sortNum":10000,
           "headers":[{"name":"X-Debug","value":"1","isDisabled":true}],"params":[{"name":"orderId","value":"42","isPath":true},{"name":"dryRun","value":"true","isPath":false}],
           "body":{"type":"json","raw":["{","  \"sku\": \"{{#guid}}\"","}"],"form":[]},
           "tests":[{"type":"res-code","custom":"","action":"equal","value":"201"},{"type":"json-query","custom":"json.items[0].id","action":"equal","value":"7"},{"type":"set-env-var","custom":"json.id","action":"setto","value":"{{lastItemId}}"}],
           "docs":["# Create","Adds an order."]},
          {"_id":"r-oauth","containerId":"","name":"Token","url":"https://auth.example.com/me","method":"GET","sortNum":20000,"headers":[],
           "body":{"type":"formencoded","raw":"","form":[{"name":"a","value":"1"},{"name":"b","value":"2","isDisabled":true}]},
           "auth":{"type":"oauth2","oauth2":{"grantType":"client_credentials","tokenUrl":"https://auth.example.com/token","clientId":"app","clientSecret":"s","scope":"read"}}}],
         "settings":{"auth":{"type":"bearer","bearer":"{{token}}"},"options":{"baseUrl":"{{baseUrl}}/api/"}}}
        """#
        let result = try InterchangeImport.decode(source)
        let collection = result.workspace.collections[0]
        XCTAssertEqual(collection.folders?.map(\.name), ["admin", "orders"])
        XCTAssertEqual(collection.folders?[1].parentID, collection.folders?[0].id)
        XCTAssertEqual(collection.folders?[0].defaults.auth.token, "{{adminToken}}")
        XCTAssertEqual(collection.defaults?.auth.token, "{{token}}")
        let create = collection.requests[0]
        XCTAssertEqual(create.url, "{{baseUrl}}/api/orders/:orderId/items")
        XCTAssertEqual(create.pathVariables?.first?.value, "42"); XCTAssertEqual(create.query.first?.name, "dryRun")
        XCTAssertEqual(create.body, "{\n  \"sku\": \"{{$guid}}\"\n}"); XCTAssertFalse(create.headers[0].enabled)
        XCTAssertTrue(create.postScript.contains(#"tc.check("res-code equal 201", () => { return tc.response.status; }, "equal", "201");"#))
        XCTAssertTrue(create.postScript.contains("const json = tc.response.json; return json.items[0].id;"))
        XCTAssertTrue(create.postScript.contains(#"tc.setVar("lastItemId""#))
        XCTAssertEqual(create.description, "# Create\nAdds an order.")
        let token = collection.requests[1]
        XCTAssertEqual(token.auth.kind, .oauth2); XCTAssertEqual(token.auth.oauth?.grant, .clientCredentials); XCTAssertEqual(token.auth.oauth?.tokenURL, "https://auth.example.com/token")
        XCTAssertEqual(token.form.map(\.enabled), [true, false])
        let environment = #"{"clientName":"Thunder Client","environmentName":"(Global Env)","global":true,"variables":[{"name":"tenant","value":"acme"}]}"#
        XCTAssertEqual(try InterchangeImport.decode(environment).workspace.globals?.first?.value, "acme")
    }

    func testHARImportsRequestsWithRecordedResponses() throws {
        let source = #"""
        {"log":{"version":"1.2","entries":[
          {"request":{"method":"POST","url":"https://api.example.com/login?next=%2Fhome","headers":[{"name":":authority","value":"api.example.com"},{"name":"Content-Type","value":"application/x-www-form-urlencoded"},{"name":"Content-Length","value":"9"},{"name":"Cookie","value":"a=1"}],
            "postData":{"mimeType":"application/x-www-form-urlencoded","params":[{"name":"user","value":"ada+lovelace"}]}},
           "response":{"status":200,"headers":[{"name":"Content-Type","value":"application/json"},{"name":"Content-Encoding","value":"br"}],"content":{"mimeType":"application/json","text":"{\"ok\":true}"}}},
          {"request":{"method":"GET","url":"https://cdn.example.com/app.js","headers":[]},"response":{"status":200,"headers":[],"content":{"text":"AAAA","encoding":"base64"}}},
          {"request":{"method":"GET","url":"data:image/png;base64,AAAA","headers":[]}}]}}
        """#
        let result = try InterchangeImport.decode(source)
        let collection = result.workspace.collections[0]
        XCTAssertEqual(collection.requests.count, 2)
        XCTAssertEqual(collection.folders?.map(\.name), ["api.example.com", "cdn.example.com"])
        let login = collection.requests[0]
        XCTAssertEqual(login.name, "POST /login"); XCTAssertEqual(login.url, "https://api.example.com/login?next=%2Fhome")
        XCTAssertEqual(login.headers.map(\.name), ["Content-Type", "Cookie"])
        XCTAssertEqual(login.bodyKind, .form); XCTAssertEqual(login.form.first?.value, "ada lovelace")
        XCTAssertEqual(login.examples?.first?.body, #"{"ok":true}"#); XCTAssertEqual(login.examples?.first?.headers.map(\.name), ["Content-Type"])
        XCTAssertNil(collection.requests[1].examples)
        XCTAssertTrue(result.warnings.contains { $0.contains("Cookie") })
    }

    func testHTTPFileImportsRequestsVariablesAndHandlers() throws {
        let source = """
        @baseUrl = https://api.example.com
        @token = abc

        ### List users
        GET {{baseUrl}}/users
            ?page=2
            &limit=10 HTTP/1.1
        Authorization: Bearer {{token}}
        X-Request-Id: {{$uuid}}

        ###
        # @name createUser
        # @no-redirect
        POST {{baseUrl}}/users
        Content-Type: application/json

        {
          "name": "Ada"
        }

        > {%
          client.test("created", function() { client.assert(response.status === 201, "status"); });
          client.global.set("id", response.body.id);
        %}

        ### Login form
        POST {{baseUrl}}/login
        Content-Type: application/x-www-form-urlencoded

        user=ada&pass=a%26b

        ###
        https://example.com/health
        """
        let result = try InterchangeImport.decode(source, filename: "api.http")
        let collection = result.workspace.collections[0]
        XCTAssertEqual(collection.name, "api")
        XCTAssertEqual(collection.defaults?.variables.map(\.name), ["baseUrl", "token"])
        XCTAssertEqual(collection.requests.map(\.name), ["List users", "createUser", "Login form", "GET https://example.com/health"])
        let list = collection.requests[0]
        XCTAssertEqual(list.url, "{{baseUrl}}/users?page=2&limit=10")
        XCTAssertEqual(list.headers.map(\.value), ["Bearer {{token}}", "{{$guid}}"])
        let create = collection.requests[1]
        XCTAssertEqual(create.bodyKind, .json); XCTAssertEqual(create.body, "{\n  \"name\": \"Ada\"\n}"); XCTAssertFalse(create.followRedirects)
        XCTAssertTrue(create.postScript.contains("client.global.set(\"id\", response.body.id);"))
        XCTAssertTrue(create.postScript.contains("(__http.client, __http.request, __http.response)"))
        let login = collection.requests[2]
        XCTAssertEqual(login.bodyKind, .form); XCTAssertEqual(login.form.map(\.value), ["ada", "a&b"])
    }

    func testPostmanV1AndDataDump() throws {
        let v1 = #"""
        {"id":"c1","name":"Legacy","order":["r1"],"folders":[{"id":"f1","name":"Users","order":["r2"]}],"requests":[
          {"id":"r1","name":"Root","collectionId":"c1","method":"GET","url":"https://example.com/?a=1","headers":"Accept: application/json\n//X-Off: 1","queryParams":[{"key":"a","value":"1","enabled":true}],"dataMode":"params","data":[],"tests":"tests['ok'] = responseCode.code === 200;"},
          {"id":"r2","name":"Create","collectionId":"c1","method":"POST","url":"https://example.com/users","headerData":[{"key":"Content-Type","value":"application/json","enabled":true}],"dataMode":"raw","rawModeData":"{\"a\":1}","currentHelper":"basicAuth","helperAttributes":{"username":"u","password":"p"},
           "responses":[{"name":"Created","responseCode":{"code":201},"headers":[],"text":"{}"}]}]}
        """#
        let legacy = try InterchangeImport.decode(v1).workspace.collections[0]
        XCTAssertEqual(legacy.requests.map(\.name), ["Root", "Create"])
        XCTAssertEqual(legacy.requests[0].url, "https://example.com/"); XCTAssertEqual(legacy.requests[0].headers.map(\.enabled), [true, false])
        XCTAssertTrue(legacy.requests[0].postScript.contains("tests['ok']"))
        XCTAssertEqual(legacy.requests[1].folderID, legacy.folders?.first?.id); XCTAssertEqual(legacy.requests[1].bodyKind, .json)
        XCTAssertEqual(legacy.requests[1].auth.kind, .basic); XCTAssertEqual(legacy.requests[1].examples?.first?.status, 201)
        let dump = #"""
        {"version":1,"collections":[{"info":{"name":"Modern","schema":"https://schema.getpostman.com/json/collection/v2.1.0/collection.json"},"item":[{"name":"Ping","request":{"method":"GET","url":"https://example.com/ping"}}]},
          {"id":"c1","name":"Legacy","order":["r1"],"folders":[],"requests":[{"id":"r1","name":"Root","collectionId":"c1","method":"GET","url":"https://example.com/"}]}],
         "environments":[{"id":"e1","name":"Prod","values":[{"key":"host","value":"example.com","enabled":true}]}],"globals":[{"key":"g","value":"1","enabled":true}]}
        """#
        let workspace = try InterchangeImport.decode(dump).workspace
        XCTAssertEqual(workspace.collections.map(\.name), ["Modern", "Legacy"])
        XCTAssertEqual(workspace.environments.first?.values["host"], "example.com")
        XCTAssertEqual(workspace.globals?.first?.name, "g")
        let native = try CollectionCodec.decode(CollectionCodec.encode(Workspace.starter, format: .native))
        XCTAssertTrue(native.includesSettings)
    }

    func testMultipleFilesMergeAndReportSkippedFiles() throws {
        let files = [ImportFile(path: "env.json", text: #"{"name":"Staging","values":[{"key":"a","value":"1"}]}"#),
                     ImportFile(path: "calls.http", text: "GET https://example.com"),
                     ImportFile(path: "notes.txt", text: "just some notes")]
        let result = try InterchangeImport.decode(files: files, name: "Imported files")
        XCTAssertEqual(result.workspace.environments.first?.name, "Staging")
        XCTAssertEqual(result.workspace.collections.first?.name, "calls")
        XCTAssertTrue(result.warnings.contains { $0.hasPrefix("Skipped notes.txt") })
        XCTAssertThrowsError(try InterchangeImport.decode("just some notes"))
    }
}
