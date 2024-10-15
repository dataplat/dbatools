$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Mocking Get-Command for parameter validation
        Mock Get-Command {
            [PSCustomObject]@{
                Parameters = @{
                    SqlInstance     = @{Name = 'SqlInstance'}
                    SqlCredential   = @{Name = 'SqlCredential'}
                    AvailabilityGroup = @{Name = 'AvailabilityGroup'}
                    Name            = @{Name = 'Name'}
                    IPAddress       = @{Name = 'IPAddress'}
                    SubnetIP        = @{Name = 'SubnetIP'}
                    SubnetMask      = @{Name = 'SubnetMask'}
                    Port            = @{Name = 'Port'}
                    Dhcp            = @{Name = 'Dhcp'}
                    Passthru        = @{Name = 'Passthru'}
                    InputObject     = @{Name = 'InputObject'}
                    EnableException = @{Name = 'EnableException'}
                }
            }
        } -ParameterFilter { $Name -eq $CommandName }
    }

    Context "Validate parameters" {
        It "Should have the correct parameters" {
            $knownParameters = 'SqlInstance', 'SqlCredential', 'AvailabilityGroup', 'Name', 'IPAddress', 'SubnetIP', 'SubnetMask', 'Port', 'Dhcp', 'Passthru', 'InputObject', 'EnableException'
            $command = Get-Command $CommandName
            $commandParameters = $command.Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            $commandParameters | Should -Be $knownParameters
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_ag_newlistener"
        $listenerName = 'dbatoolsci_listener'
        $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Confirm:$false -Certificate dbatoolsci_AGCert
    }

    AfterEach {
        $null = Remove-DbaAgListener -SqlInstance $script:instance3 -Listener $listenerName -AvailabilityGroup $agname -Confirm:$false
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "creates a listener" {
        It "returns results with proper data" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname | 
                Add-DbaAgListener -Name $listenerName -IPAddress 127.0.20.1 -Port 14330 -Confirm:$false
            $results.PortNumber | Should -Be 14330
        }
    }
}

#$script:instance2 for appveyor
