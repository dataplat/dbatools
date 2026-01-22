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

    Context "Output Validation" {
        BeforeAll {
            $loginName2 = "dbatoolsci_renamelogin_output"
            $renamedLogin2 = "dbatoolsci_renamelogin_output2"
            $password = 'MyV3ry$ecur3P@ssw0rd'
            $securePassword = ConvertTo-SecureString $password -AsPlainText -Force

            $splatNewLogin = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Login           = $loginName2
                Password        = $securePassword
                EnableException = $true
            }
            $null = New-DbaLogin @splatNewLogin

            $splatRename = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Login           = $loginName2
                NewLogin        = $renamedLogin2
                EnableException = $true
            }
            $result = Rename-DbaLogin @splatRename

            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login $renamedLogin2 -EnableException
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain 'System.Management.Automation.PSCustomObject'
        }

        It "Has the expected properties" {
            $expectedProps = @(
                'ComputerName',
                'InstanceName',
                'SqlInstance',
                'Database',
                'PreviousLogin',
                'NewLogin',
                'PreviousUser',
                'NewUser',
                'Status'
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be present in output"
            }
        }

        It "Has ComputerName populated for login rename" {
            $result.ComputerName | Should -Not -BeNullOrEmpty
        }

        It "Has InstanceName populated for login rename" {
            $result.InstanceName | Should -Not -BeNullOrEmpty
        }

        It "Has SqlInstance populated for login rename" {
            $result.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Has PreviousLogin populated for login rename" {
            $result.PreviousLogin | Should -Be $loginName2
        }

        It "Has NewLogin populated for login rename" {
            $result.NewLogin | Should -Be $renamedLogin2
        }

        It "Has null Database for login rename" {
            $result.Database | Should -BeNullOrEmpty
        }

        It "Has null PreviousUser for login rename" {
            $result.PreviousUser | Should -BeNullOrEmpty
        }

        It "Has null NewUser for login rename" {
            $result.NewUser | Should -BeNullOrEmpty
        }
    }
}