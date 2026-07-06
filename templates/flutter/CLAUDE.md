# Flutter 모바일 가이드

팀 공통 규격(`agent-cairn/CLAUDE.md`)을 기준으로, 본 문서는 Flutter 기반 모바일 프로젝트에 특화된 규약을 정의합니다.

> **설계 철학**: 본 가이드는 **번호형 레이어드 클린 아키텍처**(의존 방향을 폴더 번호로 강제)를 팀 공통 뼈대로 삼되, **상태관리·에러 처리·네트워크 라이브러리는 프로젝트가 선택**하도록 열어 둡니다. 아키텍처(불변)와 기술 선택(가변)을 분리해, 여러 팀이 자신에게 맞는 스택을 고르면서도 동일한 구조·의존 규칙을 공유하게 하는 것이 목표입니다.

---

## 1. 아키텍처 — 번호형 레이어드 클린 아키텍처

폴더 최상위 레이어에 **2자리 번호 접두사**를 붙여 **정렬 순서 = 의존성 흐름 순서**가 되게 합니다. 이름형 구조(`data/`, `domain/`)는 의존 규칙을 문서로만 지키지만, 번호형은 "무엇을 import해도 되는지"를 구조로 드러내 리뷰에서 역방향 의존을 바로 잡을 수 있습니다.

```
lib/
├── main.dart               # 앱 진입점 (상태관리 루트 · MaterialApp.router)
├── 00_config/              # Composition Root — di · router · network · theme · env · constants
├── 01_presentation/<f>/    # pages · widgets · 상태관리 컨트롤러(선택한 라이브러리에 따름)
├── 02_application/<f>/     # usecases — 1 UseCase = 1 비즈니스 동작 (callable class)
├── 03_domain/<f>/          # entities · repositories(추상 인터페이스) · failures   ← 순수 Dart
└── 04_infra/<f>/           # datasources · dtos · mappers · repositories(구현체)
```

- **최상위 레이어 폴더에만** `NN_` 번호. 그 아래 **기능 폴더(`<f>`)는 번호 없이** snake_case. 하나의 기능(`auth` 등)이 `01~04`를 수직으로 관통한다.
- 레이어 공용 자산은 각 레이어의 `shared/` 하위에 둔다.

### 1.1 의존성 규칙 (위반 금지)

```
01_presentation → 02_application → 03_domain ← 04_infra
00_config → (모든 레이어를 알고 배선; 그러나 어떤 레이어(01~04)도 00_config 를 import 하지 않음. 배선은 레이어 밖 진입점 main.dart 에서만 주입한다)
```

- 화살표 방향으로만 import. **역방향 금지.**
- `03_domain` 은 **순수 Dart** — Flutter/Dio/상태관리 등 어떤 외부 인프라도 import하지 않는다. (함수형 에러 처리에 fpdart 를 쓰는 경우, fpdart 는 순수 Dart 라 예외적으로 허용.)
- `04_infra` 는 `03_domain` 의 인터페이스를 **구현**하고 외부 SDK 를 안다. `01`/`02` 를 몰라야 한다.
- 구체 구현을 인터페이스에 주입하는 **배선은 오직 `00_config/di/`** 에서만 한다. (Composition Root)

### 1.2 레이어별 책임

| 레이어 | 책임 | 의존 |
| --- | --- | --- |
| `03_domain` | Entity(순수 값 객체, 직렬화 없음) · Repository 인터페이스(추상) · 도메인 에러 타입(선택한 전략에 따라 `Failure`/도메인 예외 등) | 없음 (순수 Dart) |
| `02_application` | UseCase — 1 동작, Repository **인터페이스에만** 의존 | `→ 03_domain` |
| `04_infra` | DataSource(API 클라이언트) · DTO(직렬화) · Mapper · RepositoryImpl(raw 예외를 경계에서 잡아 도메인 에러로 변환) | `→ 03_domain` + 외부 SDK |
| `01_presentation` | Page · Widget(순수 지향) · 상태관리 컨트롤러 | `→ 02_application → 03_domain` |
| `00_config` | 전역 배선/프레임워크 설정만 (비즈니스 로직 금지) | 전 레이어를 알고 배선 |

### 1.3 새 기능 추가 순서 (안쪽부터, 각 단계 실패 테스트 → 구현)

1. `03_domain`: Entity + Repository 인터페이스(+ 필요 시 도메인 에러 타입)
2. `02_application`: UseCase — Repository 인터페이스에만 의존
3. `04_infra`: DTO + Mapper + DataSource + RepositoryImpl(예외를 경계에서 잡아 Failure/도메인 에러로 변환)
4. `00_config/di`: 구현체를 **인터페이스 타입으로** 주입 (구현 은닉)
5. `01_presentation`: 상태관리 컨트롤러 + Page/Widget
6. `00_config/router`: 라우트 등록

### 1.4 올바른 모양 (예시 — 상태관리·에러 전략 비의존 뼈대)

> 아래는 예외 기반 에러 전략을 쓰는 최소 뼈대다. fpdart 를 채택하면 반환 타입을 `TaskEither<Failure, User>` 로 바꾸고 `TaskEither.tryCatch` 로 경계 변환을 하면 된다(§3). 엔티티/DTO 예시는 Freezed 3.x 문법(단일 생성자 `abstract class`, 유니온 `sealed class`)을 사용한다.

```dart
// 03_domain/auth/entities/user.dart — 순수 엔티티 (직렬화 없음)
@freezed
abstract class User with _$User {
  const factory User({required String id, required String email}) = _User;
}

// 03_domain/auth/repositories/auth_repository.dart — 추상 인터페이스
abstract class AuthRepository {
  Future<User> login({required String email, required String password});
}

// 02_application/auth/usecases/login.dart — UseCase (callable class)
class Login {
  Login(this._repository);
  final AuthRepository _repository;
  Future<User> call({required String email, required String password}) {
    return _repository.login(email: email, password: password);
  }
}

// 04_infra/auth/repositories/auth_repository_impl.dart — 구현 (DTO→Entity 변환, 예외를 경계에서 처리)
class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._api);
  final AuthApi _api;
  @override
  Future<User> login({required String email, required String password}) async {
    try {
      final dto = await _api.login(LoginRequestDto(email: email, password: password));
      return dto.toEntity(); // DTO 는 이 레이어 밖으로 노출하지 않는다
    } on Exception catch (error) {
      // 예외는 이 경계에서만 처리한다 — raw 예외(Dio 등)를 상위로 전파하지 않고
      // 선택한 에러 전략에 맞는 도메인 에러로 변환한다.
      throw _mapToDomainError(error);
    }
  }
}

// 00_config/di/auth_providers.dart — 배선 (반환 타입은 반드시 "인터페이스")
// 아래는 개념 예시이며, 실제 표기는 선택한 상태관리/DI 도구의 관례를 따른다.
```

**금지 패턴**

```dart
// 금지: 위젯/컨트롤러에서 직접 API·DB 호출 (반드시 UseCase 경유)
class _MyPageState extends State<MyPage> {
  @override
  void initState() {
    super.initState();
    http.get(Uri.parse('https://api...')); // NO
  }
}

// 금지: 하드코딩된 색상/문구 (테마·상수/i18n 경유)
Text('로그인', style: TextStyle(color: Color(0xFF123456))); // NO

// 금지: 03_domain 이 외부 인프라를 import (Dio/Flutter/상태관리 패키지)
// 금지: DTO 를 02/01 레이어로 노출 · 레이어 역방향 import · 00_config 밖에서 배선
```

---

## 2. 상태관리 — 프로젝트가 선택, 일관 적용

**아키텍처(번호형 레이어 + 의존 규칙)는 상태관리와 독립적입니다.** 상태관리 라이브러리는 오직 `01_presentation` 의 "컨트롤러 자리"와 `00_config/di` 의 배선 표기에만 영향을 줍니다. `02~04` 레이어는 어떤 선택에도 동일합니다.

- 팀/프로젝트는 **Riverpod · GetX · BLoC 중 하나를 초기에 선택**하고, 한 프로젝트 안에서 **끝까지 일관** 적용한다. (**혼용 금지.**)
- 선택을 `__docs/ADR.md` 에 근거와 함께 기록한다.

### 2.1 상태관리별 배치 가이드

| 라이브러리 | 컨트롤러 위치 | DI/배선 위치 | 비고 |
| --- | --- | --- | --- |
| **Riverpod** (권장) | `01_presentation/<f>/controllers/` — `@riverpod` Notifier/AsyncNotifier + Provider | `00_config/di/` — `Provider<Interface>` | `AsyncValue` 로 로딩/에러/데이터 3상태 표현. 코드젠(`@riverpod`) 방식 권장 |
| **GetX** | `01_presentation/<f>/controllers/` — `GetxController` | `00_config/di/` — `Bindings` (`Get.lazyPut`) | `Rx` 반응형 상태. 라우팅도 GetX 로 통일 가능 |
| **BLoC** | `01_presentation/<f>/bloc/` — Bloc/Cubit + events/states | `00_config/di/` — `get_it`/`RepositoryProvider` | events/states 를 명시적 분리. 위젯은 `BlocBuilder`/`BlocListener` 로 소비 |

- 어느 쪽이든 **컨트롤러는 UseCase만 호출**한다. Repository 구현·DataSource·Dio 를 직접 참조하지 않는다.
- 위젯은 **로딩·에러·빈 상태 3종을 항상** 렌더링 분기한다.

---

## 3. 기술 스택 기본값 (권장값 — 프로젝트 합의로 조정 가능)

- Flutter stable 채널 최신. 언어: Dart (strong-mode).
- **모델링**: `freezed` + `json_serializable`. **Entity(도메인, 직렬화 없음) / DTO(인프라, `fromJson`/`toJson`) / State(프레젠테이션)** 세 모델을 구분하고, DTO↔Entity 변환은 `mappers/` 에서 담당한다. (API 스키마 변경이 도메인/UI 로 새는 것을 차단.)
- **네트워크**: `dio` 권장 (+ 선택적으로 `retrofit` 코드젠). `http`/`chopper` 등 다른 클라이언트도 팀 선택으로 허용하되, 인스턴스/인터셉터는 `00_config/network/` 에서 단일 생성·주입한다.
- **라우팅**: `go_router` (GetX 프로젝트는 GetX 라우팅 허용). 경로 상수는 `00_config/router/` 에 집중, 문자열 하드코딩 금지.
- **에러 처리**: `fpdart` 의 `TaskEither<Failure, T>`(에러를 타입 시그니처에 드러냄) **권장**. 예외 기반이나 `Result` 타입도 팀 선택으로 허용하되, **예외는 Repository 구현 경계에서만 처리하고 raw 예외를 Presentation 으로 전파하지 않는다**는 원칙은 공통이다.
- **저장소**: `shared_preferences` / `flutter_secure_storage` (비밀값은 secure).
- **테스트**: `flutter_test` + `mocktail` + `integration_test`.

---

## 4. 필수 스크립트

`Makefile` 또는 `melos.yaml` 에 아래 타겟을 포함합니다.

```
analyze:   flutter analyze
format:    dart format --set-exit-if-changed .
test:      flutter test --coverage
build-ios: flutter build ios --release
build-aab: flutter build appbundle --release
```

- 코드젠(Freezed/json/retrofit/riverpod 등)을 쓰는 경우, 변경 후 `dart run build_runner build --delete-conflicting-outputs` 로 생성 파일을 갱신하고 **생성 파일(`*.g.dart`, `*.freezed.dart`)은 커밋에 포함**한다(CI 안정성).
- 커밋 전: `dart format`, `flutter analyze`(경고 0), `flutter test` 모두 통과해야 한다.

---

## 5. 환경변수·플레이버 규칙

- dev / staging / prod 플레이버 분리.
- API 키 등 비밀값은 `--dart-define` + secure storage 조합. 리포지토리에 커밋 금지. base URL·토큰은 `00_config/env/` 에서 로딩(하드코딩 금지).
- `.env.example` 에 필요한 `--dart-define` 키 목록을 문서화.

---

## 6. UI·상태 규칙

- 위젯은 가능한 한 `StatelessWidget`(+ 선택한 상태관리의 소비 위젯). 상태는 컨트롤러로 위임한다.
- 화면당 한 개의 페이지 위젯 + 순수 프레젠테이션 위젯 조합. `build()` 가 50줄을 넘으면 하위 위젯으로 추출.
- 에러/로딩/빈 상태 3종을 **항상** 설계. `__docs/UI_GUIDE.md` 에 명시.
- 색상·타이포그래피는 `Theme` 에서 읽고 하드코딩 금지. 사용자 문구는 상수/i18n/에러 매핑으로 분리.
- 금지 총정리: `print()`(→ `debugPrint`/logger), `dynamic`(→ 구체 타입 명시. 불가피하면 `Object?` + 명시적 캐스팅), 하드코딩 문자열·색상·URL·라우트, God widget, 위젯 내 비즈니스 로직·API·DB 접근, 레이어 역방향 import.

---

## 7. 테스트 정책 (TDD)

- **실패 테스트 → 구현 → 통과** 순. 테스트 없이 구현 커밋 금지. `test/` 는 `lib/` 의 번호형 레이어 구조를 **미러링**한다.
- 레이어별 전략: `03_domain` 단위(순수, 모킹 없음) · `02_application` 단위(UseCase 로직, Repository 인터페이스 mocktail) · `04_infra` 단위(매퍼·예외 변환, Dio/API mocktail) · `01_presentation` 단위·위젯(컨트롤러 상태 전이·렌더링).
- 외부 통신은 **항상 mocktail 로 격리**(실제 네트워크/DB 호출 금지).

---

## 8. 플랫폼 고려사항

- iOS: `Info.plist` 권한 문자열 한국어 필수. 추가 시 PR 에 명시.
- Android: 최소 SDK 합의값 고정. 변경 시 `__docs/ADR.md` 기록.
- 딥링크/유니버설 링크 추가 시 플랫폼별 설정 모두 반영했는지 확인.

---

## 9. 참고 — 완전히 고정된 Riverpod 스택을 원한다면

상태관리를 **Riverpod 로 확정**하고, fpdart(`TaskEither`) · Dio+Retrofit · Freezed 3.x · analyzer 9 정합까지 **하나로 고정된 opinionated 스택**을 원하는 프로젝트는, 별도의 `flutter-clean-arch-riverpod` 스타터 템플릿(컨벤션 문서 10종 + 코드 생성 스킬 2종 + `bootstrap.sh`)을 도입할 수 있다. 본 가이드의 번호형 레이어·의존 규칙과 동일한 뼈대 위에서 기술 선택만 고정한 형태다. 그 경우 상태관리/에러/네트워크 선택지는 해당 템플릿의 고정값을 따른다.
