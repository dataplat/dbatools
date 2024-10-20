param($ModuleName = 'dbatools')

Describe "Get-DbaDbIdentity" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database tempdb
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

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbIdentity
        }
        It "has the required parameter: <_>" -ForEach @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Table",
            "EnableException"
        ) {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Validate standard output" {
        BeforeAll {
            $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Table', 'Cmd', 'IdentityValue', 'ColumnValue', 'Output'
            $result = Get-DbaDbIdentity -SqlInstance $global:instance1 -Database tempdb -Table 'dbo.dbatoolsci_example', 'dbo.dbatoolsci_example2'
        }

        It "Should return property: <_>" -ForEach $props {
            $result[0].PSObject.Properties[$_] | Should -Not -BeNullOrEmpty
        }

        It "Should return results for each table" {
            $result.Count | Should -Be 2
        }

        It "Should return correct results" {
            $result[0].IdentityValue | Should -Be 125
        }
    }
}
