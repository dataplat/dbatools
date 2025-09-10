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
            SqlInstance = $TestConfig.instance1
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
        $null = Stop-DbaProcess -SqlInstance $TestConfig.instance1 -Login $renamedLogin
        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login $renamedLogin

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When renaming a login" {
        BeforeAll {
            $splatRename = @{
                SqlInstance = $TestConfig.instance1
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
            Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login $renamedLogin | Should -Not -BeNullOrEmpty
        }
    }
}