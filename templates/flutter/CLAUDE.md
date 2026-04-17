# Flutter 모바일 가이드

팀 공통 규격(`agent-cairn/CLAUDE.md`)을 기준으로, 본 문서는 Flutter 기반 모바일 프로젝트에 특화된 규약을 정의합니다.

## 1. 아키텍처

레이어 분리 + 기능 단위(feature-first) 구성을 우선합니다.

```
lib/
├── app.dart                  # 앱 진입점, 라우터, 테마
├── core/                     # 전역 유틸, 예외, 확장, 테마
├── config/                   # 환경변수/빌드 플레이버 로딩
├── data/                     # API 클라이언트, DTO, 저장소 구현
│   ├── api/
│   ├── dto/
│   └── repositories/
├── domain/                   # 엔티티, 유스케이스, 저장소 인터페이스
│   ├── entities/
│   ├── usecases/
│   └── repositories/
└── features/                 # 기능 단위 화면 + 상태
    └── <feature>/
        ├── presentation/
        │   ├── pages/
        │   └── widgets/
        └── application/      # 상태 관리(notifier/controller)
```

- **상태 관리**: 프로젝트 합의에 따라 Riverpod 또는 GetX 중 하나를 선택하고 **일관되게** 사용.
- `domain/`은 Flutter/패키지 비의존 순수 Dart.
- `data/` 구현은 `domain/`의 인터페이스를 구현하도록 DI.

### 올바른 모양 (예시, Riverpod 기준)

```dart
// domain/entities/user.dart — 순수 엔티티
@freezed
class User with _$User {
  const factory User({required String id, required String email}) = _User;
}

// domain/repositories/user_repository.dart — 인터페이스
abstract class UserRepository {
  Future<User?> findByEmail(String email);
  Future<void> save(User user);
}

// domain/usecases/register_user.dart — 유스케이스
class RegisterUser {
  RegisterUser(this._repo);
  final UserRepository _repo;
  Future<User> call({required String email}) async {
    if (await _repo.findByEmail(email) != null) {
      throw const EmailAlreadyExistsException();
    }
    final user = User(id: const Uuid().v4(), email: email);
    await _repo.save(user);
    return user;
  }
}

// data/repositories/user_repository_impl.dart — 구현
class UserRepositoryImpl implements UserRepository {
  UserRepositoryImpl(this._api);
  final UserApi _api;
  @override Future<User?> findByEmail(String email) async { /* ... */ }
  @override Future<void> save(User user) async { /* ... */ }
}

// features/register/application/register_controller.dart — 상태
class RegisterController extends StateNotifier<AsyncValue<User?>> {
  RegisterController(this._usecase) : super(const AsyncValue.data(null));
  final RegisterUser _usecase;
  Future<void> submit(String email) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _usecase(email: email));
  }
}

// features/register/presentation/pages/register_page.dart — 프레젠테이션
class RegisterPage extends ConsumerWidget {
  const RegisterPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(registerControllerProvider);
    return Scaffold(body: state.when(
      data: (user) => user == null ? const RegisterForm() : const SuccessView(),
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(message: '$e'),
    ));
  }
}
```

**금지 패턴**

```dart
// 금지: 위젯 안에서 직접 API 호출
class _MyPageState extends State<MyPage> {
  @override
  void initState() {
    super.initState();
    http.get(Uri.parse('https://api...')); // NO: 유스케이스 경유 필요
  }
}

// 금지: 하드코딩된 색상/문구
Text('로그인', style: TextStyle(color: Color(0xFF123456))); // NO
// → Text(AppStrings.login, style: Theme.of(context).textTheme.titleMedium);
```

## 2. 기술 스택 기본값

- Flutter stable 채널 최신.
- 언어: Dart (strong-mode, `analysis_options.yaml`에 `avoid_dynamic_calls`, `prefer_const_constructors` 등 포함).
- 네트워킹: `dio` 또는 `http` + retry/interceptor.
- 직렬화: `freezed` + `json_serializable`.
- 라우팅: `go_router`.
- 저장소: `shared_preferences` / `flutter_secure_storage` (비밀값은 secure).
- 테스트: `flutter_test` + `mocktail` + `integration_test`.

## 3. 필수 스크립트

`Makefile` 또는 `melos.yaml`에 아래 타겟을 포함합니다.

```
analyze:   flutter analyze
format:    dart format --set-exit-if-changed .
test:      flutter test --coverage
build-ios: flutter build ios --release
build-aab: flutter build appbundle --release
```

커밋 전: `dart format`, `flutter analyze`, `flutter test` 모두 통과해야 함.

## 4. 환경변수·플레이버 규칙

- dev / staging / prod 플레이버 분리.
- API 키 등 비밀값은 `--dart-define` + secure storage 조합. 리포지토리에 커밋 금지.
- `.env.example`에 필요한 `--dart-define` 키 목록을 문서화.

## 5. UI·상태 규칙

- 위젯은 가능한 한 `StatelessWidget`. 상태는 notifier/controller로 위임.
- 화면당 한 개의 페이지 위젯 + 순수 프리젠테이션 위젯 조합.
- 에러/로딩/빈 상태 3종을 **항상** 설계. `__docs/UI_GUIDE.md`에 명시.
- 색상·타이포그래피는 테마에서 읽고 하드코딩 금지.

## 6. 테스트 정책

- 단위 테스트: 유스케이스·도메인 로직.
- 위젯 테스트: 주요 페이지·공용 컴포넌트.
- 통합 테스트: 인증·핵심 트랜잭션 플로우.
- 외부 통신은 mocktail로 격리.

## 7. 플랫폼 고려사항

- iOS: `Info.plist` 권한 문자열 한국어 필수. 추가 시 PR에 명시.
- Android: 최소 SDK 합의값 고정. 변경 시 `__docs/ADR.md` 기록.
- 딥링크/유니버설 링크 추가 시 플랫폼별 설정 모두 반영했는지 확인.
