#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Add-DbaRegServerGroup",
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
                "Name",
                "Description",
                "Group",
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
        $group = "dbatoolsci-group1"
        $group2 = "dbatoolsci-group2"
        $description = "group description"
        $descriptionUpdated = "group description updated"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When adding a registered server group" {
        It "adds a registered server group" {
            $splatAddGroup = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $group
            }
            $results = Add-DbaRegServerGroup @splatAddGroup
            $results.Name | Should -Be $group
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "adds a registered server group with extended properties" {
            $splatAddGroupExtended = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $group2
                Description = $description
            }
            $results = Add-DbaRegServerGroup @splatAddGroupExtended
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $description
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $result = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name dbatoolsci-outputtest -Description "Output validation test group"
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -eq dbatoolsci-outputtest | Remove-DbaRegServerGroup
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns the documented output type" {
            $result | Should -BeOfType [Microsoft.SqlServer.Management.RegisteredServers.ServerGroup]
        }

        It "Has the expected default display properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Name',
                'DisplayName',
                'Description',
                'ServerGroups',
                'RegisteredServers'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Has the ServerGroup-specific properties" {
            $result.PSObject.Properties.Name | Should -Contain 'Id' -Because "Id is a key ServerGroup property"
            $result.PSObject.Properties.Name | Should -Contain 'Parent' -Because "Parent is a key ServerGroup property"
        }
    }

    Context "When using pipeline input" {
        It "supports pipeline input" {
            $results = Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Id 1 |
                Add-DbaRegServerGroup -Name dbatoolsci-first |
                Add-DbaRegServerGroup -Name dbatoolsci-second |
                Add-DbaRegServerGroup -Name dbatoolsci-third |
                Add-DbaRegServer -ServerName dbatoolsci-test -Description ridiculous
            $results.Group | Should -Be "dbatoolsci-first\dbatoolsci-second\dbatoolsci-third"
        }
    }

    Context "When adding nested groups" {
        It "adds a registered server group and sub-group when not exists" {
            $splatAddNested = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = "$group\$group2"
                Description = $description
            }
            $results = Add-DbaRegServerGroup @splatAddNested
            $results.Name | Should -Be $group2
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "updates description of sub-group when it already exists" {
            $splatUpdateNested = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = "$group\$group2"
                Description = $descriptionUpdated
            }
            $results = Add-DbaRegServerGroup @splatUpdateNested
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $descriptionUpdated
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}