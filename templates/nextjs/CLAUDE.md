# Next.js 웹 프론트엔드 가이드

팀 공통 규격(`agent-cairn/CLAUDE.md`)을 기준으로, 본 문서는 Next.js(App Router) 기반 웹 프로젝트에 특화된 규약을 정의합니다.

## 1. 아키텍처

UI / 상태 / 비즈니스 로직 분리를 우선합니다.

```
src/
├── app/                    # App Router 라우트·레이아웃·페이지
│   └── (routes)/page.tsx
├── features/               # 기능 단위 모듈 (수직 분할)
│   └── <feature>/
│       ├── components/     # 해당 기능 UI (프레젠테이션)
│       ├── hooks/          # 상태/부수효과 훅
│       ├── api/            # 서버 액션/페치 래퍼
│       ├── schemas.ts      # zod 스키마
│       └── types.ts
├── components/             # 전역 재사용 UI (디자인 시스템)
├── lib/                    # 순수 유틸, 외부 SDK 래퍼
├── styles/
└── config/                 # 환경변수 로딩/검증
```

- 페이지(`app/`)는 조립만 한다. 로직은 `features/`에.
- 데이터 페치: 서버 컴포넌트 우선, 상호작용이 필요한 곳에만 클라이언트 컴포넌트.
- 전역 클라이언트 상태는 꼭 필요한 경우에만 (Zustand 권장). context 남용 금지.

### 올바른 모양 (예시)

```tsx
// features/login/api/login.ts — 서버 액션
'use server';
import { loginSchema } from '../schemas';

export async function login(formData: FormData) {
  const parsed = loginSchema.parse(Object.fromEntries(formData));
  // 비즈니스 로직은 별도 함수로 분리
  return await performLogin(parsed);
}

// features/login/hooks/use-login-form.ts — 상태·부수효과 캡슐화
'use client';
export function useLoginForm() {
  const form = useForm<LoginInput>({ resolver: zodResolver(loginSchema) });
  const [pending, startTransition] = useTransition();
  const onSubmit = form.handleSubmit((data) => {
    startTransition(async () => { await login(data); });
  });
  return { form, pending, onSubmit };
}

// features/login/components/login-form.tsx — 순수 프레젠테이션
'use client';
export function LoginForm({ form, pending, onSubmit }: LoginFormProps) {
  return <form onSubmit={onSubmit}>{/* ... */}</form>;
}

// app/(auth)/login/page.tsx — 조립
export default function LoginPage() {
  return <LoginFormContainer />;
}
```

**금지 패턴**

```tsx
// 금지: 페이지에 비즈니스 로직 직접 작성
export default async function Page() {
  const db = new PrismaClient();                // NO: DB 접근 누수
  const users = await db.user.findMany();       // NO
  if (users.length > 100) { /* 비즈니스 규칙 */ } // NO
  return <div>{/* ... */}</div>;
}

// 금지: 비밀값을 NEXT_PUBLIC_ 으로 노출
// process.env.NEXT_PUBLIC_JWT_SECRET  → 클라이언트 번들에 그대로 박힘
```

## 2. 기술 스택 기본값

- 언어: **TypeScript** (`strict: true`)
- 런타임: Node.js LTS / React Server Components
- 스타일: Tailwind CSS (프로젝트 합의 시 CSS Modules 허용)
- 테스트: **Vitest** + **React Testing Library** + **Playwright**(E2E)
- 린트: ESLint(Next 플러그인 포함) + Prettier
- 검증: zod (폼/서버 액션 입력)
- 폼: react-hook-form

## 3. 필수 스크립트 (`package.json`)

```json
{
  "scripts": {
    "dev": "next dev",
    "build": "next build",
    "start": "next start",
    "lint": "next lint --max-warnings=0 && eslint . --max-warnings=0",
    "test": "vitest run",
    "test:e2e": "playwright test"
  }
}
```

## 4. 환경변수 규칙

- `NEXT_PUBLIC_` 접두사 없는 값은 **클라이언트 번들에 포함되지 않음**. 혼동 주의.
- `src/config/env.ts`에서 zod로 분리 검증:
  - `serverEnv`: 서버 전용
  - `publicEnv`: 클라이언트 노출
- 비밀값을 `NEXT_PUBLIC_*`에 넣지 않는다 (하드코딩과 동일 취급).

## 5. 컴포넌트 규칙

- **프레젠테이션**과 **컨테이너**를 분리. 훅으로 상태를 감싸 UI는 순수하게.
- 접근성: 의미론적 태그, alt, role, aria-* 속성 필수.
- 국제화/문구는 상수/i18n 모듈로 분리. 컴포넌트 안에 한국어 문자열 직접 박지 않는다 (i18n 미도입 프로젝트는 예외).

## 6. 테스트 정책

- 단위: 훅·유틸 순수 함수, `@testing-library/react` 기반 컴포넌트 렌더링 테스트.
- E2E: 주요 플로우는 Playwright로 커버. CI에서 headless 실행.
- MSW로 네트워크 모킹. 실제 API 호출 금지.

## 7. UI 변경 프로세스

- UI 변경이 있는 작업은 `__docs/UI_GUIDE.md` 필수.
- 구현 완료 보고 시, 주요 화면 스크린샷(또는 Playwright 트레이스) 첨부 권장.
