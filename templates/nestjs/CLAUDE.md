# NestJS 백엔드 프로젝트 가이드

팀 공통 규격(`agent-cairn/CLAUDE.md`) 을 기준으로, 본 문서는 NestJS 기반 백엔드 프로젝트에 특화된 규약을 정의합니다.

## 1. 아키텍처

NestJS 의 모듈·DI 시스템을 활용하되, **도메인/서비스/인프라** 계층 경계를 명확히 분리합니다.

```
src/
├── main.ts                  # 부트스트랩 (ValidationPipe, Helmet, CORS 등)
├── app.module.ts            # 루트 모듈
├── modules/                 # 기능 단위 모듈 (수직 분할)
│   └── <feature>/
│       ├── <feature>.module.ts
│       ├── <feature>.controller.ts   # HTTP 어댑터
│       ├── <feature>.service.ts      # 유스케이스
│       ├── dto/                       # 입력/출력 DTO + class-validator
│       ├── entities/                  # ORM 엔티티 (또는 domain 으로 분리)
│       └── repositories/              # 인터페이스 + 구현
├── domain/                  # 순수 도메인 (엔티티, 값 객체, 도메인 오류)
├── infrastructure/          # DB 클라이언트, 큐, 외부 SDK 어댑터
├── common/                  # 가드, 인터셉터, 파이프, 필터, 데코레이터
└── config/                  # 환경변수 로딩/검증
```

- `service` 는 `controller` 와 `repository` 의 연결고리. 순수 비즈니스 로직은 `domain/` 유스케이스로 분리해도 좋다.
- `repository` 는 **인터페이스 토큰** 을 먼저 정의하고 구현체를 DI 프로바이더로 주입.
- `dto` 는 `class-validator` + `class-transformer` 로 HTTP 엣지에서 검증. 서비스 내부 타입과 분리.

### 올바른 모양 (예시)

```ts
// modules/users/dto/register-user.dto.ts
export class RegisterUserDto {
  @IsEmail() email!: string;
  @IsString() @Length(2, 50) name!: string;
}

// domain/users/errors.ts
export class EmailAlreadyExistsError extends Error {
  readonly code = 'EMAIL_ALREADY_EXISTS';
}

// modules/users/users.service.ts
@Injectable()
export class UsersService {
  constructor(
    @Inject(USER_REPOSITORY) private readonly users: UserRepository,
  ) {}

  async register(input: RegisterUserDto): Promise<User> {
    if (await this.users.findByEmail(input.email)) {
      throw new EmailAlreadyExistsError();
    }
    const user: User = { id: randomUUID(), ...input };
    await this.users.save(user);
    return user;
  }
}

// modules/users/users.controller.ts
@Controller('users')
export class UsersController {
  constructor(private readonly service: UsersService) {}

  @Post()
  async register(@Body() dto: RegisterUserDto) {
    const user = await this.service.register(dto);
    return { data: user };
  }
}

// common/filters/domain-error.filter.ts — 도메인 오류 → HTTP 매핑 중앙화
@Catch(EmailAlreadyExistsError)
export class EmailConflictFilter implements ExceptionFilter {
  catch(err: EmailAlreadyExistsError, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse();
    res.status(409).json({ error: { code: err.code, message: '이미 가입된 이메일입니다.' } });
  }
}
```

**금지 패턴**

```ts
// 금지: 컨트롤러에서 DB 직접 접근
@Controller('users')
export class UsersController {
  constructor(private readonly db: DataSource) {} // NO
  @Get() list() { return this.db.query('SELECT * FROM users'); } // NO
}

// 금지: DTO 없이 req.body 직접 사용
@Post() create(@Req() req: Request) {
  const email = req.body.email; // NO: 검증 누락
}

// 금지: 도메인이 @nestjs/common 을 import
export class User { @IsEmail() email!: string; } // NO: 도메인이 프레임워크 의존
```

## 2. 기술 스택 기본값

- 언어: **TypeScript** (`strict: true`, `noUncheckedIndexedAccess: true`).
- 런타임: Node.js LTS.
- 프레임워크: `@nestjs/common`, `@nestjs/core`, `@nestjs/config`, `@nestjs/platform-express` (기본) 또는 `@nestjs/platform-fastify`.
- 검증: **class-validator** + **class-transformer** (DTO), **zod** (외부 계약·환경변수).
- 테스트: **Jest** (`@nestjs/testing` 의 `TestingModule` 활용).
- 린트: ESLint + Prettier — 본 템플릿의 `eslint.config.mjs` 사용 (공용 `templates/node/` 대신 NestJS 전용).
- ORM: TypeORM 또는 Prisma (프로젝트 선택). 마이그레이션은 도구별 공식 CLI 로만 수행.
- 로깅: `nestjs-pino` (요청 컨텍스트 자동 주입).
- 문서화: `@nestjs/swagger` (선택).

## 3. 필수 스크립트 (`package.json`)

```json
{
  "scripts": {
    "start:dev": "nest start --watch",
    "build": "nest build",
    "start": "node dist/main.js",
    "lint": "eslint . --max-warnings=0",
    "format": "prettier --write .",
    "test": "jest",
    "test:watch": "jest --watch",
    "test:e2e": "jest --config test/jest-e2e.json"
  }
}
```

커밋 전 게이트: `npm run build && npm run lint && npm run test`.

## 4. 환경변수 규칙

- `@nestjs/config` 의 `ConfigModule` 에 **zod 기반 `validate` 함수** 를 주입해 부팅 시 검증.
- 타입 안전한 접근을 위해 `ConfigService<EnvSchema, true>` (strict 모드) 를 사용.
- 검증 실패 시 앱이 부팅되지 않아야 한다.
- 신규 환경변수 추가 시 동일 커밋에 `.env.example` 도 갱신.
- 운영 비밀값은 시크릿 매니저에서 주입. 레포에 커밋 금지.

## 5. API 응답 규칙

- 성공: `{ "data": ... }`
- 실패: `{ "error": { "code": "...", "message": "...", "details"?: ... } }`
- 전역 `ExceptionFilter` 로 도메인 오류 → HTTP 상태 코드 매핑을 중앙화한다.
- `ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true })` 를 `main.ts` 에서 글로벌 적용.
- 비즈니스 오류를 500 으로 내지 않는다 (의미 있는 4xx).

## 6. DB 스키마 변경

- **반드시 마이그레이션 도구** 사용 — TypeORM 의 `typeorm migration:generate`, Prisma 의 `prisma migrate`.
- 운영 DB 에 대한 `DROP`/`ALTER TABLE` · `typeorm schema:drop` · `prisma db push --accept-data-loss` 등 ad-hoc 실행 금지 (하네스 훅이 차단).
- 마이그레이션 PR 에는 롤백 전략을 `__docs/ADR.md` 에 기록.

## 7. 테스트 정책

- **단위 테스트**: 서비스·도메인 유스케이스. 저장소는 **인메모리 대체 구현** 또는 `jest.Mocked<T>`.
- **통합 테스트**: `Test.createTestingModule` 로 모듈을 조립해 컨트롤러·파이프·필터까지 함께 검증. supertest 로 HTTP 어설션.
- **E2E 테스트**: `test/jest-e2e.json` 에서 분리 실행. 외부 의존성은 Testcontainers 또는 Docker Compose 로 격리.
- 외부 API 는 `nock`/`msw` 로 격리. 실제 네트워크 호출 금지.
- 테스트 이름: `[대상] [조건] 일 때 [결과] 여야 한다`.
