#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Rename-DbaLogin",
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
                "Login",
                "NewLogin",
                "EnableException",
                "Force"
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
        $loginName = "dbatoolsci_renamelogin"
        $renamedLogin = "dbatoolsci_renamelogin2"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

        # Create the test login
        $splatNewLogin = @{
            SqlInstance = $TestConfig.InstanceSingle
            Login       = $loginName
            Password    = $securePassword
        }
        $newLogin = New-DbaLogin @splatNewLogin

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects
        $null = Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Login $renamedLogin
        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $renamedLogin

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When renaming a login" {
        BeforeAll {
            $splatRename = @{
                SqlInstance = $TestConfig.InstanceSingle
                Login       = $loginName
                NewLogin    = $renamedLogin
            }
            $results = Rename-DbaLogin @splatRename
        }

        It "Should be successful" {
            $results.Status | Should -Be "Successful"
        }

        It "Should return the correct previous login name" {
            $results.PreviousLogin | Should -Be $loginName
        }

        It "Should return the correct new login name" {
            $results.NewLogin | Should -Be $renamedLogin
        }

        It "Should create the renamed login in the database" {
            Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $renamedLogin | Should -Not -BeNullOrEmpty
        }
    }

    Context "Output validation" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $outputLoginName = "dbatoolsci_renameoutput_$(Get-Random)"
            $outputRenamedLogin = "dbatoolsci_renameoutput2_$(Get-Random)"
            $outputPassword = ConvertTo-SecureString "MyV3ry`$ecur3P@ssw0rd" -AsPlainText -Force

            $splatOutputLogin = @{
                SqlInstance = $TestConfig.InstanceSingle
                Login       = $outputLoginName
                Password    = $outputPassword
            }
            $null = New-DbaLogin @splatOutputLogin

            $splatOutputRename = @{
                SqlInstance = $TestConfig.InstanceSingle
                Login       = $outputLoginName
                NewLogin    = $outputRenamedLogin
            }
            $result = Rename-DbaLogin @splatOutputRename
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            $null = Stop-DbaProcess -SqlInstance $TestConfig.InstanceSingle -Login $outputRenamedLogin -ErrorAction SilentlyContinue
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $outputRenamedLogin -ErrorAction SilentlyContinue
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $outputLoginName -ErrorAction SilentlyContinue
        }

        It "Returns output of the documented type" {
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType PSCustomObject
        }

        It "Has the expected properties" {
            $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Database", "PreviousLogin", "NewLogin", "PreviousUser", "NewUser", "Status")
            foreach ($prop in $expectedProperties) {
                $result[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
            }
        }
    }
}