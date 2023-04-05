$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ServerMajorVersion', 'WebVersionUrl', 'OfflineOnly', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {

    Context "Should fetch the version locally" {
        It "Gets latest version for all SQL versions starting from SQL 2000" {
            $results = Get-DbaLatestSQLVersion -OfflineOnly
            $results | Should -Not -Be $null
            $results.count | Should -Be 10
        }

        It "Get the latest version for SQL 2014" {
            $results = Get-DbaLatestSQLVersion -ServerMajorVersion 12 -OfflineOnly
            $results | Should -Not -Be $null
            $results.LatestSP | Should -Be "SP3"
        }
    }

    Context "Should fetch the version from online" {
        It "Failure to read online data, fall back to local" {
            $results = Get-DbaLatestSQLVersion -WebVersionUrl "https://dbatools.dummy/dummy-reference.json" -Verbose -WarningVariable warningMessage
            $results | Should -Not -Be $null
            $warningMessage | Should -BeLike "*Unable to read from online reference file*"
        }
    }

}