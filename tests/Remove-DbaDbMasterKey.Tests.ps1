#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbMasterKey",
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
                "Database",
                "ExcludeDatabase",
                "All",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName - Output Validation" -Tag UnitTests {
    Context "Output Validation" {
        BeforeAll {
            # Setup: Create a test database with a master key
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance1
            $dbName = "dbatoolsci_removemasterkey_$(Get-Random)"
            $null = New-DbaDatabase -SqlInstance $TestConfig.instance1 -Name $dbName -EnableException
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database $dbName -Query "CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'P@ssw0rd123'" -EnableException
            
            # Execute the command
            $result = Remove-DbaDbMasterKey -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false -EnableException
        }

        AfterAll {
            # Cleanup: Remove test database
            Remove-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbName -Confirm:$false
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'Status'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Returns Status property with expected value" {
            $result.Status | Should -Be "Master key removed"
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>