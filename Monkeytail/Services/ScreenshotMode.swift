import Foundation
#if os(iOS)
import UIKit
#endif
#if os(visionOS)
import MonkeytailSystemCore
#else
import MonkeytailCore
#endif

/// App Store screenshots: `--screenshot <scene>` loads demo data in a temporary directory and opens one screen.
/// Nothing is read from or written to the user's workspace, theme or language.
struct ScreenshotScene {
    var name: String
    var request: String
    var editorTab: String?
    var responseTab: String?
    var format: String?
    var pane = "Response"
    var sheet: String?
    var dark = false
    var preset = "monkeytail"
    var send = true
    /// iPhone only: show the collections list instead of the request.
    var sidebar = false

    static let all: [ScreenshotScene] = [
        ScreenshotScene(name: "01-workspace", request: "List charges", responseTab: "Body", format: "Pretty"),
        ScreenshotScene(name: "02-tree", request: "Get customer", responseTab: "Body", format: "Tree"),
        ScreenshotScene(name: "03-headers", request: "List customers", responseTab: "Headers"),
        ScreenshotScene(name: "04-tests", request: "List charges", responseTab: "Tests"),
        ScreenshotScene(name: "05-console", request: "List charges", responseTab: "Console", dark: true),
        ScreenshotScene(name: "06-body", request: "Create charge", editorTab: "Body", pane: "Request", send: false),
        ScreenshotScene(name: "07-params", request: "List customers", editorTab: "Params", pane: "Request", send: false),
        ScreenshotScene(name: "08-auth", request: "Get access token", editorTab: "Auth", pane: "Request", send: false),
        ScreenshotScene(name: "09-scripts", request: "Create charge", editorTab: "Scripts", pane: "Request", send: false),
        ScreenshotScene(name: "10-docs", request: "List charges", editorTab: "Docs", pane: "Request", send: false),
        ScreenshotScene(name: "11-graphql", request: "Search products", editorTab: "Body", responseTab: "Body", format: "Pretty", preset: "grape"),
        ScreenshotScene(name: "12-environments", request: "List charges", sheet: "environment"),
        ScreenshotScene(name: "13-import", request: "List charges", sheet: "transfer"),
        ScreenshotScene(name: "14-runner", request: "List charges", sheet: "runner", send: false),
        ScreenshotScene(name: "15-code", request: "Create charge", sheet: "code", send: false),
        ScreenshotScene(name: "16-curl", request: "Create charge", sheet: "curl", send: false),
        ScreenshotScene(name: "17-history", request: "List charges", sheet: "history"),
        ScreenshotScene(name: "18-settings", request: "List charges", sheet: "settings"),
        ScreenshotScene(name: "19-theme", request: "Get customer", sheet: "theme", dark: true, preset: "ocean"),
        ScreenshotScene(name: "20-dark", request: "Get customer", responseTab: "Body", format: "Pretty", dark: true, preset: "graphite", sidebar: true)
    ]
}

enum ScreenshotMode {
    static let scene: ScreenshotScene? = {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--screenshot"), arguments.indices.contains(index + 1) else { return nil }
        return ScreenshotScene.all.first { $0.name == arguments[index + 1] || $0.name.dropFirst(3) == arguments[index + 1] }
    }()
    static var active: Bool { scene != nil }

    @MainActor static func prepare(_ store: WorkspaceStore) {
        guard let scene else { return }
        store.workspace = DemoWorkspace.workspace
        let requests = store.workspace.collections.flatMap(\.requests)
        store.history = DemoWorkspace.history(requests)
        for name in ["Create charge", "Get customer", "List customers"] { if let id = requests.first(where: { $0.name == name })?.id { store.openTab(id) } }
        store.selectedRequestID = requests.first { $0.name == scene.request }?.id
        #if os(iOS)
        // On iPhone a selected request always pushes the detail column.
        if scene.sidebar && UIDevice.current.userInterfaceIdiom == .phone { store.selectedRequestID = nil }
        #endif
    }
}

enum DemoWorkspace {
    static let mobileID = UUID(uuidString: "6B1D3F9A-2C4E-4F11-9A57-0D2E8B7C1A01")!

    static let workspace: Workspace = {
        let json = "application/json; charset=utf-8"
        func mock(_ body: String, status: Int = 200, delay: Int = 118, headers extra: [Field] = []) -> MockResponse {
            var mock = MockResponse(); mock.enabled = true; mock.status = status; mock.delayMilliseconds = delay; mock.body = body
            mock.headers = [Field("Content-Type", json), Field("Request-Id", "req_7Hk29fQxLmA3"), Field("Cache-Control", "no-store"), Field("RateLimit-Remaining", "4987")] + extra
            return mock
        }
        func request(_ name: String, _ method: String, _ path: String, folder: UUID? = nil) -> APIRequest {
            var request = APIRequest(name: name, method: method, url: "{{base_url}}" + path)
            request.folderID = folder; request.auth.kind = .inherit
            request.headers = [Field("Accept", "application/json")]
            return request
        }

        var customers = RequestFolder(name: "Customers"), charges = RequestFolder(name: "Charges"), webhooks = RequestFolder(name: "Webhooks")
        var refunds = RequestFolder(name: "Refunds", parentID: charges.id)
        customers.defaults.auth.kind = .inherit; charges.defaults.auth.kind = .inherit; refunds.defaults.auth.kind = .inherit; webhooks.defaults.auth.kind = .inherit

        var listCustomers = request("List customers", "GET", "/customers", folder: customers.id)
        listCustomers.query = [Field("limit", "20"), Field("status", "active"), Field("created[gte]", "2026-10-01"), Field("expand", "subscriptions")]
        listCustomers.mock = mock("""
        {"object":"list","has_more":true,"data":[{"id":"cus_8Kd2nQ","name":"Northwind Coffee","email":"billing@northwind.example","balance":0},{"id":"cus_3Lp9tR","name":"Harbor & Pine","email":"ap@harborpine.example","balance":-1250},{"id":"cus_1Zx7vB","name":"Lumen Studio","email":"hello@lumen.example","balance":4200}]}
        """, delay: 96, headers: [Field("Link", "<https://api.acme.dev/v1/customers?starting_after=cus_1Zx7vB>; rel=\"next\""), Field("ETag", "W/\"5f2-1c9a\""), Field("Strict-Transport-Security", "max-age=63072000"), Field("Vary", "Accept-Encoding, Authorization")])

        var getCustomer = request("Get customer", "GET", "/customers/:id", folder: customers.id)
        getCustomer.pathVariables = [Field("id", "cus_8Kd2nQ")]
        getCustomer.mock = mock("""
        {"id":"cus_8Kd2nQ","object":"customer","name":"Northwind Coffee","email":"billing@northwind.example","currency":"eur","created":1793664000,"address":{"line1":"18 Canal Street","city":"Amsterdam","postal_code":"1012 AB","country":"NL"},"subscriptions":[{"id":"sub_4Qe1","plan":"growth","status":"active","seats":12,"renews":"2026-12-01"}],"metadata":{"segment":"retail","account_manager":"Mira"},"tax_exempt":false,"delinquent":false}
        """, delay: 84)

        var createCustomer = request("Create customer", "POST", "/customers", folder: customers.id)
        createCustomer.bodyKind = .json
        createCustomer.body = "{\n  \"name\": \"Lumen Studio\",\n  \"email\": \"hello@lumen.example\"\n}"
        let updateCustomer = request("Update customer", "PATCH", "/customers/:id", folder: customers.id)
        let deleteCustomer = request("Delete customer", "DELETE", "/customers/:id", folder: customers.id)

        var listCharges = request("List charges", "GET", "/charges", folder: charges.id)
        listCharges.query = [Field("limit", "3"), Field("customer", "{{customer_id}}")]
        listCharges.postScript = """
        pm.test("Status is 200", () => pm.response.to.have.status(200));
        pm.test("Returns charges", () => pm.expect(pm.response.json().data.length).to.be.above(0));
        pm.test("Every charge is in euros", () => pm.response.json().data.forEach(c => pm.expect(c.currency).to.eql("eur")));
        pm.test("Responds within 500 ms", () => pm.expect(pm.response.responseTime).to.be.below(500));
        const charges = pm.response.json().data;
        console.log("Fetched", charges.length, "charges");
        console.log("Total captured", charges.reduce((sum, c) => sum + c.amount, 0) / 100, "EUR");
        pm.collectionVariables.set("charge_id", charges[0].id);
        """
        func assertion(_ kind: AssertionKind, _ name: String, path: String = "", expected: String) -> ResponseAssertion {
            var value = ResponseAssertion(); value.kind = kind; value.name = name; value.path = path; value.expected = expected; return value
        }
        listCharges.assertions = [assertion(.status, "Status is 200", expected: "200"), assertion(.duration, "Faster than 500 ms", expected: "500"),
                                  assertion(.header, "Returns JSON", path: "Content-Type", expected: "application/json; charset=utf-8"),
                                  assertion(.json, "Lists objects", path: "$.object", expected: "\"list\""), assertion(.json, "First charge succeeded", path: "$.data[0].status", expected: "\"succeeded\"")]
        listCharges.description = """
        Returns the most recent charges for a customer, newest first.

        **Query parameters**
        - `limit` — between 1 and 100, default 10
        - `customer` — only charges for this customer
        - `starting_after` — cursor for the next page

        The response includes `has_more` when another page is available. Amounts are in the smallest currency unit, so `4200` is €42.00.
        """
        listCharges.mock = mock("""
        {"object":"list","has_more":false,"data":[{"id":"ch_3NfK8a","amount":4200,"currency":"eur","status":"succeeded","captured":true,"customer":"cus_8Kd2nQ","description":"Growth plan · November","payment_method":{"type":"card","brand":"visa","last4":"4242"},"created":1793750400},{"id":"ch_3NfK7z","amount":1890,"currency":"eur","status":"succeeded","captured":true,"customer":"cus_8Kd2nQ","description":"Extra seats","payment_method":{"type":"card","brand":"mastercard","last4":"5100"},"created":1793664000},{"id":"ch_3NfK6y","amount":12500,"currency":"eur","status":"refunded","captured":true,"customer":"cus_8Kd2nQ","description":"Annual upgrade","payment_method":{"type":"sepa_debit","last4":"3000"},"created":1793577600}]}
        """)

        var createCharge = request("Create charge", "POST", "/charges", folder: charges.id)
        createCharge.headers += [Field("Idempotency-Key", "{{$guid}}"), Field("Content-Type", "application/json")]
        createCharge.bodyKind = .json
        createCharge.body = """
        {
          "amount": 4200,
          "currency": "eur",
          "customer": "{{customer_id}}",
          "description": "Growth plan · November",
          "capture": true,
          "metadata": {
            "order_id": "ord_{{$timestamp}}",
            "channel": "web"
          }
        }
        """
        createCharge.preScript = """
        // Sign the body so the API can verify it wasn't changed in transit.
        const secret = pm.environment.get("signing_secret");
        const signature = CryptoJS.HmacSHA256(pm.request.body.raw, secret).toString();
        pm.request.headers.upsert({ key: "Acme-Signature", value: signature });
        console.log("Signed request", signature.slice(0, 12) + "…");
        """
        createCharge.postScript = """
        pm.test("Charge created", () => pm.response.to.have.status(201));
        pm.test("Amount matches", () => pm.expect(pm.response.json().amount).to.eql(4200));
        pm.environment.set("charge_id", pm.response.json().id);
        """
        createCharge.mock = mock("{\"id\":\"ch_3NfK9b\",\"amount\":4200,\"currency\":\"eur\",\"status\":\"succeeded\"}", status: 201)

        var refund = request("Refund a charge", "POST", "/charges/:charge/refunds", folder: refunds.id)
        refund.pathVariables = [Field("charge", "{{charge_id}}")]
        let listRefunds = request("List refunds", "GET", "/refunds", folder: refunds.id)
        let replay = request("Replay an event", "POST", "/webhooks/events/:id/replay", folder: webhooks.id)
        let endpoints = request("List endpoints", "GET", "/webhooks/endpoints", folder: webhooks.id)
        let balance = request("Retrieve balance", "GET", "/balance")

        var payments = RequestCollection(name: "Payments API", requests: [listCustomers, getCustomer, createCustomer, updateCustomer, deleteCustomer, listCharges, createCharge, refund, listRefunds, replay, endpoints, balance])
        payments.folders = [customers, charges, refunds, webhooks]
        var defaults = RequestDefaults(); defaults.auth.kind = .bearer; defaults.auth.token = "{{api_token}}"
        defaults.headers = [Field("Acme-Version", "2026-10-01")]
        payments.defaults = defaults

        var token = APIRequest(name: "Get access token", method: "POST", url: "https://auth.acme.dev/oauth/token")
        token.auth.kind = .oauth2
        var oauth = OAuthConfiguration(); oauth.grant = .clientCredentials
        oauth.tokenURL = "https://auth.acme.dev/oauth/token"; oauth.authorizationURL = "https://auth.acme.dev/authorize"
        oauth.clientID = "acme-dashboard"; oauth.clientSecret = "sk_live_51Hc8••••"; oauth.scope = "charges:write customers:read"
        oauth.accessToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzY29wZSI6ImNoYXJnZXMifQ.k3J8"
        token.auth.oauth = oauth
        var me = APIRequest(name: "Current user", method: "GET", url: "https://auth.acme.dev/userinfo")
        me.auth.kind = .bearer; me.auth.token = "{{access_token}}"
        let identity = RequestCollection(name: "Identity", requests: [token, me])

        var search = APIRequest(name: "Search products", method: "POST", url: "https://shop.acme.dev/graphql")
        search.transport = .graphql
        var graph = GraphQLRequest()
        graph.query = """
        query SearchProducts($term: String!, $first: Int = 3) {
          products(query: $term, first: $first) {
            nodes {
              id
              title
              price { amount currencyCode }
              inventory { available }
            }
          }
        }
        """
        graph.variables = "{\n  \"term\": \"espresso\",\n  \"first\": 3\n}"
        graph.operationName = "SearchProducts"
        search.graphql = graph
        search.mock = mock("""
        {"data":{"products":{"nodes":[{"id":"gid://shop/Product/1081","title":"Espresso blend, 1 kg","price":{"amount":"24.00","currencyCode":"EUR"},"inventory":{"available":312}},{"id":"gid://shop/Product/1094","title":"Espresso cups, set of 4","price":{"amount":"36.00","currencyCode":"EUR"},"inventory":{"available":48}},{"id":"gid://shop/Product/1102","title":"Single-origin espresso","price":{"amount":"18.50","currencyCode":"EUR"},"inventory":{"available":0}}]}}}
        """, delay: 142)
        let storefront = RequestCollection(name: "Storefront GraphQL", requests: [search])

        var orders = APIRequest(name: "Order updates", method: "GET", url: "wss://stream.acme.dev/orders"); orders.transport = .websocket
        var metrics = APIRequest(name: "Live metrics", method: "GET", url: "https://stream.acme.dev/metrics"); metrics.transport = .sse
        let realtime = RequestCollection(name: "Realtime", requests: [orders, metrics])
        let shipping = RequestCollection(name: "Shipping", requests: [APIRequest(name: "Create label", method: "POST", url: "{{base_url}}/shipments/labels"), APIRequest(name: "Track parcel", method: "GET", url: "{{base_url}}/shipments/:id/events")])

        var push = RequestCollection(name: "Push notifications", requests: [APIRequest(name: "Send notification", method: "POST", url: "https://push.acme.dev/v2/send")]); push.workspaceID = mobileID

        var signing = Field("signing_secret", "whsec_9f2c41d8"); signing.secret = true
        var apiToken = Field("api_token", "sk_live_51Hc8Lr2eZvKYlo2C"); apiToken.secret = true
        let production = APIEnvironment(name: "Production", variables: [Field("base_url", "https://api.acme.dev/v1"), apiToken, Field("customer_id", "cus_8Kd2nQ"), signing, Field("region", "eu-west-1")])
        let staging = APIEnvironment(name: "Staging", variables: [Field("base_url", "https://staging.api.acme.dev/v1"), Field("api_token", "sk_test_4eC39HqLyjWDarjt"), Field("customer_id", "cus_test_51")])
        let local = APIEnvironment(name: "Local", variables: [Field("base_url", "http://localhost:4242/v1"), Field("api_token", "dev")])

        var result = Workspace(collections: [payments, identity, storefront, realtime, shipping, push], environments: [production, staging, local])
        result.selectedEnvironmentID = production.id
        result.globals = [Field("user_agent", "Acme Dashboard/4.2")]
        result.workspaces = [WorkspaceInfo(id: Workspace.defaultWorkspaceID, name: "Acme Payments"), WorkspaceInfo(id: mobileID, name: "Mobile Backend")]
        return result
    }()

    static func history(_ requests: [APIRequest]) -> [HistoryEntry] {
        let rows: [(String, Int?, Double, Double)] = [("List charges", 200, 0.118, 60), ("Create charge", 201, 0.231, 420), ("Get customer", 200, 0.084, 900),
                                                    ("Refund a charge", 402, 0.162, 1800), ("List customers", 200, 0.096, 3600), ("Get access token", 200, 0.312, 7200),
                                                    ("Search products", 200, 0.142, 10800), ("Delete customer", 404, 0.071, 86400), ("Retrieve balance", nil, 0, 90000)]
        return rows.compactMap { name, status, duration, age in
            guard let request = requests.first(where: { $0.name == name }) else { return nil }
            var entry = HistoryEntry(request: request, status: status, duration: duration, error: status == nil ? "The request timed out." : nil)
            entry.date = Date().addingTimeInterval(-age)
            return entry
        }
    }
}
