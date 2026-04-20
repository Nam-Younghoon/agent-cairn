// Spotless 설정 (Kotlin 프로젝트)
// 적용 방법: build.gradle.kts 에서 `apply(from = "spotless.gradle.kts")` 로 로드하거나,
//           동일 블록을 루트 build.gradle.kts 에 복사해 사용한다.
// 도입 기준: agent-cairn 하네스에서 `install.sh --with-spotless` 옵트인 시 배포됨.
// 커밋 전 게이트:
//   ./gradlew build test spotlessCheck
// 자동 포매팅:
//   ./gradlew spotlessApply

plugins {
    id("com.diffplug.spotless") version "6.25.0"
}

spotless {
    kotlin {
        target("src/**/*.kt")
        targetExclude("**/build/**", "**/generated/**")

        // ktfmt — 구글 스타일, 설정 최소, 결과 일관. (ktlint 대신 채택)
        ktfmt("0.49").googleStyle()

        trimTrailingWhitespace()
        endWithNewline()

        // 라이선스 헤더를 쓰는 팀은 아래 주석 해제:
        // licenseHeaderFile(rootProject.file("config/license-header.txt"))
    }

    kotlinGradle {
        target("*.gradle.kts", "buildSrc/**/*.gradle.kts")
        ktfmt("0.49").googleStyle()
    }
}
