$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Schema', 'FilePath', 'EnableException', 'Statement'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $null = $db.Query("CREATE TABLE [dbo].[BunchOFiles]([FileName123] [nvarchar](50) NULL, [TheFile123] [image] NULL)")
    }
    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.BunchOFiles")
        } catch {
            $null = 1
        }
    }

    It "exports the table data" {
        $results = Import-DbaBinaryFile -SqlInstance sqlcs -Database tempdb -Table BunchOFiles -FilePath C:\github\appveyor-lab\azure\adalsql.msi
        $results.Database.Count | Should -Be 1
        $results.Database | Should -Be "tempdb"
        $results.FilePath | Should -match "adalsql.msi"
    }
}