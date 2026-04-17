// 팀 공통 ESLint flat config (Node / TypeScript)
// 적용 방법: 프로젝트 루트에 eslint.config.mjs 로 복사하거나
//          "import base from 'sw2-eslint-config'" 형태로 확장 사용.
//
// Next.js 프로젝트에서는 기본 next lint 실행 후 본 config 를 추가로 적용한다.

import tseslint from 'typescript-eslint';
import eslint from '@eslint/js';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  {
    ignores: ['dist', 'build', '.next', 'coverage', 'node_modules'],
  },
  eslint.configs.recommended,
  ...tseslint.configs.recommendedTypeChecked,
  {
    languageOptions: {
      parserOptions: {
        projectService: true,
      },
    },
    rules: {
      // any 타입 금지 — 팀 규약
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unsafe-assignment': 'error',
      '@typescript-eslint/no-unsafe-call': 'error',
      '@typescript-eslint/no-unsafe-return': 'error',
      '@typescript-eslint/no-unsafe-member-access': 'error',

      // 줄임말 변수명 억제를 돕는 규칙
      '@typescript-eslint/naming-convention': [
        'warn',
        { selector: 'default', format: ['camelCase'] },
        { selector: 'variable', format: ['camelCase', 'UPPER_CASE', 'PascalCase'] },
        { selector: 'typeLike', format: ['PascalCase'] },
        { selector: 'import', format: ['camelCase', 'PascalCase'] },
      ],

      // 콘솔 제한 (warn/error 만 허용)
      'no-console': ['warn', { allow: ['warn', 'error'] }],

      // 사용하지 않는 변수는 _접두사만 허용
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],

      // 깊은 동치 비교
      eqeqeq: ['error', 'always'],
    },
  },
  // Prettier와 충돌하는 스타일 규칙은 끈다
  prettier,
);
