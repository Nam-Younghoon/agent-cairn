# SpringBoot (Kotlin) 백엔드 프로젝트 가이드

팀 공통 규격(`agent-cairn/CLAUDE.md`) 을 기준으로, 본 문서는 Spring Boot + **Kotlin** 기반 백엔드 프로젝트에 특화된 규약을 정의합니다.
Java 프로젝트는 `templates/springboot/` 를 사용합니다.

## 1. 아키텍처

Spring 의 DI 컨테이너를 활용하되, **헥사고날/클린** 스타일로 도메인·애플리케이션·인프라를 분리합니다. Kotlin 의 `data class`, `sealed class`, 확장 함수로 도메인 표현력을 높입니다.

```
src/main/kotlin/com/example/app/
├── AppApplication.kt                 # @SpringBootApplication 부트스트랩
├── config/                            # @Configuration (Security, Web, OpenAPI 등)
├── common/                            # 예외 핸들러, 공용 DTO, 확장
├── modules/                           # 기능 단위 모듈 (수직 분할)
│   └── user/
│       ├── api/                       # @RestController (HTTP 엣지)
│       │   ├── UserController.kt
│       │   └── dto/                   # 요청/응답 DTO + jakarta.validation
│       ├── application/               # 유스케이스 (서비스)
│       │   └── RegisterUserService.kt
│       ├── domain/                    # 엔티티, 값 객체, 도메인 오류, 리포지토리 인터페이스
│       │   ├── User.kt
│       │   ├── DomainError.kt         # sealed class 로 도메인 오류 타입 계층
│       │   └── UserRepository.kt
│       └── infrastructure/            # 리포지토리 구현 (JPA/Exposed), 외부 API
│           └── JpaUserRepository.kt
└── resources/
    ├── application.yml
    ├── application-dev.yml
    ├── application-prod.yml
    └── db/migration/                  # Flyway 마이그레이션 (V1__init.sql ...)
```

- `domain/` 은 Spring·JPA 어노테이션을 직접 import 하지 않는다. JPA 엔티티가 필요하면 `infrastructure/` 에 별도 `UserJpaEntity` 를 두고 매핑.
- `application/` 은 `domain/` 인터페이스에만 의존. 구현체는 `infrastructure/` 에서 Bean 주입.
- `sealed class DomainError` 로 오류 타입 계층을 구성하면 `when` 분기에서 Kotlin 컴파일러가 망라성(exhaustiveness) 을 체크해준다.

### 올바른 모양 (예시)

```kotlin
// domain/User.kt — 순수 도메인
data class User(val id: UUID, val email: String, val name: String) {
    companion object {
        fun create(email: String, name: String): User =
            User(id = UUID.randomUUID(), email = email, name = name)
    }
}

// domain/UserRepository.kt — 인터페이스
interface UserRepository {
    fun findByEmail(email: String): User?
    fun save(user: User)
}

// domain/DomainError.kt — sealed 계층으로 망라 분기
sealed class DomainError(message: String) : RuntimeException(message) {
    class EmailAlreadyExists(email: String) : DomainError("이미 가입된 이메일: $email")
    class UserNotFound(id: UUID) : DomainError("사용자 없음: $id")
}

// application/RegisterUserService.kt — 유스케이스
@Service
class RegisterUserService(
    private val users: UserRepository,
) {
    @Transactional
    fun register(email: String, name: String): User {
        users.findByEmail(email)?.let { throw DomainError.EmailAlreadyExists(email) }
        val user = User.create(email, name)
        users.save(user)
        return user
    }
}

// api/UserController.kt — HTTP 어댑터
@RestController
@RequestMapping("/users")
class UserController(
    private val service: RegisterUserService,
) {
    @PostMapping
    fun register(@Valid @RequestBody req: RegisterUserRequest): ResponseEntity<ApiResponse<UserView>> {
        val user = service.register(req.email, req.name)
        return ResponseEntity.status(HttpStatus.CREATED).body(ApiResponse.ok(UserView.from(user)))
    }
}

// api/dto/RegisterUserRequest.kt
data class RegisterUserRequest(
    @field:Email @field:NotBlank val email: String,
    @field:NotBlank @field:Size(min = 2, max = 50) val name: String,
)

// common/GlobalExceptionHandler.kt — 도메인 오류 → HTTP 매핑 중앙화
@RestControllerAdvice
class GlobalExceptionHandler {
    @ExceptionHandler(DomainError::class)
    fun onDomainError(ex: DomainError): ResponseEntity<ApiResponse<Nothing>> = when (ex) {
        is DomainError.EmailAlreadyExists ->
            ResponseEntity.status(HttpStatus.CONFLICT)
                .body(ApiResponse.error("EMAIL_ALREADY_EXISTS", ex.message!!))
        is DomainError.UserNotFound ->
            ResponseEntity.status(HttpStatus.NOT_FOUND)
                .body(ApiResponse.error("USER_NOT_FOUND", ex.message!!))
    }
}
```

**금지 패턴**

```kotlin
// 금지: 컨트롤러가 JPA 리포지토리를 직접 주입
@RestController
class UserController(private val repo: JpaUserRepository) // NO: 인프라 누수

// 금지: 도메인이 jakarta.persistence 를 import
@Entity
data class User(@Id val id: UUID) // NO: 도메인이 JPA 에 물림

// 금지: !! 남용으로 nullable 을 강제로 벗기기
val email = req.body!!.email!! // NO

// 금지: 예외를 삼키고 500 으로 변환
runCatching { ... }.getOrElse { throw RuntimeException(it) } // NO: 도메인 오류를 의미 있는 HTTP 로
```

## 2. 기술 스택 기본값

- 언어: **Kotlin 1.9+** (JVM target 21).
- 빌드: **Gradle Kotlin DSL** (`build.gradle.kts`, `settings.gradle.kts`).
- 프레임워크: Spring Boot 3.x, Spring Web, Spring Data JPA (또는 JOOQ/Exposed), Spring Validation, Spring Security(필요 시).
  - Kotlin 플러그인: `kotlin("jvm")`, `kotlin("plugin.spring")`, `kotlin("plugin.jpa")` (JPA 사용 시, 기본 생성자 생성용).
- 검증: **jakarta.validation** (Hibernate Validator). data class 필드에는 `@field:` 타겟 사용.
- 테스트: **JUnit 5** + **MockK** + **AssertJ** / **Kotest**(선택). 통합 테스트에 **Testcontainers**.
- 마이그레이션: **Flyway** (`spring-boot-starter-flyway` + `resources/db/migration/V*.sql`).
- 로깅: Logback + `logstash-logback-encoder` (JSON 구조 로그, 선택).
- 직렬화: **jackson-module-kotlin** (Spring Boot 3.x 기본 포함).
- 포매터: **기본 off**. 팀이 도입하려면 하네스 설치 시 `--with-spotless` 플래그를 사용한다 (ktfmt 기반 `spotless.gradle.kts` 가 배포됨).

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

Kotlin + Maven 조합에서는 `kotlin-maven-plugin` + `spring-boot-maven-plugin` 을 사용한다.

```
mvn verify                   # build + test (기본 게이트)
mvn spring-boot:run          # 로컬 실행
mvn flyway:migrate           # 마이그레이션
# Spotless Maven: mvn spotless:check / spotless:apply
```

## 4. 환경변수 · 프로파일 규칙

- 환경 분리는 **Spring Profile** 로 수행: `application-dev.yml`, `application-staging.yml`, `application-prod.yml`.
- 민감 값은 `application-*.yml` 에 **직접 기록 금지**. `${DB_PASSWORD}` 형태로 환경변수 치환.
- 부팅 시 `@ConfigurationProperties` + `@Validated` 로 필수값 검증. Kotlin 의 non-nullable 필드가 자연스럽게 필수성을 강제.
- 운영 프로파일은 시크릿 매니저(AWS Secrets Manager, Vault 등) 에서 주입. `application-prod.yml` 에 실값 커밋 금지.
- 새 환경변수 추가 시 동일 커밋에 `.env.example` (또는 `application-*.yml.example`) 을 갱신.

## 5. API 응답 규칙

- 성공: `{ "data": ... }`
- 실패: `{ "error": { "code": "...", "message": "...", "details"?: ... } }`
- 공통 래퍼 `data class ApiResponse<T>` 를 정의하고 모든 컨트롤러가 이 타입으로 응답.
- `@RestControllerAdvice` 로 전역 예외 핸들러 구성, `sealed class DomainError` 를 `when` 으로 분기해 HTTP 상태 코드로 매핑.
- 검증 실패(`MethodArgumentNotValidException`) 는 400, 도메인 충돌은 409, 권한은 401/403. 500 은 "내가 예측하지 못한 오류" 에만.

## 6. DB 스키마 변경

- **반드시 Flyway 마이그레이션** (`resources/db/migration/V<seq>__<name>.sql`) 으로 수행.
- `spring.jpa.hibernate.ddl-auto` 는 `validate` (운영), `validate` 또는 `none` (스테이징). `update`·`create`·`create-drop` 은 로컬 전용.
- 운영 DB 에 대한 `DROP`/`ALTER TABLE` · `flyway clean` · `liquibase drop-all` 등 ad-hoc 파괴 명령은 하네스 훅이 물리적으로 차단.
- 파괴적 마이그레이션(컬럼 삭제·타입 축소) 은 **단계적 배포**: (1) 코드 전개 → (2) 데이터 백필 → (3) 별도 릴리스에서 스키마 제거.
- JPA 엔티티의 `@Column` 변경은 반드시 Flyway 마이그레이션과 짝을 이루어야 한다.

## 7. 테스트 정책

- **단위 테스트**: 도메인·애플리케이션 서비스. `@SpringBootTest` 없이 순수 JUnit5 + **MockK**.
  ```kotlin
  val repo = mockk<UserRepository>()
  every { repo.findByEmail(any()) } returns null
  ```
- **슬라이스 테스트**: `@WebMvcTest`, `@DataJpaTest` 로 레이어 좁게 로드. Spring-Mockk (`@MockkBean`) 조합 권장.
- **통합 테스트**: Testcontainers (Postgres/Redis/Kafka) 로 실제 DB/브로커 상대. `@Testcontainers` + `@Container` + `@DynamicPropertySource`.
- **계약 테스트**: 외부 API 가 있다면 WireMock.
- 테스트 이름: `\`사용자가 X 일 때 Y 해야 한다\`` 형태의 백틱 한글 함수명 허용.
- 커버리지 목표는 ADR 에 기록하고 `jacocoTestCoverageVerification` Gradle 태스크로 게이트.
