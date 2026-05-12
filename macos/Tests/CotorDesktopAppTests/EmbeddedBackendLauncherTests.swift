import Testing
@testable import CotorDesktopApp

struct EmbeddedBackendLauncherTests {
    @Test
    func backendHealthRequiresOwnedVersionedCotorServer() {
        let owned = #"{"ok":true,"service":"cotor-app-server","owner":"cotor-desktop","version":"1.0.6","build":"1.0.6"}"#
            .data(using: .utf8)!
        let legacy = #"{"ok":true,"service":"cotor-app-server"}"#
            .data(using: .utf8)!
        let other = #"{"ok":true,"service":"other","owner":"cotor-desktop","version":"1.0.6","build":"1.0.6"}"#
            .data(using: .utf8)!

        #expect(isOwnedEmbeddedBackendHealthData(owned))
        #expect(!isOwnedEmbeddedBackendHealthData(legacy))
        #expect(!isOwnedEmbeddedBackendHealthData(other))
    }

    @Test
    func backendLaunchEnvironmentDoesNotInheritParentSecrets() {
        let env = sanitizedEmbeddedBackendEnvironment(
            processEnvironment: [
                "PATH": "/custom/bin:/usr/bin",
                "HOME": "/Users/test",
                "USER": "test",
                "TMPDIR": "/tmp/cotor-test",
                "LANG": "C.UTF-8",
                "LC_ALL": "C.UTF-8",
                "OPENAI_API_KEY": "secret-openai",
                "GITHUB_TOKEN": "secret-github",
                "GH_TOKEN": "secret-gh",
                "LINEAR_API_TOKEN": "secret-linear",
                "CUSTOM_PASSWORD": "secret-password",
                "COTOR_PROJECT_ROOT": "/source/checkout",
                "COTOR_CODEX_OAUTH_HOME": "/Users/test/.cotor/codex-oauth",
                "JAVA_HOME": "/Library/Java/TestJDK"
            ],
            javaPath: "/Library/Java/TestJDK/bin/java",
            appHomePath: "/Users/test/Library/Application Support/CotorDesktop",
            appToken: "desktop-token"
        )

        #expect(env["OPENAI_API_KEY"] == nil)
        #expect(env["GITHUB_TOKEN"] == nil)
        #expect(env["GH_TOKEN"] == nil)
        #expect(env["LINEAR_API_TOKEN"] == nil)
        #expect(env["CUSTOM_PASSWORD"] == nil)
        #expect(env["COTOR_PROJECT_ROOT"] == nil)
        #expect(env["COTOR_CODEX_OAUTH_HOME"] == "/Users/test/.cotor/codex-oauth")
        #expect(env["COTOR_APP_HOME"] == "/Users/test/Library/Application Support/CotorDesktop")
        #expect(env["COTOR_DESKTOP_APP_HOME"] == "/Users/test/Library/Application Support/CotorDesktop")
        #expect(env["COTOR_APP_TOKEN"] == "desktop-token")
        #expect(env["JAVA_HOME"] == "/Library/Java/TestJDK")
        #expect(env["PATH"] == "/custom/bin:/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin")
    }
}
