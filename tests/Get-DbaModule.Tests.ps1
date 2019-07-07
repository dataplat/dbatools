$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'ModifiedSince', 'Type', 'ExcludeSystemDatabases', 'ExcludeSystemObjects', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Modules are properly retreived" {

        # SQL2008R2SP2 returns around 600 of these in freshly installed instance. 100 is a good enough number.
        It "Should have a high count" {
            $results = Get-DbaModule -SqlInstance $script:instance1 | Select-Object -First 101
            $results.Count | Should BeGreaterThan 100
        }

        # SQL2008R2SP2 will return a number of modules from the msdb database so it is a good candidate to test
        $results = Get-DbaModule -SqlInstance $script:instance1 -Type View -Database msdb
        It "Should only have one type of object" {
            ($results | Select-Object -Unique Type | Measure-Object).Count | Should Be 1
        }

        It "Should only have one database" {
            ($results | Select-Object -Unique Database | Measure-Object).Count | Should Be 1
        }
    }

    Context "Accepts Piped Input" {
        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database msdb, master
        # SQL2008R2SP2 returns around 600 of these in freshly installed instance. 100 is a good enough number.
        $results = $db | Get-DbaModule
        It "Should have a high count" {
            $results.Count | Should BeGreaterThan 100
        }
        It "Should only have two databases" {
            ($results | Select-Object -Unique Database | Measure-Object).Count | Should Be 2
        }

        $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database msdb
        $results = $db | Get-DbaModule -Type View
        It "Should only have one type of object" {
            ($results | Select-Object -Unique Type | Measure-Object).Count | Should Be 1
        }

        It "Should only have one database" {
            ($results | Select-Object -Unique Database | Measure-Object).Count | Should Be 1
        }
    }
}