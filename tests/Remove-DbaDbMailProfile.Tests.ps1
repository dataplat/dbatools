#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMailProfile",
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
                "Profile",
                "ExcludeProfile",
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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $profileName = "dbatoolsci_test_$(Get-Random)"
        $profileName2 = "dbatoolsci_test_$(Get-Random)"

        $null = New-DbaDbMailProfile -SqlInstance $server -Name $profileName
        $null = New-DbaDbMailProfile -SqlInstance $server -Name $profileName2

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "commands work as expected" {
        It "removes a database mail profile" {
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server -Profile $profileName
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName) | Should -BeNullOrEmpty
        }

        It "supports piping database mail profile" {
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName) | Should -Not -BeNullOrEmpty
            Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName | Remove-DbaDbMailProfile
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName) | Should -BeNullOrEmpty
        }

        It "removes all database mail profiles but excluded" {
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName2) | Should -Not -BeNullOrEmpty
            (Get-DbaDbMailProfile -SqlInstance $server -ExcludeProfile $profileName2) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailProfile -SqlInstance $server -ExcludeProfile $profileName2
            (Get-DbaDbMailProfile -SqlInstance $server -ExcludeProfile $profileName2) | Should -BeNullOrEmpty
            (Get-DbaDbMailProfile -SqlInstance $server -Profile $profileName2) | Should -Not -BeNullOrEmpty
        }

        It "removes all database mail profiles" {
            (Get-DbaDbMailProfile -SqlInstance $server) | Should -Not -BeNullOrEmpty
            $script:outputResult = Remove-DbaDbMailProfile -SqlInstance $server
            (Get-DbaDbMailProfile -SqlInstance $server) | Should -BeNullOrEmpty
        }

        Context "Output validation" {
            It "Returns output of the documented type" {
                $script:outputResult | Should -Not -BeNullOrEmpty
                $script:outputResult[0] | Should -BeOfType [PSCustomObject]
            }

            It "Has the expected properties" {
                $expectedProps = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Status", "IsRemoved")
                foreach ($prop in $expectedProps) {
                    $script:outputResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
                }
            }

            It "Has correct values for a successful removal" {
                $script:outputResult[0].Name | Should -BeOfType [System.String]
                $script:outputResult[0].Status | Should -Be "Dropped"
                $script:outputResult[0].IsRemoved | Should -BeTrue
            }
        }
    }
}