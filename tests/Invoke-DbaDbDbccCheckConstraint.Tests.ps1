$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Object', 'AllConstraints', 'AllErrorMessages', 'NoInformationalMessages', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$commandname Integration Test" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $random = Get-Random
        $tableName = "dbatools_CheckConstraintTbl1"
        $check1 = "chkTab1"
        $dbname = "dbatoolsci_dbccCheckConstraint$random"

        $null = $server.Query("CREATE DATABASE $dbname")
        $null = $server.Query("CREATE TABLE $tableName (Col1 int, Col2 char (30))", $dbname)
        $null = $server.Query("INSERT $tableName(Col1, Col2) VALUES (100, 'Hello')", $dbname)
        $null = $server.Query("ALTER TABLE $tableName WITH NOCHECK ADD CONSTRAINT $check1 CHECK (Col1 > 100); ", $dbname)
    }
    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Validate standard output" {
        $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Database', 'Cmd', 'Output', 'Table', 'Constraint', 'Where'
        $result = Invoke-DbaDbDbccCheckConstraint -SqlInstance $script:instance2 -Database $dbname -Object $tableName -Confirm:$false

        foreach ($prop in $props) {
            $p = $result[0].PSObject.Properties[$prop]
            It "Should return property: $prop" {
                $p.Name | Should Be $prop
            }
        }

        It "returns correct results" {
            $result.Database -match $dbname | Should Be $true
            $result.Table -match $tableName | Should Be $true
            $result.Constraint -match $check1 | Should Be $true
            $result.Output.Substring(0, 25) -eq 'DBCC execution completed.' | Should Be $true
        }
    }
}