#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaCredential",
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
                "Credential",
                "ExcludeCredential",
                "Identity",
                "ExcludeIdentity",
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

        # Set up test server connection and create unique credential names for this test run
        $testServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $credentialName = "dbatoolsci_test_$(Get-Random)"
        $credentialName2 = "dbatoolsci_test_$(Get-Random)"
        $credentialName3 = "dbatoolsci_test_$(Get-Random)"
        $credentialName4 = "dbatoolsci_test_$(Get-Random)"

        # Track all credentials created during tests for cleanup
        $createdCredentials = @()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Clean up any remaining test credentials
        $existingCredentials = Get-DbaCredential -SqlInstance $TestConfig.InstanceSingle | Where-Object Name -like "dbatoolsci_test_*"
        if ($existingCredentials) {
            $existingCredentials | Remove-DbaCredential -ErrorAction SilentlyContinue
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When removing SQL credentials" {
        BeforeEach {
            # Create fresh credentials for each test to ensure isolation
            $splatCreateCred1 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Query       = "CREATE CREDENTIAL $credentialName WITH IDENTITY = 'NT AUTHORITY\SYSTEM', SECRET = 'G31o)lkJ8HNd!';"
            }
            $null = Invoke-DbaQuery @splatCreateCred1

            $splatCreateCred2 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Query       = "CREATE CREDENTIAL $credentialName2 WITH IDENTITY = 'NT AUTHORITY\SYSTEM', SECRET = 'G31o)lkJ8HNd!';"
            }
            $null = Invoke-DbaQuery @splatCreateCred2
        }

        AfterEach {
            # Clean up credentials created in this specific test
            $splatCleanup = @{
                SqlInstance = $TestConfig.InstanceSingle
                Credential  = @($credentialName, $credentialName2, $credentialName3, $credentialName4)
            }
            Remove-DbaCredential @splatCleanup -ErrorAction SilentlyContinue
        }

        It "removes a SQL credential" {
            $splatGetCredential = @{
                SqlInstance = $TestConfig.InstanceSingle
                Credential  = $credentialName
            }
            (Get-DbaCredential @splatGetCredential) | Should -Not -BeNullOrEmpty

            $splatRemoveCredential = @{
                SqlInstance = $TestConfig.InstanceSingle
                Credential  = $credentialName
            }
            Remove-DbaCredential @splatRemoveCredential

            (Get-DbaCredential @splatGetCredential) | Should -BeNullOrEmpty
        }

        It "supports piping SQL credential" {
            $splatGetCredential = @{
                SqlInstance = $TestConfig.InstanceSingle
                Credential  = $credentialName
            }
            (Get-DbaCredential @splatGetCredential) | Should -Not -BeNullOrEmpty

            Get-DbaCredential @splatGetCredential | Remove-DbaCredential
            (Get-DbaCredential @splatGetCredential) | Should -BeNullOrEmpty
        }

        It "removes all SQL credentials but excluded" {
            # Create additional credential for this specific test
            $splatCreateCred3 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Query       = "CREATE CREDENTIAL $credentialName3 WITH IDENTITY = 'NT AUTHORITY\SYSTEM', SECRET = 'G31o)lkJ8HNd!';"
            }
            $null = Invoke-DbaQuery @splatCreateCred3

            $splatGetCredential2 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Credential  = $credentialName2
            }
            (Get-DbaCredential @splatGetCredential2) | Should -Not -BeNullOrEmpty

            $splatGetExcluded = @{
                SqlInstance       = $TestConfig.InstanceSingle
                ExcludeCredential = $credentialName2
            }
            (Get-DbaCredential @splatGetExcluded) | Should -Not -BeNullOrEmpty

            $splatRemoveExcluded = @{
                SqlInstance       = $TestConfig.InstanceSingle
                ExcludeCredential = $credentialName2
            }
            Remove-DbaCredential @splatRemoveExcluded

            (Get-DbaCredential @splatGetExcluded) | Should -BeNullOrEmpty
            (Get-DbaCredential @splatGetCredential2) | Should -Not -BeNullOrEmpty
        }

        It "removes all SQL credentials" {
            # Create additional credentials for this specific test
            $splatCreateCred4 = @{
                SqlInstance = $TestConfig.InstanceSingle
                Query       = "CREATE CREDENTIAL $credentialName4 WITH IDENTITY = 'NT AUTHORITY\SYSTEM', SECRET = 'G31o)lkJ8HNd!';"
            }
            $null = Invoke-DbaQuery @splatCreateCred4

            $splatGetAll = @{
                SqlInstance = $TestConfig.InstanceSingle
            }
            (Get-DbaCredential @splatGetAll) | Should -Not -BeNullOrEmpty

            $splatRemoveAll = @{
                SqlInstance = $TestConfig.InstanceSingle
            }
            Remove-DbaCredential @splatRemoveAll

            (Get-DbaCredential @splatGetAll) | Should -BeNullOrEmpty
        }
    }
}