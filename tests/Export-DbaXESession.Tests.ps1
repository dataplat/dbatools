param($ModuleName = 'dbatools')

Describe "Export-DbaXESession" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $AltExportPath = "$env:USERPROFILE\Documents"
        $outputFile = "$AltExportPath\Dbatoolsci_XE_CustomFile.sql"
    }

    AfterAll {
        Get-ChildItem $outputFile -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaXESession
        }
        It "has the required parameter: SqlInstance" -ForEach @("SqlInstance", "SqlCredential", "InputObject", "Session", "Path", "FilePath", "Encoding", "Passthru", "BatchSeparator", "NoPrefix", "NoClobber", "Append", "EnableException") {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Check if output file was created" {
        BeforeAll {
            $null = Export-DbaXESession -SqlInstance $global:instance2 -FilePath $outputFile
        }
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check if session parameter is honored" {
        BeforeAll {
            $null = Export-DbaXESession -SqlInstance $global:instance2 -FilePath $outputFile -Session system_health
        }
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }

    Context "Check if supports Pipeline input" {
        BeforeAll {
            $null = Get-DbaXESession -SqlInstance $global:instance2 -Session system_health | Export-DbaXESession -FilePath $outputFile
        }
        It "Exports results to one sql file" {
            (Get-ChildItem $outputFile).Count | Should -Be 1
        }
        It "Exported file is bigger than 0" {
            (Get-ChildItem $outputFile).Length | Should -BeGreaterThan 0
        }
    }
}
