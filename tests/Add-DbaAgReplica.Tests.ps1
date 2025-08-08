#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaAgReplica",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Name",
                "ClusterType",
                "AvailabilityMode",
                "FailoverMode",
                "BackupPriority",
                "ConnectionModeInPrimaryRole",
                "ConnectionModeInSecondaryRole",
                "SeedingMode",
                "Endpoint",
                "EndpointUrl",
                "Passthru",
                "ReadOnlyRoutingList",
                "ReadonlyRoutingConnectionUrl",
                "Certificate",
                "ConfigureXESession",
                "SessionTimeout",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $primaryAgName = "dbatoolsci_agroup"
        $splatPrimary = @{
            Primary      = $TestConfig.instance3
            Name         = $primaryAgName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
            Confirm      = $false
        }
        $primaryAg = New-DbaAvailabilityGroup @splatPrimary
        $replicaName = $primaryAg.PrimaryReplica
    }

    AfterAll {
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $primaryAgName -Confirm:$false -ErrorAction SilentlyContinue
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.instance3 -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "When adding AG replicas" {
        BeforeAll {
            $replicaAgName = "dbatoolsci_add_replicagroup"
            $splatRepAg = @{
                Primary      = $TestConfig.instance3
                Name         = $replicaAgName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Certificate  = "dbatoolsci_AGCert"
            }
            $replicaAg = New-DbaAvailabilityGroup @splatRepAg
        }

        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.instance3 -AvailabilityGroup $replicaAgName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns results with proper data" {
            $results = Get-DbaAgReplica -SqlInstance $TestConfig.instance3
            $results.AvailabilityGroup | Should -Contain $replicaAgName
            $results.Role | Should -Contain "Primary"
            $results.AvailabilityMode | Should -Contain "SynchronousCommit"
            $results.FailoverMode | Should -Contain "Manual"
        }

        It "Returns just one result for a specific replica" {
            $results = Get-DbaAgReplica -SqlInstance $TestConfig.instance3 -Replica $replicaName -AvailabilityGroup $replicaAgName
            $results.AvailabilityGroup | Should -Be $replicaAgName
            $results.Role | Should -Be "Primary"
            $results.AvailabilityMode | Should -Be "SynchronousCommit"
            $results.FailoverMode | Should -Be "Manual"
        }
    }
} #$TestConfig.instance2 for appveyor
