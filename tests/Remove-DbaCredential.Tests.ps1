#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaCredential",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
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

        # Set variables. They are available in all the It blocks.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    BeforeEach {
        $credentialName = "dbatoolsci_test_$(Get-Random)"
        $credentialName2 = "dbatoolsci_test_$(Get-Random)"

        $null = Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL $credentialName WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"
        $null = Invoke-DbaQuery -SqlInstance $server -Query "CREATE CREDENTIAL $credentialName2 WITH IDENTITY = 'NT AUTHORITY\SYSTEM',  SECRET = 'G31o)lkJ8HNd!';"
    }

    Context "Commands work as expected" {
        It "Removes a SQL credential" {
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName) | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $server -Credential $credentialName -Confirm:$false
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName) | Should -BeNullOrEmpty
        }

        It "Supports piping SQL credential" {
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName) | Should -Not -BeNullOrEmpty
            Get-DbaCredential -SqlInstance $server -Credential $credentialName | Remove-DbaCredential -Confirm:$false
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName) | Should -BeNullOrEmpty
        }

        It "Removes all SQL credentials but excluded" {
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName2) | Should -Not -BeNullOrEmpty
            (Get-DbaCredential -SqlInstance $server -ExcludeCredential $credentialName2) | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $server -ExcludeCredential $credentialName2 -Confirm:$false
            (Get-DbaCredential -SqlInstance $server -ExcludeCredential $credentialName2) | Should -BeNullOrEmpty
            (Get-DbaCredential -SqlInstance $server -Credential $credentialName2) | Should -Not -BeNullOrEmpty
        }

        It "Removes all SQL credentials" {
            (Get-DbaCredential -SqlInstance $server) | Should -Not -BeNullOrEmpty
            Remove-DbaCredential -SqlInstance $server -Confirm:$false
            (Get-DbaCredential -SqlInstance $server) | Should -BeNullOrEmpty
        }
    }
}