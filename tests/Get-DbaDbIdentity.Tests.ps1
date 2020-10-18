$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command -Name $CommandName).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'EnableException'

        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (Id int NOT NULL IDENTITY (125, 1), Value varchar(5));
        INSERT INTO dbo.dbatoolsci_example(Value) Select 1;
        CREATE TABLE dbo.dbatoolsci_example2 (Id int NOT NULL IDENTITY (5, 1), Value varchar(5));
        INSERT INTO dbo.dbatoolsci_example2(Value) Select 1;")
    }
    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.dbatoolsci_example;
            DROP TABLE dbo.dbatoolsci_example2")
        } catch {
            $null = 1
        }
    }

    Context "Validate standard output " {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Table', 'Cmd', 'IdentityValue', 'ColumnValue', 'Output'
        $result = Get-DbaDbIdentity -SqlInstance $script:instance1 -Database tempdb -Table 'dbo.dbatoolsci_example', 'dbo.dbatoolsci_example2'

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }

        It "returns results for each table" {
            $result.Count -eq 2 | Should Be $true
        }

        It "returns correct results" {
            $result[0].IdentityValue -eq 125 | Should Be $true
        }
    }
}