$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-ChildItem function:\Get-DbaDbPageInfo).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Schema', 'Table', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}

Describe "$CommandName Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $dbname = "dbatoolsci_pageinfo_$random"
        Get-DbaProcess -SqlInstance $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $server.Query("CREATE DATABASE $dbname;")
        $server.Databases[$dbname].Query('CREATE TABLE [dbo].[TestTable](TestText VARCHAR(MAX) NOT NULL)')
        $query = "
                INSERT INTO dbo.TestTable
                (
                    TestText
                )
                VALUES
                ('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')"

        # Generate a bunch of extra inserts to create enough pages
        1..100 | ForEach-Object {
            $query += ",('AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA')"
        }
        $server.Databases[$dbname].Query($query)
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
    }
    Context "Count Pages" {
        $result = Get-DbaDbPageInfo -SqlInstance $script:instance2 -Database $dbname
        It "returns the proper results" {
            ($result).Count | Should -Be 9
            ($result | Where-Object { $_.IsAllocated -eq $false }).Count | Should -Be 5
            ($result | Where-Object { $_.IsAllocated -eq $true }).Count | Should -Be 4
        }
    }
}