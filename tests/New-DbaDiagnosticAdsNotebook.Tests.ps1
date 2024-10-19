param($ModuleName = 'dbatools')

Describe "New-DbaDiagnosticAdsNotebook" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDiagnosticAdsNotebook
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have TargetVersion as a parameter" {
            $CommandUnderTest | Should -HaveParameter TargetVersion
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have IncludeDatabaseSpecific as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeDatabaseSpecific
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $file = "TestDrive:\myNotebook.ipynb"
        }
        AfterAll {
            Remove-Item -Path $file -ErrorAction SilentlyContinue
        }
        It "should create a file" {
            $notebook = New-DbaDiagnosticAdsNotebook -TargetVersion 2017 -Path $file -IncludeDatabaseSpecific
            $notebook | Should -Not -BeNullOrEmpty
            $file | Should -Exist
        }

        It "returns a file that includes specific phrases" {
            $results = New-DbaDiagnosticAdsNotebook -TargetVersion 2017 -Path $file -IncludeDatabaseSpecific
            $results | Should -Not -BeNullOrEmpty
            $fileContent = Get-Content -Path $file -Raw
            $fileContent | Should -Match "information for current instance"
        }
    }
}
