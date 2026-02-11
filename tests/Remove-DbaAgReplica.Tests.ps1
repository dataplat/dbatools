#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAgReplica",
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

Describe $CommandName -Tag IntegrationTests -Skip:(-not $TestConfig.InstanceHadr) {
    Context "Output validation" {
        BeforeAll {
            $ConfirmPreference = "None"
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $PSDefaultParameterValues["*-Dba*:Confirm"] = $false

            # Determine if we have a second HADR-enabled instance for multi-node replica testing
            $secondHadrInstance = $null
            if ($TestConfig.InstanceMulti2) {
                try {
                    $multi2Server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
                    if ($multi2Server.IsHadrEnabled) {
                        $secondHadrInstance = $TestConfig.InstanceMulti2
                    }
                } catch {
                    # InstanceMulti2 not available for HADR
                }
            }

            $result = $null
            if ($secondHadrInstance) {
                $agName = "dbatoolsci_removerepl_$(Get-Random)"
                $splatAg = @{
                    Primary      = $TestConfig.InstanceHadr
                    Name         = $agName
                    ClusterType  = "None"
                    FailoverMode = "Manual"
                    Certificate  = "dbatoolsci_AGCert"
                    Confirm      = $false
                }
                $null = New-DbaAvailabilityGroup @splatAg

                $splatReplica = @{
                    SqlInstance = $secondHadrInstance
                    Name        = $agName
                    ClusterType = "None"
                    Certificate = "dbatoolsci_AGCert"
                    Confirm     = $false
                }
                $null = Add-DbaAgReplica @splatReplica

                $result = Remove-DbaAgReplica -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName -Replica $secondHadrInstance -Confirm:$false
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            $PSDefaultParameterValues.Remove("*-Dba*:Confirm")
        }

        AfterAll {
            if ($agName) {
                $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agName -Confirm:$false -ErrorAction SilentlyContinue
            }
            if ($secondHadrInstance) {
                $null = Get-DbaEndpoint -SqlInstance $secondHadrInstance -Type DatabaseMirroring | Remove-DbaEndpoint -Confirm:$false -ErrorAction SilentlyContinue
            }
        }

        It "Returns output of the documented type" {
            if (-not $result) { Set-ItResult -Skipped -Because "requires two HADR-enabled instances" }
            $result[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected properties" {
            if (-not $result) { Set-ItResult -Skipped -Because "requires two HADR-enabled instances" }
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "Replica", "Status")
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Returns the correct status" {
            if (-not $result) { Set-ItResult -Skipped -Because "requires two HADR-enabled instances" }
            $result[0].Status | Should -Be "Removed"
        }
    }
}
