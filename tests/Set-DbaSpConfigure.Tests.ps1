$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Value', 'Name', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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