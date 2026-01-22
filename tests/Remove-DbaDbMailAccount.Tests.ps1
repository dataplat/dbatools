#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMailAccount",
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
                "Account",
                "ExcludeAccount",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $accountname1 = "dbatoolsci_test_$(Get-Random)"
        $accountname2 = "dbatoolsci_test_$(Get-Random)"

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
    }

    Context "When working with database mail accounts" {
        BeforeEach {
            # We want to run all commands in the BeforeEach block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatAccount1 = @{
                SqlInstance  = $server
                Name         = $accountname1
                EmailAddress = "admin@ad.local"
            }
            $null = New-DbaDbMailAccount @splatAccount1

            $splatAccount2 = @{
                SqlInstance  = $server
                Name         = $accountname2
                EmailAddress = "admin@ad.local"
            }
            $null = New-DbaDbMailAccount @splatAccount2

            # We want to run all commands outside of the BeforeEach block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterEach {
            # We want to run all commands in the AfterEach block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Cleanup all created accounts
            $null = Remove-DbaDbMailAccount -SqlInstance $server -Account $accountname1, $accountname2

            # We want to run all commands outside of the AfterEach block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "removes a database mail account" {
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -Account $accountname
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname) | Should -BeNullOrEmpty
        }

        It "supports piping database mail account" {
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname) | Should -Not -BeNullOrEmpty
            Get-DbaDbMailAccount -SqlInstance $server -Account $accountname | Remove-DbaDbMailAccount
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname) | Should -BeNullOrEmpty
        }

        It "removes all database mail accounts but excluded" {
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname2) | Should -Not -BeNullOrEmpty
            (Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2
            (Get-DbaDbMailAccount -SqlInstance $server -ExcludeAccount $accountname2) | Should -BeNullOrEmpty
            (Get-DbaDbMailAccount -SqlInstance $server -Account $accountname2) | Should -Not -BeNullOrEmpty
        }

        It "removes all database mail accounts" {
            (Get-DbaDbMailAccount -SqlInstance $server) | Should -Not -BeNullOrEmpty
            Remove-DbaDbMailAccount -SqlInstance $server
            (Get-DbaDbMailAccount -SqlInstance $server) | Should -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $accountname = "dbatoolsci_test_$(Get-Random)"
            $splatAccount = @{
                SqlInstance  = $server
                Name         = $accountname
                EmailAddress = "admin@ad.local"
            }
            $null = New-DbaDbMailAccount @splatAccount

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $null = Remove-DbaDbMailAccount -SqlInstance $server -Account $accountname
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result = Remove-DbaDbMailAccount -SqlInstance $server -Account $accountname -EnableException
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected properties" {
            $result = Remove-DbaDbMailAccount -SqlInstance $server -Account $accountname -EnableException
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "Status",
                "IsRemoved"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
            }
        }
    }
}