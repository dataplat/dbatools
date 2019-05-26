$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Simple', 'Primary', 'Secondary', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    It "warns if SQL instance edition is not supported" {
        $null = Test-DbaDbLogShipStatus -SqlInstance $script:instance1 -WarningAction SilentlyContinue -WarningVariable editionwarn
        $editionwarn -match "Express" | Should Be $true
    }

    It "warns if no log shipping found" {
        $null = Test-DbaDbLogShipStatus -SqlInstance $script:instance2 -Database 'master' -WarningAction SilentlyContinue -WarningVariable doesntexist
        $doesntexist -match "No information available" | Should Be $true
    }
}