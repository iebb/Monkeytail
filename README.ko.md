<p align="center"><img src="docs/brand/monkeytail-banner.png" alt="Monkeytail" width="880"></p>

[English](README.md) · [Español](README.es.md) · [Français](README.fr.md) · [日本語](README.ja.md) · **한국어** · [简体中文](README.zh-Hans.md)

# Monkeytail

**iPhone, iPad, Mac, Apple Vision Pro용 네이티브 API 클라이언트입니다. Postman과 Insomnia 컬렉션을 그대로 가져오고, 스크립트도 그대로 쓰며, 로그인은 필요 없습니다.**

Monkeytail은 이미 가진 컬렉션을 열어 똑같이 실행합니다. Monkeytail 계정도, 로그인 화면도, 클라우드 작업 공간도, 원격 분석도 없습니다. 요청은 서버로 바로 전송되고, 데이터는 기기나 본인의 iCloud Drive에만 저장됩니다.

<p><img src="docs/screenshots/iphone-request.png" alt="iPhone의 요청 편집기" width="285"> <img src="docs/screenshots/iphone-response.png" alt="iPhone의 JSON 응답" width="285"></p>

## 다운로드

**[App Store에서 다운로드](https://apps.apple.com/app/id6814706725)**: iPhone, iPad, Mac, Apple Vision Pro용으로 무료이며 앱 내 구입이 없습니다. 웹사이트: [monk.ieb.app](https://monk.ieb.app)

## Postman이나 Insomnia에서 옮겨 오기

- **모두 가져옵니다.** Postman 컬렉션(v1, v2, v2.1), 환경, 전역 변수, 전체 데이터 내보내기, Insomnia v4 및 v5 내보내기는 물론 Bruno, Hoppscotch, Thunder Client, HAR, `.http` 파일, OpenAPI/Swagger, cURL을 지원합니다. 여러 파일이나 폴더 전체를 한 번에 선택할 수 있습니다.
- **클라우드에서 바로 가져올 수도 있습니다.** Postman, Insomnia, Hoppscotch에 한 번 로그인해 동기화된 작업 공간을 가져오거나 GitHub 저장소를 지정하십시오. 세션은 해당 가져오기에만 사용되며 저장되지 않습니다.
- **스크립트가 그대로 동작합니다.** 요청 전 스크립트와 테스트 스크립트는 `pm.test`, `pm.expect`, `pm.sendRequest`, CryptoJS, lodash, moment를 포함한 Postman 호환 `pm` API로 실행됩니다. Insomnia, Bruno 등 다른 클라이언트의 스크립트는 호환 객체를 통해 실행됩니다.
- **사용 방식도 같습니다.** 인증, 헤더, 변수, 스크립트를 상속하는 작업 공간, 컬렉션, 중첩 폴더. 환경, 전역 변수, `{{$guid}}` 같은 동적 변수를 포함한 `{{변수}}`도 지원합니다.
- **언제든 내보낼 수 있습니다.** Postman v2.1, Insomnia v4 또는 손실 없는 Monkeytail JSON 파일.

## 그 밖의 기능

- HTTP, 인트로스펙션을 지원하는 GraphQL, WebSocket, 서버 전송 이벤트
- OAuth 2.0(PKCE), OAuth 1.0, JWT, AWS Signature V4, Digest, API 키, Basic, Bearer
- 반복 실행과 CSV/JSON 데이터 파일을 지원하는 컬렉션 실행기, JSON 또는 JUnit 보고서 내보내기
- 시각적 어서션, 저장된 예시, 오프라인 모의 응답, 로컬 모의 서버
- 서식 지정된 JSON, 트리, 검색, 비교, 이미지, 오디오, 비디오, 16진수를 보여 주는 응답 뷰어
- 13개 언어로 코드 생성, cURL 가져오기 및 내보내기
- 소요 시간 분석, TLS 세부 정보, HTTP/HTTPS/SOCKS5 프록시, 클라이언트 인증서, 선택적 브라우저 TLS 프로필
- 테마, 사용자 지정 색상 및 서체. 영어, 스페인어, 프랑스어, 일본어, 한국어, 중국어 간체 지원
- 본인의 iCloud Drive를 통한 동기화와 즐겨찾는 요청을 보낼 수 있는 Apple Watch용 동반 앱

자세히 보기: [API 도구](docs/APITools.md) · [스크립트](docs/Scripting.md) · [브라우저 프로필](docs/BrowserProfiles.md) · [예시 작업 공간](docs/examples)

## 빌드

Xcode에서 `Monkeytail.xcodeproj`를 열고 **Monkeytail**(iPhone 및 iPad), **MonkeytailMac** 또는 **MonkeytailVision** 스킴을 실행합니다. iOS 17, macOS 14 또는 visionOS 1 이상이 필요합니다. `project.yml`을 수정한 후에는 `xcodegen generate`를 실행하십시오.

## 테스트

```sh
swift test
```

## 라이선스

[BSD 3-Clause](LICENSE)
