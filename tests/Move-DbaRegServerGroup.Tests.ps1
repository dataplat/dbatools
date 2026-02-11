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

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputGroup = "dbatoolsci-outputgroup-$(Get-Random)"
            $outputGroupDest = "dbatoolsci-outputdest-$(Get-Random)"
            # Clean up in case they exist from a previous run
            Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $outputGroupDest, $outputGroup -ErrorAction SilentlyContinue | Remove-DbaRegServerGroup -Confirm:$false -ErrorAction SilentlyContinue
            $null = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $outputGroup
            $null = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $outputGroupDest
            $outputResult = Move-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $outputGroup -NewGroup $outputGroupDest

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $outputGroupDest, $outputGroup -ErrorAction SilentlyContinue | Remove-DbaRegServerGroup -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.RegisteredServers.ServerGroup"
        }

        It "Has the expected default display properties" {
            if (-not $outputResult) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Name", "DisplayName", "Description", "ServerGroups", "RegisteredServers")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}