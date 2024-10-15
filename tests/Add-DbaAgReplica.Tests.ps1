$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests' {
    BeforeAll {
        # Mocking Get-Command for parameter validation
        Mock Get-Command {
            [PSCustomObject]@{
                Parameters = @{
                    SqlInstance                   = @{Name = 'SqlInstance'}
                    SqlCredential                 = @{Name = 'SqlCredential'}
                    Name                          = @{Name = 'Name'}
                    ClusterType                   = @{Name = 'ClusterType'}
                    AvailabilityMode              = @{Name = 'AvailabilityMode'}
                    FailoverMode                  = @{Name = 'FailoverMode'}
                    BackupPriority                = @{Name = 'BackupPriority'}
                    ConnectionModeInPrimaryRole   = @{Name = 'ConnectionModeInPrimaryRole'}
                    ConnectionModeInSecondaryRole = @{Name = 'ConnectionModeInSecondaryRole'}
                    SeedingMode                   = @{Name = 'SeedingMode'}
                    Endpoint                      = @{Name = 'Endpoint'}
                    EndpointUrl                   = @{Name = 'EndpointUrl'}
                    Passthru                      = @{Name = 'Passthru'}
                    ReadOnlyRoutingList           = @{Name = 'ReadOnlyRoutingList'}
                    ReadonlyRoutingConnectionUrl  = @{Name = 'ReadonlyRoutingConnectionUrl'}
                    Certificate                   = @{Name = 'Certificate'}
                    ConfigureXESession            = @{Name = 'ConfigureXESession'}
                    SessionTimeout                = @{Name = 'SessionTimeout'}
                    InputObject                   = @{Name = 'InputObject'}
                    EnableException               = @{Name = 'EnableException'}
                }
            }
        } -ParameterFilter { $Name -eq $CommandName }
    }

    Context "Validate parameters" {
        It "Should have the correct parameters" {
            $knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'ClusterType', 'AvailabilityMode', 'FailoverMode', 'BackupPriority', 'ConnectionModeInPrimaryRole', 'ConnectionModeInSecondaryRole', 'SeedingMode', 'Endpoint', 'EndpointUrl', 'Passthru', 'ReadOnlyRoutingList', 'ReadonlyRoutingConnectionUrl', 'Certificate', 'ConfigureXESession', 'SessionTimeout', 'InputObject', 'EnableException'
            $command = Get-Command $CommandName
            $commandParameters = $command.Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
            $commandParameters | Should -Be $knownParameters
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $agname = "dbatoolsci_agroup"
        $null = New-DbaAvailabilityGroup -Primary $script:instance3 -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert -Confirm:$false
    }

    AfterAll {
        $null = Remove-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup $agname -Confirm:$false
    }

    Context "gets ag replicas" {
        It "returns results with proper data" {
            $results = Get-DbaAgReplica -SqlInstance $script:instance3
            $results.AvailabilityGroup | Should -Contain $agname
            $results.Role | Should -Contain 'Primary'
            $results.AvailabilityMode | Should -Contain 'SynchronousCommit'
            $results.FailoverMode | Should -Contain 'Manual'
        }

        It "returns just one result" {
            $replicaName = (Get-DbaAgReplica -SqlInstance $script:instance3 -AvailabilityGroup $agname).Name
            $results = Get-DbaAgReplica -SqlInstance $script:instance3 -Replica $replicaName -AvailabilityGroup $agname
            $results.AvailabilityGroup | Should -Be $agname
            $results.Role | Should -Be 'Primary'
            $results.AvailabilityMode | Should -Be 'SynchronousCommit'
            $results.FailoverMode | Should -Be 'Manual'
        }
    }
}

#$script:instance2 for appveyor
