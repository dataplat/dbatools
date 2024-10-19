param($ModuleName = 'dbatools')

Describe "Get-DbaBinaryFileTable" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database tempdb
        $null = $db.Query("CREATE TABLE [dbo].[BunchOFilez]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
        $null = Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFilez -FilePath $global:appveyorlabrepo\azure\adalsql.msi
        $null = Get-ChildItem $global:appveyorlabrepo\certificates | Import-DbaBinaryFile -SqlInstance $global:instance2 -Database tempdb -Table BunchOFilez
    }

    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.BunchOFilez")
        } catch {
            $null = 1
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaBinaryFileTable
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "Schema",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        It "returns a table" {
            $results = Get-DbaBinaryFileTable -SqlInstance $global:instance2 -Database tempdb
            $results.Name.Count | Should -BeGreaterOrEqual 1
        }

        It "supports piping" {
            $results = Get-DbaDbTable -SqlInstance $global:instance2 -Database tempdb | Get-DbaBinaryFileTable
            $results.Name.Count | Should -BeGreaterOrEqual 1
        }
    }
}
