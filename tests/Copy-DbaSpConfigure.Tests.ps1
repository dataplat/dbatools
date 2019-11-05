$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'ConfigName', 'ExcludeConfigName', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Copy config with the same properties." {
        BeforeAll {
            $sourceconfig = (Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $destconfig = (Get-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout).ConfiguredValue
            # Set it so they don't match
            if ($sourceconfig -and $destconfig) {
                $newvalue = $sourceconfig + $destconfig
                $null = Set-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout -Value $newvalue
            }
        }
        AfterAll {
            if ($destconfig -and $destconfig -ne $sourceconfig) {
                $null = Set-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout -Value $destconfig
            }
        }

        It "starts with different values" {
            $config1 = Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue -ne $config2.ConfiguredValue | Should be $true
        }

        It "copied successfully" {
            $results = Copy-DbaSpConfigure -Source $script:instance1 -Destination $script:instance2 -ConfigName RemoteQueryTimeout
            $results.Status | Should Be "Successful"
        }

        It "retains the same properties" {
            $config1 = Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout
            $config2 = Get-DbaSpConfigure -SqlInstance $script:instance2 -ConfigName RemoteQueryTimeout
            $config1.ConfiguredValue | Should be $config2.ConfiguredValue
        }

        It "didn't modify the source" {
            $newconfig = (Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout).ConfiguredValue
            $newconfig -eq $sourceconfig | Should Be $true
        }
    }
}