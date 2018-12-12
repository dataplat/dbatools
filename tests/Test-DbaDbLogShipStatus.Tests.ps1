$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'Simple', 'Primary', 'Secondary', 'EnableException'
        $SupportShouldProcess = $false
        $paramCount = $knownParameters.Count
        if ($SupportShouldProcess) {
            $defaultParamCount = 13
        } else {
            $defaultParamCount = 11
        }
        $command = Get-Command -Name $CommandName
        [object[]]$params = $command.Parameters.Keys

        It "Should contain our specific parameters" {
            ((Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count) | Should Be $paramCount
        }

        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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