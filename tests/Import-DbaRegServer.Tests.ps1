#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Import-DbaRegServer",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # For all the temporary files that we want to clean up after the test, we create variables to track them.
        $global:tempFilesToRemove = @()

        # Set variables. They are available in all the It blocks.
        $global:srvName = "dbatoolsci-server1"
        $global:group = "dbatoolsci-group1"
        $global:regSrvName = "dbatoolsci-server12"
        $global:regSrvDesc = "dbatoolsci-server123"

        $global:srvName2 = "dbatoolsci-server2"
        $global:group2 = "dbatoolsci-group1a"
        $global:regSrvName2 = "dbatoolsci-server21"
        $global:regSrvDesc2 = "dbatoolsci-server321"

        $global:regSrvName3 = "dbatoolsci-server3"
        $global:srvName3 = "dbatoolsci-server3"
        $global:regSrvDesc3 = "dbatoolsci-server3desc"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Get-DbaRegServer -SqlInstance $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false -ErrorAction SilentlyContinue
        Get-DbaRegServerGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false -ErrorAction SilentlyContinue

        # Remove temporary files.
        Remove-Item -Path $global:tempFilesToRemove -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When importing registered servers" {
        BeforeEach {
            # Clean up any existing test objects before each test
            Get-DbaRegServer -SqlInstance $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServer -Confirm:$false -ErrorAction SilentlyContinue
            Get-DbaRegServerGroup -SqlInstance $TestConfig.instance2 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "imports group objects" {
            $newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance2 -Name $global:group
            $newServer = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $global:srvName -Name $global:regSrvName -Description $global:regSrvDesc -Group $newGroup.Name

            $results = $newServer.Parent | Import-DbaRegServer -SqlInstance $TestConfig.instance2
            $results.Description | Should -Be $global:regSrvDesc
            $results.ServerName | Should -Be $global:srvName
            $results.Parent.Name | Should -Be $global:group
        }

        It "imports registered server objects" {
            $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance2 -Name $global:group2
            $newServer2 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $global:srvName2 -Name $global:regSrvName2 -Description $global:regSrvDesc2

            $results2 = $newServer2 | Import-DbaRegServer -SqlInstance $TestConfig.instance2
            $results2.ServerName | Should -Be $newServer2.ServerName
            $results2.Parent.Name | Should -Be $newServer2.Parent.Name
        }

        It "imports a file from Export-DbaRegServer" {
            $newServer3 = Add-DbaRegServer -SqlInstance $TestConfig.instance2 -ServerName $global:srvName3 -Name $global:regSrvName3 -Description $global:regSrvDesc3

            $results3 = $newServer3 | Export-DbaRegServer -Path C:\temp
            $global:tempFilesToRemove += $results3.FullName
            $results4 = Import-DbaRegServer -SqlInstance $TestConfig.instance2 -Path $results3
            $results4.ServerName | Should -Be @("dbatoolsci-server3")
            $results4.Description | Should -Be @("dbatoolsci-server3desc")
        }

        It "imports from a random object so long as it has ServerName" {
            $object = [PSCustomObject]@{
                ServerName = "dbatoolsci-randobject"
            }
            $results = $object | Import-DbaRegServer -SqlInstance $TestConfig.instance2
            $results.ServerName | Should -Be "dbatoolsci-randobject"
            $results.Name | Should -Be "dbatoolsci-randobject"
        }

        It "does not import object if ServerName does not exist" {
            $object = [PSCustomObject]@{
                Name = "dbatoolsci-randobject"
            }
            $results = $object | Import-DbaRegServer -SqlInstance $TestConfig.instance2 -WarningAction SilentlyContinue -WarningVariable warn
            $results | Should -Be $null
            $warn | Should -Match "No servers added"
        }
    }
}