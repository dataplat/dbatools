#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName = "dbatools",
    $PSDefaultParameterValues = ($TestConfig = Get-TestConfig).Defaults
)

Describe "Add-DbaRegServer" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command Add-DbaRegServer
            $expected = $TestConfig.CommonParameters
            $expected += @(
                "SqlInstance",
                "SqlCredential",
                "ServerName",
                "Name",
                "Description",
                "Group",
                "ActiveDirectoryTenant",
                "ActiveDirectoryUserId",
                "ConnectionString",
                "OtherParams",
                "InputObject",
                "ServerObject",
                "EnableException",
                "Confirm",
                "WhatIf"
            )
        }

        It "Has parameter: <_>" -ForEach $expected {
            $command | Should -HaveParameter $PSItem
        }

        It "Should have exactly the number of expected parameters ($($expected.Count))" {
            $hasparms = $command.Parameters.Values.Name
            Compare-Object -ReferenceObject $expected -DifferenceObject $hasparms | Should -BeNullOrEmpty
        }
    }
}

Describe "Add-DbaRegServer" -Tag "IntegrationTests" {
    BeforeAll {
        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"
        $groupobject = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name $group
    }

    AfterAll {
        Get-DbaRegServer -SqlInstance $TestConfig.instance1, $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false
        Get-DbaRegServerGroup -SqlInstance $TestConfig.instance1, $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
    }

    Context "When adding a registered server" {
        BeforeAll {
            $results1 = Add-DbaRegServer -SqlInstance $TestConfig.instance1 -ServerName $srvName
        }

        It "Adds a registered server with correct name" {
            $results1.Name | Should -Be $srvName
        }

        It "Adds a registered server with correct server name" {
            $results1.ServerName | Should -Be $srvName
        }

        It "Adds a registered server with non-null SqlInstance" {
            $results1.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }

    Context "When adding a registered server with extended properties" {
        BeforeAll {
            $splat = @{
                SqlInstance = $TestConfig.instance1
                ServerName  = $regSrvName
                Name        = $srvName
                Group       = $groupobject
                Description = $regSrvDesc
            }

            $results2 = Add-DbaRegServer @splat
        }

        It "Adds a registered server with correct server name" {
            $results2.ServerName | Should -Be $regSrvName
        }

        It "Adds a registered server with correct description" {
            $results2.Description | Should -Be $regSrvDesc
        }

        It "Adds a registered server with correct name" {
            $results2.Name | Should -Be $srvName
        }

        It "Adds a registered server with non-null SqlInstance" {
            $results2.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
