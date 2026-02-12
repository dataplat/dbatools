#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaAgReplica",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "AvailabilityGroup",
                "Replica",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $agName = "dbatoolsci_agroup"
        $splatNewAg = @{
            Primary      = $TestConfig.InstanceHadr
            Name         = $agName
            ClusterType  = "None"
            FailoverMode = "Manual"
            Certificate  = "dbatoolsci_AGCert"
        }
        $ag = New-DbaAvailabilityGroup @splatNewAg
        $replicaName = $ag.PrimaryReplica

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName
        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "gets ag replicas" {
        BeforeAll {
            $script:outputForValidation = Get-DbaAgReplica -SqlInstance $TestConfig.InstanceHadr
        }

        It "returns results with proper data" {
            $results = $script:outputForValidation
            $results.AvailabilityGroup | Should -Contain $agName
            $results.Role | Should -Contain "Primary"
            $results.AvailabilityMode | Should -Contain "SynchronousCommit"
        }

        It "returns just one result" {
            $splatGetReplica = @{
                SqlInstance       = $TestConfig.InstanceHadr
                Replica           = $replicaName
                AvailabilityGroup = $agName
            }
            $results = Get-DbaAgReplica @splatGetReplica
            $results.AvailabilityGroup | Should -Be $agName
            $results.Role | Should -Be "Primary"
            $results.AvailabilityMode | Should -Be "SynchronousCommit"
        }

        It "Passes EnableException to Get-DbaAvailabilityGroup" {
            $results = Get-DbaAgReplica -SqlInstance invalidSQLHostName -WarningAction SilentlyContinue
            $WarnVar | Should -Match "The network path was not found|No such host is known"
            $results | Should -BeNullOrEmpty

            { Get-DbaAgReplica -SqlInstance invalidSQLHostName -EnableException } | Should -Throw
        }

        It "Returns output of the documented type" {
            $result = $script:outputForValidation
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.AvailabilityReplica"
        }

        It "Has the expected default display properties" {
            $result = $script:outputForValidation
            if (-not $result) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "AvailabilityGroup",
                "Name",
                "Role",
                "ConnectionState",
                "RollupSynchronizationState",
                "AvailabilityMode",
                "BackupPriority",
                "EndpointUrl",
                "SessionTimeout",
                "FailoverMode",
                "ReadonlyRoutingList"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}