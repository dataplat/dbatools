#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaAvailabilityGroup",
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
                "AllAvailabilityGroups",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests -Skip:$env:appveyor {
    # Skip IntegrationTests on AppVeyor because every call to Remove-DbaAvailabilityGroup failes on appveyor with: Failed to delete SQL Server instance name to Windows Server Failover Clustering node name map entry for the local availability replica of availability group '...'.  The operation encountered SQL Server error 35222 and has been terminated.

    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $agname = "dbatoolsci_removewholegroup"
        $null = New-DbaAvailabilityGroup -Primary $TestConfig.InstanceHadr -Name $agname -ClusterType None -FailoverMode Manual -Certificate dbatoolsci_AGCert

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Get-DbaEndpoint -SqlInstance $TestConfig.InstanceHadr -Type DatabaseMirroring | Remove-DbaEndpoint

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "removes the newly created ag" {
        It "removes the ag" {
            $results = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname
            $WarnVar | Should -BeNullorEmpty
            $results.Status | Should -Be 'Removed'
            $results.AvailabilityGroup | Should -Be $agname
        }

        It "really removed the ag" {
            $results = Get-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $agname
            $results | Should -BeNullorEmpty
        }
    }

}

Describe "$CommandName Output" -Tag IntegrationTests -Skip:(-not $TestConfig.InstanceHadr) {
    Context "Output validation" {
        BeforeAll {
            $ConfirmPreference = "None"
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $PSDefaultParameterValues["*-Dba*:Confirm"] = $false

            $outputAgName = "dbatoolsci_removeag_output_$(Get-Random)"
            $splatOutputAg = @{
                Primary      = $TestConfig.InstanceHadr
                Name         = $outputAgName
                ClusterType  = "None"
                FailoverMode = "Manual"
                Certificate  = "dbatoolsci_AGCert"
                Confirm      = $false
            }
            $null = New-DbaAvailabilityGroup @splatOutputAg
            $outputResult = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $outputAgName -Confirm:$false

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
            $PSDefaultParameterValues.Remove("*-Dba*:Confirm")
        }

        AfterAll {
            $null = Remove-DbaAvailabilityGroup -SqlInstance $TestConfig.InstanceHadr -AvailabilityGroup $outputAgName -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0] | Should -BeOfType [PSCustomObject]
        }

        It "Has the expected properties" {
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "AvailabilityGroup", "Status")
            foreach ($prop in $expectedProperties) {
                $outputResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should be present"
            }
        }

        It "Returns the correct values" {
            $outputResult[0].Status | Should -Be "Removed"
            $outputResult[0].AvailabilityGroup | Should -Be $outputAgName
        }
    }
}