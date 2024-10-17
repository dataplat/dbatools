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
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Mandatory:$false
        }
        It "Should have ConvertTo as a parameter" {
            $CommandUnderTest | Should -HaveParameter ConvertTo -Type String -Mandatory:$false
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.IO.FileInfo -Mandatory:$false
        }
        It "Should have Suffix as a parameter" {
            $CommandUnderTest | Should -HaveParameter Suffix -Type String -Mandatory:$false
        }
        It "Should have NoPlanExport as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoPlanExport -Type Switch -Mandatory:$false
        }
        It "Should have NoQueryExport as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoQueryExport -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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
