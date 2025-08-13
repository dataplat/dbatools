#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Remove-DbaCredential",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = @()
            if ($TestConfig -and $TestConfig.CommonParameters) {
                $expectedParameters += $TestConfig.CommonParameters
            }
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
        }

        It "Should have the expected parameters" {
            $comparison = Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters
            $comparison | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Set variables. They are available in all the It blocks.
        $global:serverInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        $global:credentialName = "dbatoolsci_test_$(Get-Random)"
        $global:credentialName2 = "dbatoolsci_test_$(Get-Random)"

        $null = Invoke-DbaQuery -SqlInstance $global:serverInstance -Query "CREATE CREDENTIAL $global:credentialName WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';" -EnableException
        $null = Invoke-DbaQuery -SqlInstance $global:serverInstance -Query "CREATE CREDENTIAL $global:credentialName2 WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';" -EnableException
    }

    AfterEach {
        # We want to run all commands in the AfterEach block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup any remaining test credentials
        try {
            $testCredentials = Get-DbaCredential -SqlInstance $global:serverInstance | Where-Object Name -like "dbatoolsci_test_*"
            if ($testCredentials) {
                $testCredentials | Remove-DbaCredential -Confirm:$false -ErrorAction SilentlyContinue
            }
        } catch {
            # Ignore cleanup errors
        }

        # Reset EnableException setting
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Commands work as expected" {
        It "Removes a SQL credential" {
            @(Get-DbaCredential -SqlInstance $global:serverInstance -Credential $global:credentialName) | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $global:serverInstance -Credential $global:credentialName -Confirm:$false
            @(Get-DbaCredential -SqlInstance $global:serverInstance -Credential $global:credentialName) | Should -BeNullOrEmpty
        }

        It "Supports piping SQL credential" {
            @(Get-DbaCredential -SqlInstance $global:serverInstance -Credential $global:credentialName) | Should -Not -BeNullOrEmpty
            Get-DbaCredential -SqlInstance $global:serverInstance -Credential $global:credentialName | Remove-DbaCredential -Confirm:$false
            @(Get-DbaCredential -SqlInstance $global:serverInstance -Credential $global:credentialName) | Should -BeNullOrEmpty
        }

        It "Removes all SQL credentials but excluded" {
            @(Get-DbaCredential -SqlInstance $global:serverInstance -Credential $global:credentialName2) | Should -Not -BeNullOrEmpty
            @(Get-DbaCredential -SqlInstance $global:serverInstance -ExcludeCredential $global:credentialName2) | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $global:serverInstance -ExcludeCredential $global:credentialName2 -Confirm:$false
            @(Get-DbaCredential -SqlInstance $global:serverInstance -ExcludeCredential $global:credentialName2) | Should -BeNullOrEmpty
            @(Get-DbaCredential -SqlInstance $global:serverInstance -Credential $global:credentialName2) | Should -Not -BeNullOrEmpty
        }

        It "Removes all SQL credentials" {
            @(Get-DbaCredential -SqlInstance $global:serverInstance) | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $global:serverInstance -Confirm:$false
            @(Get-DbaCredential -SqlInstance $global:serverInstance) | Should -BeNullOrEmpty
        }
    }
}