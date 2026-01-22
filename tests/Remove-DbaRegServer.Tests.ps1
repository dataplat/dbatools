#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaRegServer",
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
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $srvName = "dbatoolsci-server1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"
        $srvName2 = "dbatoolsci-server2"
        $regSrvName2 = "dbatoolsci-server21"
        $regSrvDesc2 = "dbatoolsci-server321"

        # Create the registered servers.
        $splatServer1 = @{
            SqlInstance = $TestConfig.InstanceSingle
            ServerName  = $srvName
            Name        = $regSrvName
            Description = $regSrvDesc
        }
        $newServer = Add-DbaRegServer @splatServer1

        $splatServer2 = @{
            SqlInstance = $TestConfig.InstanceSingle
            ServerName  = $srvName2
            Name        = $regSrvName2
            Description = $regSrvDesc2
        }
        $newServer2 = Add-DbaRegServer @splatServer2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created registered servers.
        Get-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Name $regSrvName, $regSrvName2 | Remove-DbaRegServer -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing registered servers" {
        It "supports dropping via the pipeline" {
            $results = $newServer | Remove-DbaRegServer
            $results.Name | Should -Be $regSrvName
            $results.Status | Should -Be "Dropped"
        }

        It "supports dropping manually" {
            $results = Remove-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Name $regSrvName2
            $results.Name | Should -Be $regSrvName2
            $results.Status | Should -Be "Dropped"
        }
    }

    Context "Output Validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # Create a test server to remove
            $testSrvName = "dbatoolsci-outputtest"
            $testRegName = "dbatoolsci-outputtest1"
            $splatTestServer = @{
                SqlInstance = $TestConfig.InstanceSingle
                ServerName  = $testSrvName
                Name        = $testRegName
            }
            $null = Add-DbaRegServer @splatTestServer

            # Remove it and capture output
            $result = Remove-DbaRegServer -SqlInstance $TestConfig.InstanceSingle -Name $testRegName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties for CMS registered servers" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Name",
                "ServerName",
                "Status"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }

        It "Sets Status property to 'Dropped'" {
            $result.Status | Should -Be "Dropped"
        }
    }
}