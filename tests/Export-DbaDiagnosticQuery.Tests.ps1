param($ModuleName = 'dbatools')

Describe "Export-DbaDiagnosticQuery" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaDiagnosticQuery
        }
        It "has all the required parameters" {
            $params = @(
                "InputObject",
                "ConvertTo",
                "Path",
                "Suffix",
                "NoPlanExport",
                "NoQueryExport",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Verifying output" -Tag "IntegrationTests" {
        BeforeAll {
            $testPath = "C:\temp\dbatoolsci"
        }
        AfterAll {
            Get-ChildItem $testPath -Recurse | Remove-Item -ErrorAction Ignore
            Get-Item $testPath | Remove-Item -ErrorAction Ignore
        }
        It "exports results to one file and creates directory if required" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $global:instance2 -QueryName 'Memory Clerk Usage' | Export-DbaDiagnosticQuery -Path $testPath
            (Get-ChildItem $testPath).Count | Should -Be 1
        }
    }
}
