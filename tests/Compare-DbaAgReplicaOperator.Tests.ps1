#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Compare-DbaAgReplicaOperator",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Output validation" -Skip:(-not $TestConfig.InstanceHadr) {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Get AG replicas to create an operator on only the primary
            $ag = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -SqlCredential $TestConfig.SqlCred
            $primaryReplica = $ag.PrimaryReplicaServerName
            $operatorName = "dbatoolsci_outputtest_$(Get-Random)"

            # Create operator on primary only so comparison finds a difference
            $splatOperator = @{
                SqlInstance   = $primaryReplica
                SqlCredential = $TestConfig.SqlCred
                Operator      = $operatorName
                EmailAddress  = "dbatoolsci@dbatools.io"
            }
            $null = New-DbaAgentOperator @splatOperator

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $result = Compare-DbaAgReplicaOperator -SqlInstance $TestConfig.InstanceHadr -SqlCredential $TestConfig.SqlCred
        }

        AfterAll {
            $ag = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -SqlCredential $TestConfig.SqlCred
            $primaryReplica = $ag.PrimaryReplicaServerName
            Remove-DbaAgentOperator -SqlInstance $primaryReplica -SqlCredential $TestConfig.SqlCred -Operator $operatorName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the expected type" {
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $result | Should -Not -BeNullOrEmpty
            $expectedProps = @("AvailabilityGroup", "Replica", "OperatorName", "Status", "EmailAddress")
            foreach ($prop in $expectedProps) {
                $result[0].psobject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}
