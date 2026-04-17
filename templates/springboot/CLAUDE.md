# SpringBoot (Java) 백엔드 프로젝트 가이드

팀 공통 규격(`agent-cairn/CLAUDE.md`) 을 기준으로, 본 문서는 Spring Boot + **Java** 기반 백엔드 프로젝트에 특화된 규약을 정의합니다.
Kotlin 프로젝트는 `templates/springboot-kotlin/` 를 사용합니다.

## 1. 아키텍처

Spring 의 DI 컨테이너를 활용하되, **헥사고날/클린** 스타일로 도메인·애플리케이션·인프라를 분리합니다.

```
src/main/java/com/example/app/
├── AppApplication.java               # @SpringBootApplication 부트스트랩
├── config/                            # @Configuration (Security, Web, OpenAPI 등)
├── common/                            # 예외 핸들러, 공용 DTO, 어노테이션
├── modules/                           # 기능 단위 모듈 (수직 분할)
│   └── user/
│       ├── api/                       # @RestController (HTTP 엣지)
│       │   ├── UserController.java
│       │   └── dto/                   # 요청/응답 DTO + jakarta.validation
│       ├── application/               # 유스케이스 (서비스)
│       │   └── RegisterUserService.java
│       ├── domain/                    # 엔티티, 값 객체, 도메인 오류, 리포지토리 인터페이스
│       │   ├── User.java
│       │   ├── EmailAlreadyExistsException.java
│       │   └── UserRepository.java
│       └── infrastructure/            # 리포지토리 구현 (JPA), 외부 API 클라이언트
│           └── JpaUserRepository.java
└── resources/
    ├── application.yml
    ├── application-dev.yml
    ├── application-prod.yml
    └── db/migration/                  # Flyway 마이그레이션 (V1__init.sql ...)
```

- `domain/` 은 Spring·JPA 어노테이션을 직접 import 하지 않는다. JPA 엔티티가 필요하면 `infrastructure/` 에 별도 `UserJpaEntity` 를 두고 매핑.
- `application/` 은 `domain/` 인터페이스에만 의존. 구현체는 `infrastructure/` 에서 Bean 주입.
- 순환 의존을 막기 위해 패키지 간 import 방향을 ArchUnit 테스트로 강제하는 것을 권장.

### 올바른 모양 (예시)

```java
// domain/User.java — 순수 도메인
public record User(UUID id, String email, String name) {
  public static User create(String email, String name) {
    return new User(UUID.randomUUID(), email, name);
  }
}

// domain/UserRepository.java — 인터페이스
public interface UserRepository {
  Optional<User> findByEmail(String email);
  void save(User user);
}

// domain/EmailAlreadyExistsException.java — 도메인 오류
public class EmailAlreadyExistsException extends RuntimeException {
  public EmailAlreadyExistsException(String email) {
    super("이미 가입된 이메일: " + email);
  }
}

// application/RegisterUserService.java — 유스케이스
@Service
public class RegisterUserService {
  private final UserRepository users;

  public RegisterUserService(UserRepository users) {
    this.users = users;
  }

  @Transactional
  public User register(String email, String name) {
    users.findByEmail(email).ifPresent(u -> {
      throw new EmailAlreadyExistsException(email);
    });
    var user = User.create(email, name);
    users.save(user);
    return user;
  }
}

// api/UserController.java — HTTP 어댑터
@RestController
@RequestMapping("/users")
public class UserController {
  private final RegisterUserService service;

  public UserController(RegisterUserService service) {
    this.service = service;
  }

  @PostMapping
  public ResponseEntity<ApiResponse<UserView>> register(@Valid @RequestBody RegisterUserRequest req) {
    var user = service.register(req.email(), req.name());
    return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.ok(UserView.from(user)));
  }
}

// api/dto/RegisterUserRequest.java
public record RegisterUserRequest(
    @Email @NotBlank String email,
    @NotBlank @Size(min = 2, max = 50) String name
) {}

// common/GlobalExceptionHandler.java — 도메인 오류 → HTTP 매핑 중앙화
@RestControllerAdvice
public class GlobalExceptionHandler {
  @ExceptionHandler(EmailAlreadyExistsException.class)
  public ResponseEntity<ApiResponse<Void>> onEmailConflict(EmailAlreadyExistsException ex) {
    return ResponseEntity.status(HttpStatus.CONFLICT)
        .body(ApiResponse.error("EMAIL_ALREADY_EXISTS", ex.getMessage()));
  }
}
```

**금지 패턴**

```java
// 금지: 컨트롤러가 JPA 리포지토리를 직접 주입
@RestController
public class UserController {
  private final JpaUserRepository repo; // NO: 인프라 레이어 누수
  @GetMapping("/users") List<User> list() { return repo.findAll(); }
}

// 금지: 도메인이 jakarta.persistence 를 import
@Entity  // NO: 도메인이 JPA 에 물림
public class User { @Id UUID id; }

// 금지: 예외를 삼키고 500 에러로 변환
try { ... } catch (Exception e) { throw new RuntimeException(e); } // NO
```

## 2. 기술 스택 기본값

- 언어: **Java 21** (LTS).
- 빌드: **Gradle Kotlin DSL** (`build.gradle.kts`, `settings.gradle.kts`). Maven 사용 팀은 본 문서의 Gradle 태스크를 Maven goal 로 번역해 사용.
- 프레임워크: Spring Boot 3.x, Spring Web, Spring Data JPA (또는 Spring JDBC/MyBatis), Spring Validation, Spring Security(필요 시).
- 검증: **jakarta.validation** (Hibernate Validator 구현).
- 테스트: **JUnit 5** + **Mockito** + **AssertJ**. 통합 테스트에 **Testcontainers**.
- 마이그레이션: **Flyway** (`spring-boot-starter-flyway` + `resources/db/migration/V*.sql`).
- 로깅: Logback (Spring Boot 기본) + `logstash-logback-encoder` (JSON 구조 로그, 선택).
- 문서화: `springdoc-openapi-starter-webmvc-ui` (선택).
- 포매터: **기본 off**. 팀이 도입하려면 하네스 설치 시 `--with-spotless` 플래그를 사용한다 (google-java-format 기반 `spotless.gradle.kts` 가 배포됨).

## 3. 필수 스크립트

Gradle 기준.

```
./gradlew build              # 컴파일 + 유닛 테스트 + JAR 패키징
./gradlew test               # 테스트만
./gradlew integrationTest    # 통합 테스트 (Testcontainers 포함, 소스셋 분리 권장)
./gradlew bootRun            # 로컬 실행
./gradlew flywayMigrate      # 마이그레이션 적용 (dev/staging)
```

### 커밋 전 게이트

- **기본** (포매터 미도입):
  ```
  ./gradlew build test
  ```
- **`--with-spotless` 옵트인** (포매터 도입):
  ```
  ./gradlew build test spotlessCheck
  ```
  `spotlessApply` 로 자동 포매팅 후 재실행하는 흐름을 권장.

### Maven 사용 팀 참고

`pom.xml` 기반이라면 위 Gradle 태스크를 다음 goal 로 대체한다.

```
mvn verify                   # build + test (기본 게이트)
mvn spring-boot:run          # 로컬 실행
mvn flyway:migrate           # 마이그레이션
# Spotless Maven: mvn spotless:check / spotless:apply
```

## 4. 환경변수 · 프로파일 규칙

- 환경 분리는 **Spring Profile** 로 수행: `application-dev.yml`, `application-staging.yml`, `application-prod.yml`.
- 민감 값은 `application-*.yml` 에 **직접 기록 금지**. `${DB_PASSWORD}` 형태로 환경변수 치환.
- 부팅 시 `@ConfigurationProperties` + `@Validated` 로 필수값 검증. 누락 시 ApplicationContext 초기화 실패.
- 운영 프로파일은 시크릿 매니저(AWS Secrets Manager, Vault 등) 에서 주입. `application-prod.yml` 에 실값 커밋 금지.
- 새 환경변수 추가 시 동일 커밋에 `.env.example` (또는 `application-*.yml.example`) 을 갱신.

## 5. API 응답 규칙

- 성공: `{ "data": ... }`
- 실패: `{ "error": { "code": "...", "message": "...", "details"?: ... } }`
- 공통 래퍼 `ApiResponse<T>` 레코드를 정의하고 모든 컨트롤러가 이 타입으로 응답.
- `@RestControllerAdvice` 로 전역 예외 핸들러 구성, 도메인 오류 → HTTP 상태 코드 매핑을 중앙화.
- 검증 실패(`MethodArgumentNotValidException`) 는 400, 도메인 충돌은 409, 권한은 401/403. 500 은 "내가 예측하지 못한 오류" 에만.

## 6. DB 스키마 변경

- **반드시 Flyway 마이그레이션** (`resources/db/migration/V<seq>__<name>.sql`) 으로 수행.
- `spring.jpa.hibernate.ddl-auto` 는 `validate` (운영), `none` 또는 `validate` (스테이징). `update`·`create`·`create-drop` 은 로컬 전용.
- 운영 DB 에 대한 `DROP`/`ALTER TABLE` · `flyway clean` · `liquibase drop-all` 등 ad-hoc 파괴 명령은 하네스 훅이 물리적으로 차단.
- 파괴적 마이그레이션(컬럼 삭제·타입 축소) 은 **단계적 배포**: (1) 코드 전개 → (2) 데이터 백필 → (3) 별도 릴리스에서 스키마 제거.
- 마이그레이션 PR 에는 롤백 전략을 `__docs/ADR.md` 에 기록.

## 7. 테스트 정책

- **단위 테스트**: 도메인·애플리케이션 서비스. `@SpringBootTest` 없이 순수 JUnit5 + Mockito.
- **슬라이스 테스트**: `@WebMvcTest`, `@DataJpaTest` 로 레이어 좁게 로드. 불필요한 `@SpringBootTest` 남용 금지.
- **통합 테스트**: Testcontainers (Postgres/Redis/Kafka) 로 실제 DB/브로커 상대. `@Testcontainers` + `@Container`.
- **계약 테스트**: 외부 API 가 있다면 WireMock 또는 Spring Cloud Contract.
- 테스트 이름: `[대상]_[조건]_[결과]` 또는 BDD 스타일. 한글 네이밍 허용 (팀 선호에 따라).
- 커버리지 목표는 ADR 에 기록하고 강제하려면 `jacocoTestCoverageVerification` Gradle 태스크로 게이트.
