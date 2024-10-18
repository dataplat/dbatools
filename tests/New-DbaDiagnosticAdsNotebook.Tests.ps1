param($ModuleName = 'dbatools')

Describe "New-DbaDiagnosticAdsNotebook" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDiagnosticAdsNotebook
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have TargetVersion as a parameter" {
            $CommandUnderTest | Should -HaveParameter TargetVersion -Type System.String
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String
        }
        It "Should have IncludeDatabaseSpecific as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeDatabaseSpecific -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
