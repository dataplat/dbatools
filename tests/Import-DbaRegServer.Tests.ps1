#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaRegServer",
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
                "Path",
                "InputObject",
                "Group",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

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

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -match dbatoolsci | Remove-DbaRegServer
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup
    }

    AfterEach {
        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -match dbatoolsci | Remove-DbaRegServer
        Get-DbaRegServerGroup -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup
        $results, $results2, $results3 | Remove-Item -ErrorAction SilentlyContinue
    }

    Context "When importing registered servers" {
        It "imports group objects" {
            $results = $newServer.Parent | Import-DbaRegServer -SqlInstance $TestConfig.InstanceSingle
            $results.Description | Should -Be $regSrvDesc
            $results.ServerName | Should -Be $srvName
            $results.Parent.Name | Should -Be $group
        }

        It "imports registered server objects" {
            $results2 = $newServer2 | Import-DbaRegServer -SqlInstance $TestConfig.InstanceSingle
            $results2.ServerName | Should -Be $newServer2.ServerName
            $results2.Parent.Name | Should -Be $newServer2.Parent.Name
        }

        It "imports a file from Export-DbaRegServer" {
            $results3 = $newServer3 | Export-DbaRegServer -Path $TestConfig.Temp
            $results4 = Import-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Path $results3
            Remove-Item -Path $results3.FullName
            $results4.ServerName | Should -Be @("dbatoolsci-server3")
            $results4.Description | Should -Be @("dbatoolsci-server3desc")
        }

        It "imports from a random object so long as it has ServerName" {
            $object = [PSCustomObject]@{
                ServerName = "dbatoolsci-randobject"
            }
            $results = $object | Import-DbaRegServer -SqlInstance $TestConfig.InstanceSingle
            $results.ServerName | Should -Be "dbatoolsci-randobject"
            $results.Name | Should -Be "dbatoolsci-randobject"
        }

        It "does not import object if ServerName does not exist" {
            $object = [PSCustomObject]@{
                Name = "dbatoolsci-randobject"
            }
            $results = $object | Import-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -WarningAction SilentlyContinue -WarningVariable warn
            $results | Should -Be $null
            $warn | Should -Match "No servers added"
        }
    }
}