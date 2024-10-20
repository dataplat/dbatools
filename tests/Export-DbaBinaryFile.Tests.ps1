param($ModuleName = 'dbatools')

Describe "Export-DbaBinaryFile" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaBinaryFile
        }
        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "Schema",
                "FileNameColumn",
                "BinaryColumn",
                "Path",
                "Query",
                "FilePath",
                "InputObject",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database tempdb
            $null = $db.Query("CREATE TABLE [dbo].[BunchOFilezz]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
            $null = Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFilezz -FilePath $global:appveyorlabrepo\azure\adalsql.msi
            $null = Get-ChildItem $global:appveyorlabrepo\certificates | Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFilezz
        }

        AfterAll {
            try {
                $null = $db.Query("DROP TABLE dbo.BunchOFilezz")
                $null = Get-ChildItem -Path C:\temp\exports -File | Remove-Item -Confirm:$false -Force
            } catch {
                $null = 1
            }
        }

        It "exports the table data to file" {
            $results = Export-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Path C:\temp\exports
            $results.Name.Count | Should -Be 3
            $results.Name | Should -Be @('adalsql.msi', 'localhost.crt', 'localhost.pfx')
        }

        It "exports the table data to file using pipeline" {
            $results = Get-DbaBinaryFileTable -SqlInstance $global:instance2 -Database tempdb | Export-DbaBinaryFile -Path C:\temp\exports
            $results.Name.Count | Should -Be 3
            $results.Name | Should -Be @('adalsql.msi', 'localhost.crt', 'localhost.pfx')
        }
    }
}
