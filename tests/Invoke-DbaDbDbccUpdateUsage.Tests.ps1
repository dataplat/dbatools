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
        $server = Connect-SqlInstance -SqlInstance $script:instance1
        $random = Get-Random
        $tableName = "dbatools_getdbtbl1"

        $dbname = "dbatoolsci_getdbUsage$random"
        $null = $server.Query("CREATE DATABASE $dbname")
        $null = $server.Query("CREATE TABLE $tableName (id int)", $dbname)
        $null = $server.Query("CREATE CLUSTERED INDEX [PK_Id] ON $tableName ([id] ASC)", $dbname)
        $null = $server.Query("INSERT $tableName(id) SELECT object_id FROM sys.objects", $dbname)
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname | Remove-DbaDatabase -Confirm:$false
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
        $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $script:instance1 -Database $dbname -Table $tableName -Confirm:$false

        It "returns results for table" {
            $result.Output -match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.' | Should Be $true
        }

        $result = Invoke-DbaDbDbccUpdateUsage -SqlInstance $script:instance1 -Database $dbname -Table $tableName -Index 1 -Confirm:$false

        It "returns results for index by id" {
            $result.Output -match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.' | Should Be $true
        }
    }

}


