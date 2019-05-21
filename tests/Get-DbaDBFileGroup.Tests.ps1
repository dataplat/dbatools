$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'FileGroup', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/sqlcollaborative/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $multifgdb = "dbatoolsci_multifgdb$random"
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database $multifgdb

        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $server.Query("CREATE DATABASE $multifgdb; ALTER DATABASE $multifgdb ADD FILEGROUP [Test1]; ALTER DATABASE $multifgdb ADD FILEGROUP [Test2];")
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database $multifgdb
    }

    Context "Returns values for Instance" {
        $results = Get-DbaDbFileGroup -SqlInstance $script:instance1
        It "Results are not empty" {
            $results | Should Not Be $Null
        }
        It "Returns the correct object" {
            $results[0].GetType().ToString() | Should Be "Microsoft.SqlServer.Management.Smo.FileGroup"
        }
    }

    Context "Accepts database and filegroup input" {
        $results = Get-DbaDbFileGroup -SqlInstance $script:instance1 -Database $multifgdb

        It "Reports the right number of filegroups" {
            $results.Count | Should Be 3
        }

        $results = Get-DbaDbFileGroup -SqlInstance $script:instance1 -Database $multifgdb -FileGroup Test1

        It "Reports the right number of filegroups" {
            $results.Count | Should Be 1
        }
    }

    Context "Accepts piped input" {
        $systemDbs = Get-DbaDatabase -SqlInstance $script:instance1 -ExcludeUser
        $results = $systemDbs | Get-DbaDbFileGroup -SqlInstance $script:instance1 -FileGroup Primary

        It "Reports the right number of filegroups" {
            $results.Count | Should Be 4
        }
    }

}