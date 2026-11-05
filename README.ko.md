<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail — Kitta Co가 만든 iPhone, iPad, Mac용 HTTP 및 cURL 도구" width="880"></p>

# Monkeytail

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · **한국어** · [简体中文](README.zh-Hans.md)

**iPhone, iPad, Mac, visionOS용 네이티브 요청 디버거이며, 간결한 Apple Watch 컴패니언 앱을 함께 제공합니다.** 명령을 가져오고, 요청을 편집하고, 응답을 살펴볼 수 있습니다. SwiftUI로 만들었으며 iPhone용 간결한 편집기와 화면에 맞춰 조정되는 데스크톱 작업 공간을 갖추고 있습니다.

무료입니다. 앱 내 구입이 없습니다. 계정이 필요 없습니다. Kitta Co는 어떠한 데이터도 수집하지 않습니다.

[제품](https://docs.kitta.co/monkeytail/) · [개인정보 처리방침](https://docs.kitta.co/monkeytail/privacy/) · [지원](https://docs.kitta.co/monkeytail/support/) · [API 도구](docs/APITools.md) · [스크립팅](docs/Scripting.md) · [브라우저 프로필](docs/BrowserProfiles.md) · [릴리스 설정](docs/Release.md)

<p><img src="docs/screenshots/iphone-request.png" alt="헤더를 인라인으로 표시하는 iPhone용 Monkeytail 요청 편집기" width="285"> <img src="docs/screenshots/iphone-response.png" alt="iPhone의 Monkeytail JSON 응답 뷰어" width="285"></p>

[검증 결과 및 기기 스크린샷](docs/Verification.md)을 참조하십시오. Monkeytail, Postman, Insomnia용으로 가져올 수 있는 [예제 작업 공간](docs/examples)이 포함되어 있습니다.

## 실행

**`Monkeytail.xcodeproj`**를 엽니다. iPhone/iPad용은 **Monkeytail**, Mac용은 **MonkeytailMac**, visionOS용은 **MonkeytailVision**, Watch 컴패니언은 **MonkeytailWatch**를 선택합니다. iOS 17, macOS 14, visionOS 1 또는 watchOS 10이 필요하며, Mac에서 클라이언트 인증서를 가져오려면 macOS 15가 필요합니다. 빌드와 검증에는 Xcode 27을 사용합니다. 실제 기기와 iCloud를 사용하는 Mac 빌드에서는 서명 팀을 선택하십시오. Mac Debug 빌드는 애드혹 로컬 테스트를 위해 별도의 샌드박스 엔타이틀먼트를 사용하며, Release 빌드는 공유 iCloud 컨테이너를 활성화합니다.

생성된 Xcode 프로젝트는 저장소에 포함되어 있습니다. `project.yml`에서 타깃 설정을 변경했다면 [XcodeGen](https://github.com/yonaskolb/XcodeGen)으로 다시 생성하십시오.

```sh
xcodegen generate
```

시작용 컬렉션은 httpbin.org를 사용합니다. 요청은 **보내기**를 탭하거나 보내기 키보드 단축키를 사용할 때만 전송됩니다. 직접 운영하는 서버를 사용하려면 Playground 환경의 `base_url`을 바꾸십시오.

## 포함된 기능

- 네이티브 요청 편집기: 메서드, URL, `:name` 경로 변수, Postman 스타일 일괄 편집을 지원하는 헤더 및 쿼리 매개변수 활성화/비활성화, JSON/텍스트/URL 인코딩/multipart 본문과 바이너리 파일 업로드, 상속된 인증, bearer/basic/Digest, API 키, OAuth 1.0 서명, JWT Bearer(HS/RS/PS/ES 256–512, 전송할 때마다 로컬에서 서명하며 헤더 또는 쿼리 매개변수에 포함), PKCE 및 갱신을 지원하는 OAuth 2.0, AWS SigV4, 시간 제한, 리디렉션.
- 셸 인용, 여러 줄 명령, 데이터, JSON, 쿠키, basic 및 `--digest` 인증, 프록시 선택을 포함한 cURL 가져오기 및 내보내기. 가져오기 기능은 텍스트를 파싱할 뿐 셸을 실행하지 않습니다.
- 헤더, 인증, 변수, 스크립트를 상속하는 컬렉션과 중첩 폴더. 추가, 이름 변경, 복제, 삭제, 검색, 자동 로컬 저장을 지원합니다. iCloud Drive 동기화는 기본적으로 켜져 있으며 기기에 이미 로그인된 세션을 사용합니다. Monkeytail 계정은 없습니다.
- 이름이 지정된 환경, 작업 공간 전역 변수, 요청 전체에서의 `{{variable}}` 치환. 누락된 변수와 순환 참조를 감지하는 중첩 변수, 그리고 `{{$guid}}`, `{{$timestamp}}`, `{{$randomEmail}}` 같은 Postman 동적 변수를 지원합니다. 해석된 값은 URL 아래에 표시되며, `{{`를 입력하면 변수가 제안됩니다.
- 컬렉션 및 폴더 실행기: 반복 횟수, 지연, CSV/JSON 데이터 파일, `pm.execution.setNextRequest`/`skipRequest`, 실시간 성공/실패 결과, JSON 또는 JUnit 보고서 내보내기. 로컬에서 실행되며 계정이나 클라우드 실행기가 필요 없습니다.
- 실제 HTTP 전송, 취소, 응답 공유, 그리고 전송 계층이 보고한 헤더와 크기가 제한된 전송 본문을 포함하는 홉별 DNS/연결/TLS/업로드/서버/다운로드 진단.
- Chrome, Firefox, Safari용 선택적 [브라우저 TLS 및 HTTP/2 프로필](docs/BrowserProfiles.md)(iOS와 Mac에서는 iOS 및 Android 프리셋 포함). visionOS는 시스템 TLS를 사용합니다. 고정된 브라우저 라이브러리에 visionOS 슬라이스가 없기 때문입니다. 고정된 curl-impersonate를 사용해 로컬에서 실행되며, 인증서 검증은 계속 활성화되어 있습니다.
- JSON 보기 좋게 출력하기, 코어 라이브러리의 축소 기능, 구문 색상, 펼칠 수 있는 트리, 줄 검색, 복사, 요청 본문 서식 지정.
- 핀치 확대/축소를 지원하는 MIME 인식 이미지 미리보기, 네이티브 오디오/비디오 재생, 오프셋/ASCII Hex 및 Binary 뷰어. 지원되지 않는 미디어는 바이트로 검사하거나 저장할 수 있습니다.
- Postman 호환 `pm` 부분 집합을 갖춘 로컬 JavaScript 요청 전/응답 후 훅: Chai 스타일 `pm.expect`, `pm.response.to.*`, `pm.sendRequest`, 환경/컬렉션/전역 변수, 쿠키, 내장 CryptoJS, lodash 및 moment 부분 집합, 콘솔 로그. 스크립트는 가져온 것을 포함해 전송할 때마다 실행됩니다.
- 시스템 네트워킹 또는 사용자 지정 HTTP CONNECT, TLS로 감싼 HTTPS CONNECT, SOCKS5 프록시. 자격 증명을 선택적으로 지정할 수 있으며, 사용자 지정 프록시가 실패해도 직접 연결로 대체하지 않습니다.
- 매개변수 힌트, 예제, 이식 가능한 JSON Schema 검증을 지원하는 OpenAPI/Swagger JSON 및 YAML 가져오기.
- GraphQL 쿼리/변수/오퍼레이션 편집, 인트로스펙션, 검색 가능한 스키마 필드 제안.
- 텍스트/JSON/바이너리 검사, 필터, ping, 취소, 재연결을 지원하는 WebSocket 및 SSE 타임라인.
- 환경별 기기 로컬 쿠키 저장소, 정확한 호스트에 대한 PKCS#12 클라이언트 ID, 자체 서명 인증서에 대한 호스트별 신뢰(검증을 끄는 대신 SHA-256 지문으로 고정). 시스템 전송 진단은 인증서 체인, 유효 기간, 협상된 TLS/암호 스위트 식별자, 프로토콜을 표시합니다.
- 시각적 상태/시간/헤더/JSONPath/스키마 어서션, 성공/실패 결과, 편집 가능한 JavaScript 검사.
- cURL, JavaScript fetch, Node.js axios, Python requests, Go, Java HttpClient, C# HttpClient, PHP cURL, Ruby Net::HTTP, Swift URLSession, Kotlin OkHttp, HTTPie, PowerShell용 코드 스니펫(자격 증명 숨기기 선택 가능).
- 요청별로 저장된 응답 예제(Postman `response` 예제), 예제·현재 응답·스냅샷으로 만드는 오프라인 응답 목, 지연/상태/오류 설정, 포그라운드 루프백 목 서버.
- Mac과 iPad의 요청 탭(다시 실행할 때 복원), 요청·폴더·컬렉션용 Markdown 문서, 샌드박스화된 HTML 응답 미리보기.
- Postman(v1, v2/v2.1 컬렉션, 환경, 전역 변수, 전체 데이터 덤프), Insomnia(v4 JSON/YAML 및 v5 YAML), Bruno(`.bru` 폴더 및 JSON 내보내기), Hoppscotch, Thunder Client, HAR, VS Code REST Client/JetBrains `.http` 파일, OpenAPI, cURL에서 가져오기. 여러 파일이나 폴더 전체를 한 번에 선택할 수 있습니다.
- 다른 앱에서 바로 가져오기: Postman, Insomnia 또는 Hoppscotch에 해당 앱과 같은 방식으로 로그인해 동기화된 컬렉션을 가져오거나, GitHub 저장소를 연결합니다. 모든 컬렉션, 환경, 전역 변수를 가져옵니다. 세션과 토큰은 해당 가져오기에만 사용되며 저장되지 않습니다. Monkeytail에는 여전히 계정이 없습니다.
- Postman v2.1 컬렉션 내보내기와 Insomnia v4 JSON 내보내기. 현재 버전의 Insomnia에서도 이 레거시 형식을 가져올 수 있습니다.
- 모든 정보를 보존하는 Monkeytail 작업 공간 JSON 가져오기/내보내기, 파일 앱 통합, 시스템 공유 시트.
- 검색, JSON/상태/헤더 비교, JSONPath 추출(`$`, 키, 인덱스, 와일드카드)을 지원하는 저장된 응답 스냅샷. 스냅샷은 로컬에만 보관되며 60 MB 이내에서 최대 50개까지 유지됩니다.
- 상태와 소요 시간이 포함된 최근 50개 요청 정의의 기록. 자동으로 다시 전송하지 않고 복원할 수 있습니다.
- 라이트/다크 모드, Dynamic Type, VoiceOver 레이블, 하드웨어 키보드 보내기 단축키(⌘↵), 세로/가로 방향에 맞춰 조정되는 레이아웃.

## 기기별 레이아웃

사이드바는 Postman과 같은 방식으로 동작합니다. 맨 위에 작업 공간 전환기가 있고, 그 아래에 해당 작업 공간의 모든 컬렉션이 중첩된 폴더와 요청의 트리로 표시됩니다. 각 작업 공간은 자체 컬렉션, 환경, 전역 변수를 가지며, 기존 데이터는 **내 작업 공간**에 있습니다. 요청과 폴더는 **이동** 또는 드래그로 옮길 수 있으며, 폴더는 **+** 또는 컬렉션·폴더·요청의 메뉴에서 추가할 수 있습니다. 인터페이스는 영어, 스페인어, 프랑스어, 일본어, 한국어, 중국어 간체로 제공되며 기기 언어를 따릅니다.

색상은 기본적으로 디자인 시스템을 따릅니다. **설정 → 테마 및 서체**에서는 여섯 가지 프리셋(Monkeytail, Navy, Ocean, Ember, Grape, Graphite), 시스템/라이트/다크 화면 모드, 그리고 강조, 캔버스, 표면, 경고, 위험, 정보, 기타 메서드, 오류에 대한 역할별 라이트 및 다크 색상을 제공합니다. 기기에 설치된 서체 중에서 인터페이스용과 코드용 서체를 따로 선택할 수도 있습니다. 테마는 기기에 저장되며 모든 윈도우에 즉시 적용됩니다.

iPhone 레이아웃은 간결한 편집기 위에 메서드와 URL을 항상 표시합니다. **보내기/취소**와 **요청/응답**은 엄지손가락이 닿는 하단에 있으며, 편집 중에는 키보드 위로 이동합니다. 헤더와 매개변수의 이름과 값은 44포인트 컨트롤과 함께 한 줄에 표시됩니다. 휴대폰에서 검색어를 입력하는 동안에는 응답 탭이 접혀 일치하는 줄이 키보드 위에 계속 보입니다. 선택적 도움말은 접혀 있으며, 요청 이름은 내비게이션 바에서 바로 편집할 수 있습니다. cURL 공유는 동작 메뉴에 있습니다.

레이아웃은 **사용 가능한 윈도우 크기**를 따릅니다.

| 사용 가능한 공간 | 레이아웃 |
| --- | --- |
| 좁은 휴대폰 / 접힌 윈도우 | 하단의 요청/응답 전환. 컬렉션은 뒤로/사이드바 버튼으로 표시 |
| 최소 640 × 440포인트의 iPad 상세 영역 | 요청과 응답을 나란히 표시 |
| 높이가 낮은 가로 방향 휴대폰 윈도우 | 편집기를 사용할 수 있도록 단일 창 |
| 최소 1,100포인트 너비의 윈도우 | 컬렉션 사이드바와 요청 및 응답 패널 |
| 절반쯤 펼친 폴더블, 화면을 가로지르는 접힘(테이블톱) | 힌지 위에 응답, 아래에 URL, 보내기, 요청 편집기. 접히는 부분에 걸치는 요소는 없음 |
| 손쉬운 사용 텍스트 크기 | 텍스트를 읽기 쉽게 유지하는 단일 창 편집기 |

선택 상태와 편집기 상태는 너비 변경, 회전, iPad 윈도우 크기 조정, 폴더블 크기 변경 후에도 유지됩니다. iOS 27.1 이상에서 테이블톱 레이아웃은 `UIHingeInteraction`(부분적으로 펼침)과 시스템의 `.division` 예약 영역을 따르므로, 분할 위치가 보고된 접힘 위치와 정확히 일치하며 양쪽에 7포인트의 여유 공간이 생깁니다. 힌지가 완전히 펼쳐졌거나 닫혀 있거나 접힘이 가로 방향이 아니면 일반 레이아웃이 적용됩니다.

## Apple Watch 컴패니언

iPhone의 동작 메뉴에서 요청에 별표를 표시합니다. **Apple Watch**를 열고 즐겨찾기를 탭해 복사한 다음, 페어링된 앱이 설치되어 있으면 **동기화**를 탭합니다. Watch에는 최대 10개의 사본이 표시됩니다. 하나를 열어 **보내기** 또는 **취소**를 탭한 다음 상태, 시간, 헤더 또는 Pretty/Raw/Hex 텍스트를 확인합니다. Watch에는 요청 편집기나 자동 폴링 기능이 없습니다.

선택된 환경과 상속된 헤더/인증은 복사할 때 해석됩니다. **자격 증명 및 본문 포함**은 저장되는 옵션이며, 직접 끄지 않았다면 켜져 있습니다. 사본은 기본적으로 로컬 파일을 사용하며, 선택적으로 키체인 저장소와 WatchConnectivity의 최신 애플리케이션 컨텍스트를 사용합니다. 요청을 편집하거나 환경을 변경하면 다시 복사해야 합니다. 동기화하면 더 이상 즐겨찾기가 아닌 사본은 제거됩니다. Watch는 자체적으로 HTTP 요청을 보내므로 Watch에서 서버에 접근할 수 있어야 합니다. 응답은 메모리에만 유지됩니다. 실제로 페어링된 기기 간 전송은 아직 하드웨어 검증이 필요합니다.

Watch는 시스템 HTTP/GraphQL, 검증된 HTTPS, 수동으로 입력한 basic/bearer/API 키 헤더를 지원합니다. 프록시, 브라우저 TLS 프리셋, 클라이언트 ID, 쿠키, OAuth/JWT/AWS, 스크립트, 목, WebSocket, SSE는 전체 앱에서만 사용할 수 있습니다. 지원되지 않는 구성은 복사하기 전에 오류를 표시합니다. 시간 제한은 최대 30초, 복사되는 본문은 최대 32 KB, 전송은 최대 60 KB, 응답은 최대 256 KB, 표시되는 본문은 최대 16 KB입니다.

visionOS 윈도우는 전체 작업 공간 편집기, 응답 뷰어, API 도구, iCloud 컨테이너를 iPhone 및 Mac과 공유합니다. visionOS에서는 시스템 TLS를 선택하십시오. 그곳에서는 브라우저 TLS 프리셋을 사용할 수 없습니다. 시스템 전용 Swift 패키지와 Watch용 Swift 패키지는 저장소에 포함된 심볼릭 링크를 통해 원본 소스를 연결하므로, 지원되지 않는 플랫폼에서 iOS/Mac용 curl 바이너리를 사용하지 않습니다.

버전 1.4는 Watch 컴패니언을 포함한 iPhone/iPad, Mac, visionOS용으로 제공됩니다. 버전 1.5는 세 플랫폼 모두에서 App Review를 기다리고 있습니다. 빌드와 검증 내용은 [릴리스 기록](docs/app-store/README.md)을 참조하십시오. 실제 페어링된 Watch로의 전송과 실시간 iCloud 전송은 아직 검증되지 않았습니다.

Mac에서는 기본적으로 요청과 응답이 크기를 조정할 수 있는 분할 화면에 위아래로 배치됩니다. **작업 공간 동작 → 작업 공간 레이아웃**을 선택하면 나란히 배치할 수 있으며, 분할 위치는 레이아웃별로 기억됩니다. 사이드바는 직접 숨길 때까지 크기를 조정하는 동안에도 열려 있습니다. 설정은 네이티브 설정 윈도우에서 열립니다. 요청을 찾으려면 ⌘F, 가져오기/내보내기는 ⇧⌘I, cURL 내보내기는 ⇧⌘E, 새 요청은 ⌘N, 보내기 또는 취소는 ⌘Return을 사용합니다.

## 상호 교환 범위

Monkeytail 작업 공간 JSON은 모든 모델 필드, 환경, 프록시 설정을 보존합니다. 가져오기는 컬렉션과 환경을 추가하고 새 ID를 생성하며, 네이티브 가져오기는 저장된 프록시 설정도 적용합니다. 가져온 스크립트는 Postman과 마찬가지로 전송할 때 실행됩니다. 각 스크립트 탭에서 내용을 검토하거나, **스크립트 실행**을 꺼서 건너뛸 수 있습니다.

Postman 내보내기는 중첩 폴더를 보존하며 **활성 환경**을 컬렉션 변수로 내보냅니다. Postman 가져오기는 폴더 계층과 상속된 헤더, 인증, 변수, 스크립트를 보존합니다. Raw, URL 인코딩, multipart, 파일, GraphQL JSON 본문을 지원합니다. 스크립트는 보존되며, 실행 시에는 [스크립팅](docs/Scripting.md)에 문서화된 API를 지원합니다.

Insomnia v4 JSON/YAML 내보내기와 v5 YAML 컬렉션은 폴더 트리와 함께 가져옵니다. 기본 환경은 컬렉션 변수가 되고, 하위 환경은 환경이 되며, 폴더 환경·헤더·인증·스크립트는 폴더 기본값이 됩니다. `{{ _.variable }}` 및 `{{ _['variable'] }}` 참조는 정규화됩니다. 템플릿 태그(응답 체이닝 등)는 알림을 표시하고 텍스트로 남으며, gRPC 요청은 건너뜁니다.

Bruno 컬렉션 폴더(`bruno.json`, `collection.bru`, `folder.bru`, `environments/`)와 JSON 내보내기는 폴더, 기본값, 비밀 환경 변수, 스크립트, 어서션(테스트로 변환)을 유지합니다. Hoppscotch 컬렉션과 환경은 `<<variable>>` 참조를 변환하고 모든 인증 유형을 유지합니다. Thunder Client 컬렉션은 선언적 테스트를 스크립트로 변환합니다. HAR 파일은 요청을 호스트별로 묶고 기록된 응답을 저장된 예제로 유지합니다. `.http`/`.rest` 파일은 `@variables`, `# @name`, 본문, `> {% %}` 응답 핸들러를 유지합니다. 이러한 클라이언트용으로 작성된 가져온 스크립트는 호환성 객체와 함께 실행됩니다. [스크립팅](docs/Scripting.md#other-clients)을 참조하십시오.

가져오기 → **Postman, Insomnia, Hoppscotch 또는 GitHub에서 가져오기**:

- **Postman:** Monkeytail은 Postman 데스크톱 앱과 같은 방식으로 로그인합니다. **Postman에 로그인**은 비공개 브라우저 세션에서 Postman 자체 로그인 페이지(이메일 및 암호, GitHub 또는 SSO)를 표시하고, 마지막 리디렉션에서 세션을 읽습니다. 그런 다음 Monkeytail은 Postman 게이트웨이를 통해 작업 공간 목록을 가져오고, 선택한 각 작업 공간의 컬렉션, 환경, 전역 변수를 데스크톱 앱이 저장하는 v1 형식으로 Postman 동기화 서비스에서 가져옵니다. 미국과 EU 계정을 모두 지원합니다. 여러 작업 공간을 가져오면 환경 이름 앞에 작업 공간 이름이 붙습니다.
- **Insomnia:** Monkeytail은 Insomnia 데스크톱 앱과 같은 방식으로 로그인합니다. **Insomnia에 로그인**은 일회용 키와 함께 Insomnia 웹 사이트를 엽니다. 표시되는 코드를 붙여넣으십시오. Monkeytail은 봉인된 로그인 상자를 열고, 계정의 종단 간 암호화 키를 잠금 해제하고, 모든 조직의 Cloud Sync 프로젝트 목록을 가져온 다음, 선택한 각 프로젝트의 기본 브랜치에서 최신 스냅샷을 가져옵니다. 문서는 기기에서 복호화됩니다. 로컬 프로젝트와 Git Sync 프로젝트는 Insomnia 클라우드에 없으므로 GitHub 옵션을 사용하거나 파일로 내보내십시오.
- **Hoppscotch:** 이메일을 입력해 로그인 링크를 받은 다음, 링크를 열지 말고 붙여넣으십시오. hoppscotch.io에서는 웹 앱의 이메일 링크 로그인이고, 자체 호스팅 서버(백엔드 URL 입력)에서는 데스크톱 앱의 매직 링크입니다. 개인 컬렉션과 환경, 전역 변수, 그리고 모든 팀의 컬렉션과 환경을 가져옵니다. 팀 환경 이름 앞에는 팀 이름이 붙습니다.
- **GitHub:** `owner/repo`, `owner/repo@branch` 또는 폴더 URL(`…/tree/branch/folder`)을 입력합니다. 모든 Postman, Insomnia Git Sync, Bruno, Thunder Client, Hoppscotch, `.http`, HAR, OpenAPI 파일을 가져오며, 각 Bruno 컬렉션은 해당 컬렉션의 `bruno.json`을 기준으로 해석됩니다. 공개 저장소에는 토큰이 필요 없고, 비공개 저장소에는 읽기 전용 세분화된 토큰을 사용하십시오. 최대 1,000개 파일, 40 MB까지 가져옵니다.

Bruno와 Thunder Client는 컬렉션을 파일 또는 Git에 저장합니다. 자격 증명과 세션은 쿠키나 캐시 없이 임시 세션을 통해 선택한 서비스로만 전송되며, 가져오기가 끝나면 폐기됩니다.

서드파티 형식은 요청 시간 제한이나 전역 프록시 선택 같은 일부 Monkeytail 설정을 보존하지 않습니다. 지원되지 않는 인증은 가져오기 알림을 표시하고, 지원되지 않는 cURL 플래그는 명시적인 오류를 발생시킵니다. 가져온 파일 경로는 메타데이터일 뿐이므로, 전송하기 전에 파일 앱이나 사진 앱에서 각 파일을 선택하십시오. 네이티브 작업 공간 내보내기에는 파일 바이트가 포함되며, Postman/Insomnia/cURL 내보내기는 파일 이름을 참조합니다. 서드파티 내보내기와 함께 실제 첨부 파일을 전달하려면 본문 → 파일 내보내기를 사용하십시오. gRPC, 계정 및 팀 작업 공간, 클라우드 모니터/목, 다른 클라이언트의 완전한 스크립팅 런타임은 이 버전의 범위에 포함되지 않습니다. Monkeytail은 로그인을 요구하지 않습니다. OpenAPI 가져오기와 JSON Schema 검증에는 명시적으로 지원되는 부분 집합이 있습니다. [API 도구](docs/APITools.md)를 참조하십시오.

브라우저 프로필은 네이티브 JSON과 `curl-impersonate --impersonate` 명령을 통해 내보내고 다시 가져올 수 있습니다. Postman 및 Insomnia 내보내기에는 Monkeytail로 다시 가져오기 위한 `_monkeytail` 메타데이터가 포함되지만, 해당 앱들이 브라우저 프로필을 직접 적용하지는 않습니다.

## 데이터와 네트워킹

작업 공간과 기록은 앱의 Application Support 디렉터리에 저장되며, 플랫폼 파일 보호와 Mac 앱 샌드박스를 사용합니다. 작업 공간 자격 증명과 기록은 기본적으로 로컬 파일을 사용합니다. **키체인 사용**은 선택 사항이며 작업 공간 자격 증명, 쿠키, 클라이언트 ID, Watch 사본에 적용됩니다. 이 옵션이 꺼져 있으면 시작할 때 키체인을 조회하지 않습니다. 이전 키체인 값은 그대로 유지되며 옵션을 켜면 복원할 수 있습니다. 내보내기에는 저장된 값이 포함됩니다. 분석 기능이나 Kitta가 운영하는 백엔드는 없습니다. iCloud Drive 동기화는 기본적으로 켜져 있으며, 버전 1.6.3에서는 기존 설치에 대해 한 번 동기화를 켭니다(로컬에만 유지하려면 설정에서 **iCloud 동기화**를 끄십시오). 동기화는 컬렉션, 환경, 스크립트, 자격 증명을 기기 간에 공유하며, 각 항목을 가장 최근 편집을 기준으로 병합하고 삭제 툼스톤을 유지합니다. 서로 다른 요청에 대한 편집은 동시에 변경되어도 유지되며, 같은 항목에 대해서는 가장 최근 편집이 적용됩니다. 원격 변경 사항을 적용하기 전에 보호된 로컬 복구 사본이 보관됩니다. 앱은 오프라인에서도 사용할 수 있으며, 활성 상태일 때와 포그라운드로 전환될 때 동기화를 확인합니다. **자격 증명 포함**은 인증 및 자격 증명 필드가 iCloud 동기화에 포함되는지를 제어합니다. 직접 끄지 않았다면 켜져 있으므로, 기본적으로 모든 항목이 동기화됩니다. 쿠키, 클라이언트 ID, 첨부 파일, 스냅샷, 요청 기록은 로컬에 유지됩니다. `Authorization`이나 `X-API-Key` 같은 필드는 자동으로 민감한 항목으로 표시되지 않으며 계속 보입니다. **민감한 항목으로 표시**를 사용하면 값이 가려집니다. **자격 증명 포함**이 꺼져 있거나, **키체인 사용**이 켜져 있거나, 코드 숨기기가 켜져 있으면 자격 증명처럼 보이는 이름은 일반 항목으로 표시하지 않는 한 계속 보호됩니다. 가져오거나 동기화된 스크립트는 기기별로 사용 동의가 필요합니다. 기기의 iCloud 세션을 전환하려면 동기화를 껐다가 다시 켜야 합니다. 응답 본문은 스냅샷으로 명시적으로 저장하거나 내보내기 전까지 메모리에만 유지됩니다. 오디오/비디오 미리보기는 보호된 임시 파일을 사용하며, 캐시된 응답이 해제되면 삭제됩니다. 중단된 세션이 남긴 파일은 하루가 지나면 앱 실행 시 정리됩니다. 명시적으로 저장하면 원본 바이트가 내보내집니다. 쿠키는 요청별로 선택해 사용하며, 환경마다 별도의 기기 로컬 저장소를 사용합니다. 세션은 Safari 쿠키를 사용하지 않습니다. OAuth는 임시 브라우저 세션에서 공급자를 열며, Monkeytail 계정을 만들지 않습니다. 클라이언트 ID는 파일 또는 선택적 키체인 저장소에 기기 로컬로 유지됩니다. 목 서버는 127.0.0.1에만 바인딩되며 앱이 백그라운드로 전환되면 중지됩니다. TLS 신뢰 검증은 계속 활성화되어 있으므로, 필요하면 iOS 설정에서 디버깅용 CA를 설치하고 신뢰하십시오. 이 앱은 범용 API/디버깅 클라이언트이므로 ATS에서 HTTP를 허용합니다.

응답은 20 MB로 제한되며, 텍스트/트리 및 바이트 미리보기는 1 MB로 제한됩니다. 이미지는 최대 2,048픽셀 미리보기로 디코딩되며, 저장할 때는 원본이 유지됩니다. 오디오/비디오 재생은 다운로드된 파일만 사용하며 외부 미디어 참조는 비활성화됩니다. JSON 서식 지정, 트리 준비, 줄 분할은 메인 스레드 밖에서 실행됩니다. 텍스트와 트리 행은 지연 렌더링되고, 검색 중에는 줄 배열이 재사용되며, 구문 강조는 긴 줄에 대한 길이 제한이 있는 하나의 컴파일된 표현식을 사용합니다. 응답 캐시는 40 MB 이내에서 최대 8개의 응답을 보관합니다. 가져오기는 40 MB, 업로드는 20 MB, iCloud 메타데이터는 20 MB로 제한됩니다. JSONPath와 JSON 비교는 노드/변경 수 제한과 함께 최대 2 MB의 본문에서 동작합니다. JavaScript 컨텍스트는 3초의 실행 기한이 있고, 임시 WebKit 데이터 저장소를 사용하며, 직접적인 네트워크/DOM 탐색을 차단합니다. 유일한 네이티브 브리지는 `pm.sendRequest`이며, 선택된 프록시를 통해 스크립트당 10개의 HTTP(S) 요청으로 제한됩니다. 파일이나 앱 브리지는 없습니다. 시간 제한을 초과한 컨텍스트는 폐기됩니다. 스크립트는 편의를 위한 API이며 범용 Node.js 런타임이 아닙니다.

## 검증

순수 모델, 파서, 컬렉션, 인코딩, JSON, 프록시 구성, multipart, 동기화 병합/툼스톤/비밀 값, JSONPath, 응답 비교 테스트:

```sh
swift test
```

시뮬레이터 통합 테스트와 UI 테스트는 로컬 HTTP, TLS/HTTP2, CONNECT, SOCKS5 픽스처를 사용하며 공개 API에 의존하지 않습니다.

```sh
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone Duo'
# Or pass another installed simulator destination, e.g.:
./Scripts/test.sh 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.0'
```

이 테스트 모음은 전송, 실제 통신상의 TLS ClientHello 및 HTTP/2 SETTINGS, 인증서 거부, 브라우저 헤더 재정의, 리디렉션, 출처 간 자격 증명 제거, 취소, 제한, 두 가지 프록시 프로토콜, 스크립트 변경/어서션/오류/시간 초과/네트워크 차단, 키체인 저장, 스냅샷 제거, 두 전송 방식에서의 multipart/바이너리 업로드, 홉별 진단, 그리고 세로 및 가로 방향에서의 전송 → 검사 → 가져오기 → 편집 → cURL 내보내기 UI 흐름을 검증합니다. UI 테스트는 격리된 임시 작업 공간을 사용하며 사용자의 일반 컬렉션을 변경하지 않습니다.

## 프로젝트 구조

```text
Sources/MonkeytailCore/  Codable models, request builder, HTTP transport, cURL,
                        collection codecs, JSON formatting/tree
Sources/MonkeytailCurl/  Small C bridge for the static browser transport
Vendor/                 Pinned curl-impersonate XCFramework and provenance
Monkeytail/Services/    Observable workspace/persistence and WebKit script runner
Monkeytail/Views/       Native adaptive SwiftUI interface
Tests/                 Core Swift package tests
MonkeytailMac/         Mac sandbox/iCloud entitlements and app metadata
MonkeytailMacTests/    Shared advanced hosted integration tests
MonkeytailVision/      Native visionOS app and shared iCloud entitlements
MonkeytailWatch/       Compact favourite-request companion and WatchConnectivity
Packages/              System-only visionOS and bounded Watch core packages
MonkeytailTests/       Hosted simulator integration tests
MonkeytailUITests/     End-to-end device UI tests
Scripts/               Local verification and network fixtures, samples, icon packaging
docs/                  Scripting, release metadata, branding, screenshots
```

프로토콜 참고 자료: [Apple 프록시 구성](https://developer.apple.com/documentation/network/proxyconfiguration), [WebKit JavaScript 실행](https://developer.apple.com/documentation/webkit/wkwebview/callasyncjavascript(_:arguments:in:in:completionhandler:)), [Postman 스키마](https://schema.postman.com/), [Insomnia 가져오기/내보내기](https://developer.konghq.com/insomnia/import-export/).

## 라이선스

[BSD 3-Clause License](LICENSE)에 따라 배포됩니다. 공개 제품, 지원, 개인정보 처리방침 페이지는 [docs.kitta.co](https://docs.kitta.co/monkeytail/)에서 호스팅됩니다.

서드파티 구성 요소는 각자의 라이선스를 따르며, 해당 고지는 설정 → 라이선스에 포함되어 있습니다. 고정된 바이너리와 재생성 절차는 [벤더 출처 정보](Vendor/README.md)를 참조하십시오.
