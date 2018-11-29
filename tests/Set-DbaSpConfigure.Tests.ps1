$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Set-DbaSpConfigure).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Value', 'Name', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Set configuration" {
        BeforeAll {
            $remotequerytimeout = (Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $newtimeout = $remotequerytimeout + 1
        }

        # Sanity check
        if ($null -eq $remotequerytimeout) {
            return
        }

        It "changes the remote query timeout from $remotequerytimeout to $newtimeout" {
            $results = Set-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout -Value $newtimeout
            $results.PreviousValue | Should Be $remotequerytimeout
            $results.NewValue | Should Be $newtimeout
        }

        It "changes the remote query timeout from $newtimeout to $remotequerytimeout" {
            $results = Set-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout -Value $remotequerytimeout
            $results.PreviousValue | Should Be $newtimeout
            $results.NewValue | Should Be $remotequerytimeout
        }

        $results = Set-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout -Value $remotequerytimeout -WarningVariable warning -WarningAction SilentlyContinue
        It "returns a warning when if the new value is the same as the old" {
            $warning -match "existing" | Should be $true
        }
    }
}