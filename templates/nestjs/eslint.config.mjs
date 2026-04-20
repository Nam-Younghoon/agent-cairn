// NestJS 전용 ESLint flat config
// 공용 templates/node/eslint.config.mjs 와 별도 유지.
// NestJS 의 데코레이터·DI·모듈 패턴에 맞춘 규칙 오버라이드를 포함한다.

import tseslint from 'typescript-eslint';
import eslint from '@eslint/js';
import prettier from 'eslint-config-prettier';

export default tseslint.config(
  {
    ignores: ['dist', 'build', 'coverage', 'node_modules', 'test/**/*.js'],
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

      // 네이밍 — NestJS 데코레이터 메타데이터는 PascalCase 허용
      '@typescript-eslint/naming-convention': [
        'warn',
        { selector: 'default', format: ['camelCase'] },
        { selector: 'variable', format: ['camelCase', 'UPPER_CASE', 'PascalCase'] },
        { selector: 'typeLike', format: ['PascalCase'] },
        { selector: 'import', format: ['camelCase', 'PascalCase'] },
        {
          selector: 'property',
          modifiers: ['readonly'],
          format: ['camelCase', 'UPPER_CASE'],
        },
      ],

      // NestJS 데코레이터 사용 시 parameterProperties (컨트롤러/서비스 DI) 허용
      '@typescript-eslint/parameter-properties': 'off',

      // @nestjs/common 의 Logger/ConfigService 외 console 금지
      'no-console': ['warn', { allow: ['warn', 'error'] }],

      // 사용하지 않는 변수는 _접두사만 허용
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],

      // 깊은 동치 비교
      eqeqeq: ['error', 'always'],

      // NestJS 는 default export 대신 named export 를 권장 (모듈 트리 가독성)
      'import/no-default-export': 'off', // eslint-plugin-import 미도입 프로젝트 기본은 off. 도입 시 'error' 로 격상 권장.

      // 빈 생성자(데코레이터만 있는 DI 포인트) 허용
      '@typescript-eslint/no-useless-constructor': 'off',

      // 비동기 핸들러 컨벤션
      '@typescript-eslint/no-floating-promises': 'error',
      '@typescript-eslint/no-misused-promises': 'error',
    },
  },
  // 테스트 파일에서만 완화
  {
    files: ['**/*.spec.ts', '**/*.test.ts', 'test/**/*.ts'],
    rules: {
      '@typescript-eslint/no-unsafe-assignment': 'off',
      '@typescript-eslint/no-unsafe-call': 'off',
      '@typescript-eslint/no-unsafe-member-access': 'off',
    },
  },
  // Prettier 와 충돌하는 스타일 규칙은 끈다
  prettier,
);
