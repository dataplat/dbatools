$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Gets compatibility for multiple databases" {
        $results = Get-DbaDbCompatibility -SqlInstance $script:instance1
        It "Gets results" {
            $results | Should Not Be $null
        }
        Foreach ($row in $results) {
            It "Should return Compatiblity level of Version100 for $($row.database)" {
                $row.Compatibility | Should Be "Version100"
            }
        }
    }
    Context "Gets compatibility for one database" {
        $results = Get-DbaDbCompatibility -SqlInstance $script:instance1 -database master

        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should return Compatiblity level of Version100 for $($results.database)" {
            $results.Compatibility | Should Be "Version100"
        }
    }
}