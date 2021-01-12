$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Name', 'Simple', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    It "successfully connects and parses link and title" {
        $results = Get-DbaKbUpdate -Name KB4057119
        $results.Link -match 'download.windowsupdate.com'
        $results.Title -match 'Cumulative Update'
        $results.KBLevel | Should -Be 4057119
    }

    It "test with the -Simple param" {
        $results = Get-DbaKbUpdate -Name KB4577194 -Simple
        $results.Link -match 'download.windowsupdate.com'
        $results.Title -match 'Cumulative Update'
        $results.KBLevel | Should -Be 4577194
    }

    # see https://github.com/sqlcollaborative/dbatools/issues/6745
    It "Calling script uses a variable named filter" {
        $filter = "SQLServer*-KB-*x64*.exe"

        $results = Get-DbaKbUpdate -Name KB4564903
        $results.KBLevel | Should -Be 4564903
        $results.Link -match 'download.windowsupdate.com'
        $results.Title -match 'Cumulative Update'
    }

    It "Call with multiple KBs" {
        $results = Get-DbaKbUpdate -Name KB4057119, KB4577194, KB4564903
        $results.KBLevel | Should -Contain 4057119
        $results.KBLevel | Should -Contain 4577194
        $results.KBLevel | Should -Contain 4564903
    }
}