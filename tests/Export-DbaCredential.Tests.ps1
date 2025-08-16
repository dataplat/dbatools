#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Export-DbaCredential",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Identity",
                "SqlCredential",
                "Credential",
                "Path",
                "FilePath",
                "ExcludePassword",
                "Append",
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

        # For all the files that we want to clean up after the test, we create an array that we can iterate through at the end.
        $allFiles = @()

        # Explain what needs to be set up for the test:
        # To test exporting credentials, we need to create test credentials with specific identities and passwords.

        # Set variables. They are available in all the It blocks.
        $plaintext = "ReallyT3rrible!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force
        $captainCredName = "dbatoolsci_CaptainAcred"
        $captainCredIdentity = "dbatoolsci_CaptainAcredId"
        $hulkCredIdentity = "dbatoolsci_Hulk"

        # Create the objects.
        $splatCaptain = @{
            SqlInstance     = $TestConfig.instance2
            Name            = $captainCredName
            Identity        = $captainCredIdentity
            Password        = $password
            EnableException = $true
        }
        $null = New-DbaCredential @splatCaptain

        $splatHulk = @{
            SqlInstance     = $TestConfig.instance2
            Identity        = $hulkCredIdentity
            Password        = $password
            EnableException = $true
        }
        $null = New-DbaCredential @splatHulk

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        $splatCleanup = @{
            SqlInstance     = $TestConfig.instance2
            Identity        = $captainCredIdentity, $hulkCredIdentity
            EnableException = $true
            WarningAction   = "SilentlyContinue"
        }
        $credentialsToRemove = Get-DbaCredential @splatCleanup
        if ($credentialsToRemove) {
            $credentialsToRemove.Drop()
        }

        # Remove all test files.
        Remove-Item -Path $allFiles -ErrorAction SilentlyContinue

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "Should export all credentials" {
        BeforeAll {
            $exportFile = Export-DbaCredential -SqlInstance $TestConfig.instance2
            $exportResults = Get-Content -Path $exportFile -Raw
            $allFiles += $exportFile
        }

        It "Should have information" {
            $exportResults | Should -Not -BeNullOrEmpty
        }

        It "Should have all users" {
            $exportResults | Should -Match "CaptainACred|Hulk"
        }

        It "Should have the password" {
            $exportResults | Should -Match "ReallyT3rrible!"
        }
    }

    Context "Should export a specific credential" {
        BeforeAll {
            $specificFilePath = "$env:USERPROFILE\Documents\dbatoolsci_credential.sql"
            $splatExportSpecific = @{
                SqlInstance = $TestConfig.instance2
                Identity    = $captainCredIdentity
                FilePath    = $specificFilePath
            }
            $null = Export-DbaCredential @splatExportSpecific
            $specificResults = Get-Content -Path $specificFilePath
            $allFiles += $specificFilePath
        }

        It "Should have information" {
            $specificResults | Should -Not -BeNullOrEmpty
        }

        It "Should only have one credential" {
            $specificResults | Should -Match "CaptainAcred"
        }

        It "Should have the password" {
            $specificResults | Should -Match "ReallyT3rrible!"
        }
    }

    Context "Should export a specific credential and append it to existing export" {
        BeforeAll {
            $appendFilePath = "$env:USERPROFILE\Documents\dbatoolsci_credential.sql"
            $splatExportAppend = @{
                SqlInstance = $TestConfig.instance2
                Identity    = $hulkCredIdentity
                FilePath    = $appendFilePath
                Append      = $true
            }
            $null = Export-DbaCredential @splatExportAppend
            $appendResults = Get-Content -Path $appendFilePath
        }

        It "Should have information" {
            $appendResults | Should -Not -BeNullOrEmpty
        }

        It "Should have multiple credentials" {
            $appendResults | Should -Match "Hulk|CaptainA"
        }

        It "Should have the password" {
            $appendResults | Should -Match "ReallyT3rrible!"
        }
    }

    Context "Should export a specific credential excluding the password" {
        BeforeAll {
            $excludePasswordFilePath = "$env:USERPROFILE\Documents\temp-credential.sql"
            $splatExportNoPassword = @{
                SqlInstance     = $TestConfig.instance2
                Identity        = $captainCredIdentity
                FilePath        = $excludePasswordFilePath
                ExcludePassword = $true
            }
            $null = Export-DbaCredential @splatExportNoPassword
            $excludePasswordResults = Get-Content -Path $excludePasswordFilePath
            $allFiles += $excludePasswordFilePath
        }

        It "Should have information" {
            $excludePasswordResults | Should -Not -BeNullOrEmpty
        }

        It "Should contain the correct identity (see #7282)" {
            $excludePasswordResults | Should -Match "IDENTITY = N'dbatoolsci_CaptainAcredId'"
        }

        It "Should not have the password" {
            $excludePasswordResults | Should -Not -Match "ReallyT3rrible!"
        }
    }
}