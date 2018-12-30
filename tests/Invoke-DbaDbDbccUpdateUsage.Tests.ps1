$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command -Name $CommandName).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'Index', 'NoInformationalMessages', 'CountRows', 'EnableException'

        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $knownParameters.Count
        }
    }
}
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database tempdb
        $null = $db.Query("CREATE TABLE dbo.dbatoolsci_example (id int);
            CREATE CLUSTERED INDEX [PK_Id] ON [dbo].[dbatoolsci_example] ([id] ASC);
            INSERT dbo.dbatoolsci_example SELECT top 100 object_id FROM sys.objects")
    }
    AfterAll {
        try {
            $null = $db.Query("DROP TABLE dbo.dbatoolsci_example")
        } catch {
            $null = 1
        }
    }

    Context "Validate standard output" {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Cmd', 'Output'
        $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $script:instance1 -Confirm:$false

        It "returns results" {
            $result.Count -gt 0 | Should Be $true
        }

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }
    }

    Context "Validate returns results " {
        $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $script:instance1 -Database 'tempdb' -Table 'dbatoolsci_example' -Confirm:$false

        It "returns results for table" {
            $result.SqlInstance -eq $script:instance1 | Should Be $true
        }

        $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $script:instance1 -Database 2 -Table 'dbo.dbatoolsci_example' -Index 1 -Confirm:$false

        It "returns results for index by id" {
            $result.SqlInstance -eq $script:instance1 | Should Be $true
        }
    }

}


