param($ModuleName = 'dbatools')

Describe "New-DbaDiagnosticAdsNotebook" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDiagnosticAdsNotebook
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "TargetVersion",
                "Path",
                "IncludeDatabaseSpecific",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
