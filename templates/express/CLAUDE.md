# Express 백엔드 프로젝트 가이드

팀 공통 규격(`agent-cairn/CLAUDE.md`)을 기준으로, 본 문서는 Express 기반 백엔드 프로젝트에 특화된 규약을 정의합니다.

## 1. 아키텍처

계층 구분을 명확히 분리합니다.

```
src/
├── routes/          # Express 라우터 (HTTP 엣지)
├── controllers/     # 요청 검증 + 유스케이스 호출
├── services/        # 비즈니스 로직 (프레임워크 비의존)
├── domain/          # 엔티티, 값 객체, 도메인 오류
├── repositories/    # DB/외부 API 접근 인터페이스와 구현
├── infrastructure/  # DB 클라이언트, 큐, 로거 등 구현체
├── middlewares/     # 인증, 에러 핸들링, 로깅 미들웨어
├── config/          # 환경변수 로딩/검증
└── app.ts           # Express 앱 조립 (DI 지점)
```

- `services/`와 `domain/`은 Express·DB 클라이언트를 직접 참조하지 않는다. 테스트 가능성을 우선.
- `repositories/`는 **인터페이스**를 먼저 정의하고, 구현체는 `infrastructure/`에서 주입.

### 올바른 모양 (예시)

```ts
// domain/user.ts — 순수 도메인, 외부 의존 없음
export type User = { id: string; email: string; name: string };
export class EmailAlreadyExistsError extends Error {}

// domain/repositories/user-repository.ts — 인터페이스만 정의
export interface UserRepository {
  findByEmail(email: string): Promise<User | null>;
  save(user: User): Promise<void>;
}

// services/register-user.ts — 유스케이스. 프레임워크 비의존.
export class RegisterUser {
  constructor(private readonly users: UserRepository) {}
  async run(input: { email: string; name: string }): Promise<User> {
    if (await this.users.findByEmail(input.email)) {
      throw new EmailAlreadyExistsError();
    }
    const user: User = { id: crypto.randomUUID(), ...input };
    await this.users.save(user);
    return user;
  }
}

// controllers/register-user-controller.ts — HTTP 어댑터
export const registerUserController = (usecase: RegisterUser) =>
  async (req: Request, res: Response) => {
    const body = registerUserSchema.parse(req.body); // zod
    const user = await usecase.run(body);
    res.status(201).json({ data: user });
  };

// infrastructure/user-repository-postgres.ts — 구현체
export class PostgresUserRepository implements UserRepository {
  constructor(private readonly db: Pool) {}
  async findByEmail(email: string) { /* ... */ }
  async save(user: User) { /* ... */ }
}
```

**금지 패턴**

```ts
// 금지: 도메인이 Express 를 import
import { Request } from 'express';
export class User { serialize(req: Request) { /* ... */ } } // NO
```

## 2. 기술 스택 기본값

- 언어: **TypeScript** (`strict: true`, `noUncheckedIndexedAccess: true`)
- 런타임: Node.js LTS
- 테스트: **Vitest**
- 린트: ESLint + Prettier (`@typescript-eslint/no-explicit-any: error`)
- 검증: **zod** (입력 스키마 + 환경변수 검증)
- 로깅: **pino**
- DB 클라이언트: Prisma 또는 Drizzle (프로젝트 선택)

## 3. 필수 스크립트 (`package.json`)

```json
{
  "scripts": {
    "dev": "tsx watch src/app.ts",
    "build": "tsc -p tsconfig.json",
    "start": "node dist/app.js",
    "lint": "eslint . --max-warnings=0",
    "test": "vitest run",
    "test:watch": "vitest"
  }
}
```

## 4. 환경변수 규칙

- `src/config/env.ts`에서 zod로 모든 환경변수를 검증하고 타입드 객체를 export.
- 검증 실패 시 앱이 부팅되지 않아야 한다.
- 추가 시 **반드시** `.env.example`도 같은 커밋에 포함.
- 운영 비밀값은 시크릿 매니저에서 주입. 레포에 절대 커밋 금지.

## 5. API 응답 규칙

- 성공: `{ "data": ... }`
- 실패: `{ "error": { "code": "...", "message": "...", "details"?: ... } }`
- 상태 코드: 2xx/4xx/5xx 의미를 혼용하지 않는다. 비즈니스 오류도 의미에 맞는 4xx로.
- 전역 에러 핸들러 미들웨어에서 도메인 오류 → HTTP 매핑을 중앙화.

## 6. DB 스키마 변경

- **반드시 마이그레이션 도구**로 수행 (Prisma `prisma migrate`, Drizzle `drizzle-kit generate`).
- 운영 DB에 대한 `DROP`/`ALTER TABLE`의 ad-hoc 실행은 하네스 훅에 의해 차단됨.
- 마이그레이션 PR에는 롤백 전략을 `__docs/ADR.md`에 기록.

## 7. 테스트 정책

- 유스케이스/도메인: **단위 테스트**, 저장소는 인메모리 대체 구현 사용.
- 라우터/미들웨어: **통합 테스트**, supertest 기반.
- 외부 API는 nock/msw로 격리. 실제 네트워크 호출 금지.
- 테스트 이름: `[대상] [조건]일 때 [결과]여야 한다`.
