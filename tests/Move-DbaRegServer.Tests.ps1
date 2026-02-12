#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Move-DbaRegServer",
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
                "ServerName",
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
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

        $srvName2 = "dbatoolsci-server2"
        $group2 = "dbatoolsci-group1a"
        $regSrvName2 = "dbatoolsci-server21"
        $regSrvDesc2 = "dbatoolsci-server321"

        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $group2
        $newServer2 = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName2 -Name $regSrvName2 -Description $regSrvDesc2

        $regSrvName3 = "dbatoolsci-server3"
        $srvName3 = "dbatoolsci-server3"
        $regSrvDesc3 = "dbatoolsci-server3desc"

        $newServer3 = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName3 -Name $regSrvName3 -Description $regSrvDesc3

        $testGroupHR = "dbatoolsci-HR-$random"
        $testGroupFinance = "dbatoolsci-Finance-$random"
        $regSrvNameHR = "dbatoolsci-HR-$random"
        $regSrvNameFinance = "dbatoolsci-Finance-$random"

        $newTestGroupHR = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $testGroupHR
        $newTestGroup5 = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $testGroupFinance
        $newServerHR = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName -Name $regSrvNameHR -Group $testGroupHR
        $newServerFinance = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName -Name $regSrvNameFinance -Group $testGroupHR

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Name $regSrvName, $regSrvName2, $regSrvName3, $regSrvNameHR, $regSrvNameFinance | Remove-DbaRegServer
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $group, $group2, $testGroupHR, $testGroupFinance | Remove-DbaRegServerGroup

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    It "moves a piped server" {
        $results = $newServer2 | Move-DbaRegServer -NewGroup $newGroup.Name
        $results.Parent.Name | Should -Be $newGroup.Name
        $results.Name | Should -Be $regSrvName2
    }

    It "moves a manually specified server" {
        $results = Move-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $srvName3 -NewGroup $newGroup2.Name
        $results.Parent.Name | Should -Be $newGroup2.Name
        $results.Description | Should -Be $regSrvDesc3
    }

    # see https://github.com/dataplat/dbatools/issues/7112
    It "moves a piped server to a target group" {
        $results = Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Group $testGroupHR | Move-DbaRegServer -Group $testGroupFinance
        $results.Count | Should -Be 2
    }
}

Describe "$CommandName Output" -Tag IntegrationTests {
    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputRandom = Get-Random
            $outputGroup = "dbatoolsci-outputgrp-$outputRandom"
            $outputSrvName = "dbatoolsci-outputsrv-$outputRandom"
            $outputRegName = "dbatoolsci-outputreg-$outputRandom"

            $outputNewGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Name $outputGroup
            $outputNewServer = Add-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -ServerName $outputSrvName -Name $outputRegName

            $outputResult = $outputNewServer | Move-DbaRegServer -NewGroup $outputGroup

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Name $outputRegName | Remove-DbaRegServer -ErrorAction SilentlyContinue
            Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle -Group $outputGroup | Remove-DbaRegServerGroup -ErrorAction SilentlyContinue
        }

        It "Returns output of the expected type" {
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.RegisteredServers.RegisteredServer"
        }

        It "Has the expected default display properties" {
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("Name", "ServerName", "Group", "Description", "Source")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}