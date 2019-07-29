<#
    The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
    Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ExcludeSystemSp', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
# Get-DbaNoun
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $random = Get-Random
        $procName = "dbatools_getdbsp"
        $dbname = "dbatoolsci_getdbsp$random"
        $server.Query("CREATE DATABASE $dbname")
        $server.Query("CREATE PROCEDURE $procName AS SELECT 1", $dbname)
    }

    AfterAll {
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    Context "Command actually works" {
        $results = Get-DbaDbStoredProcedure -SqlInstance $script:instance2 -Database $dbname -ExcludeSystemSp
        it "Should have standard properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance'.Split(',')
            ($results[0].PsObject.Properties.Name | Where-Object {$_ -in $ExpectedProps} | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }

        It "Should include test procedure: $procName" {
            ($results | Where-Object Name -eq $procName).Name | Should Be $procName
        }
        It "Should exclude system procedures" {
            ($results | Where-Object Name -eq 'sp_helpdb') | Should Be $null
        }
    }
}