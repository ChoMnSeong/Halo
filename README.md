# Halo

맥북 노치(또는 노치 없는 화면의 가상 노치)를 아이폰 Dynamic Island처럼 쓰는 macOS 메뉴막대 앱.
화면 최상단에서 내려오는 단일 패널에 **모듈 탭**을 얹어, 파일 셸프·타이머·통화·알림·블루투스·즐겨찾기를 한곳에서.

> 메뉴막대 전용 accessory 앱(Dock 아이콘 없음) · 비샌드박스 · SwiftPM + ad-hoc 서명 · macOS 14+

## 기능 (모듈)

- **셸프** — 노치로 파일을 드래그해 임시 보관(사본 복사·영속), 칩을 드래그해 다시 꺼내기.
- **타이머** — 프리셋(+1·3·5·10·25분)으로 다중 타이머, 접힘 노치에 링+남은시간("always in sight"), 일시정지/취소.
- **통화** — 접근성으로 시스템 통화 배너 감지 → 노치 자동 펼침 + 받기/거절. *(권한 필요)*
- **알림** — 알림이 오면 노치 피크 + 알림 탭 피드. *(접근성 권한 필요)*
- **연결** — 블루투스 기기 연결/해제를 노치에 표시.
- **즐겨찾기** — 핀 고정 폴더/앱 그리드, 클릭해 열기, 드래그/＋로 추가.
- **설정** — 표시 화면 모드(노치 화면만 / 마우스 따라 / 모든 모니터), 전체화면 숨기기, 항상 펼치기, 로그인 시 실행.

노치 없는 디스플레이는 가상 노치로 대체. 화면 최상단에 flush 로 붙는 단일 패널(상단 오목 플레어).

## 설치 (Homebrew)

```sh
brew install --cask ChoMnSeong/tap/halo
```

공증(notarize) 미적용이라 cask 가 설치 시 격리(quarantine)를 제거합니다. 처음 실행 후
**시스템 설정 ＞ 개인정보 보호 ＞ 손쉬운 사용**에서 권한을 켜면 통화/알림이 동작합니다.

## 직접 빌드

```sh
./build.sh            # build/Halo.app 생성 (SwiftPM release + ad-hoc 서명)
./build.sh install    # 빌드 후 /Applications 로 설치
```

요구: macOS 14+ (Sonoma), Swift 5.9+. 앱 아이콘 재생성: `swift Tools/makeicon.swift` 후 `iconutil`.

## 권한

| 기능 | 권한 |
|---|---|
| 통화 · 알림 | 손쉬운 사용(Accessibility) — 시스템 알림 배너를 읽기 위함 |
| 연결 | 블루투스 |
| 로그인 시 실행 | (선택) 로그인 항목 |

권한을 안 줘도 다른 기능(셸프·타이머·즐겨찾기)은 정상 동작합니다.

## 구조 (`Sources/`)

노치 셸(실루엣·투과·다중화면·접힘/펼침 상태머신)과, 그 위에 끼우는 **`NotchModule` 모듈**들로 분리:
`ModuleRegistry` 가 모듈을 등록하고, 접힘 시 우선순위(`ModuleActivation`)로 노치를 점령, 펼침 시 탭으로 전환.

- `DynamicLakeApp` · `ScreenGeometry` · `NotchController`(NSPanel·투과·다중패널) · `NotchContentView`(패널 셰이프·탭바)
- `Modules`(프로토콜·레지스트리·셸프) · `TimerModule` · `CallsModule`/`NotificationsModule`/`NotificationsMonitor`(AX) · `ConnectModule`(IOBluetooth) · `FavoritesModule`

## 라이선스

개인 프로젝트. © 2026 ensnif
