#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Move-DbaRegServerGroup",
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
                "Group",
                "NewGroup",
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

        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

        $group2 = "dbatoolsci-group1a"
        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group2

        $group3 = "dbatoolsci-group1b"
        $newGroup3 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group3

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Name $regSrvName | Remove-DbaRegServer -ErrorAction SilentlyContinue
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $group, $group2, $group3 | Remove-DbaRegServerGroup -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When moving registered server groups" {
        It "moves a piped group" {
            $results = $newGroup2, $newGroup3 | Move-DbaRegServerGroup -NewGroup $newGroup.Name
            $results.Parent.Name | Should -Be $newGroup.Name, $newGroup.Name
        }

        It "moves a manually specified group" {
            $results = Move-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group "$group\$group3" -NewGroup Default
            $results.Parent.Name | Should -Be "DatabaseEngineServerGroup"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $testGroup = "dbatoolsci-output-test"
            $testGroup2 = "dbatoolsci-output-dest"
            $outputTestGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $testGroup
            $outputDestGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $testGroup2

            $result = Move-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $testGroup -NewGroup $testGroup2

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group "$testGroup2\$testGroup", $testGroup2 | Remove-DbaRegServerGroup -ErrorAction SilentlyContinue

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
    }
}