#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Start-DbaAzMigration",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeDiscovery {
            $emptySecureToken = New-Object System.Security.SecureString
            $emptySecureToken.MakeReadOnly()
            $scriptMethodToken = [pscustomobject]@{}
            $splatAddScriptMethodTokenMember = @{
                InputObject = $scriptMethodToken
                MemberType  = "ScriptMethod"
                Name        = "GetAccessToken"
                Value       = { "not-a-clr-renewable-token" }
            }
            Add-Member @splatAddScriptMethodTokenMember
            $script:invalidAccessTokenCases = @(
                @{ Name = "numeric zero"; Value = 0 }
                @{ Name = "boolean false"; Value = $false }
                @{ Name = "an empty SecureString"; Value = $emptySecureToken }
                @{ Name = "an object with a blank Token property"; Value = [pscustomobject]@{ Token = "" } }
                @{ Name = "an object with only a PowerShell GetAccessToken script method"; Value = $scriptMethodToken }
            )
        }

        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "Destination",
                "SourceSqlCredential",
                "DestinationSqlCredential",
                "DestinationAccessToken",
                "Database",
                "ExcludeDatabase",
                "Path",
                "ExportDacOption",
                "ImportDacOption",
                "Force",
                "KeepBacpac",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Rejects a falsey invalid export option before connecting" {
            $splatInvalidExportOption = @{
                Source          = "not-used"
                Destination     = "not-used"
                ExportDacOption = 0
                EnableException = $true
            }
            {
                Start-DbaAzMigration @splatInvalidExportOption
            } | Should -Throw "*Microsoft.SqlServer.Dac.DacExportOptions*"
        }

        It "Rejects a falsey invalid import option before connecting" {
            $splatInvalidImportOption = @{
                Source          = "not-used"
                Destination     = "not-used"
                ImportDacOption = ""
                EnableException = $true
            }
            {
                Start-DbaAzMigration @splatInvalidImportOption
            } | Should -Throw "*Microsoft.SqlServer.Dac.DacImportOptions*"
        }

        It "Rejects a destination credential and access token together before connecting" {
            $securePassword = New-Object System.Security.SecureString
            foreach ($passwordCharacter in "unused".ToCharArray()) {
                $securePassword.AppendChar($passwordCharacter)
            }
            $securePassword.MakeReadOnly()
            $credential = New-Object System.Management.Automation.PSCredential -ArgumentList "unused", $securePassword
            $splatConflictingAuthentication = @{
                Source                   = "not-used"
                Destination              = "not-used"
                DestinationSqlCredential = $credential
                DestinationAccessToken   = "unused-token"
                EnableException          = $true
            }

            { Start-DbaAzMigration @splatConflictingAuthentication } | Should -Throw "*cannot be used together*"
        }

        It "Rejects an explicitly bound blank destination access token before connecting" {
            $splatBlankAccessToken = @{
                Source                 = "not-used"
                Destination            = "not-used"
                DestinationAccessToken = ""
                EnableException        = $true
            }

            { Start-DbaAzMigration @splatBlankAccessToken } | Should -Throw "*DestinationAccessToken*non-empty*"
        }

        It "Rejects an explicitly bound null destination access token before connecting" {
            $splatNullAccessToken = @{
                Source                 = "not-used"
                Destination            = "not-used"
                DestinationAccessToken = $null
                EnableException        = $true
            }

            { Start-DbaAzMigration @splatNullAccessToken } | Should -Throw "*DestinationAccessToken*non-empty*"
        }

        It "Rejects <Name> as a destination access token before connecting" -ForEach $script:invalidAccessTokenCases {
            $splatInvalidAccessToken = @{
                Source                 = "not-used"
                Destination            = "not-used"
                DestinationAccessToken = $Value
                EnableException        = $true
            }

            { Start-DbaAzMigration @splatInvalidAccessToken } | Should -Throw "*DestinationAccessToken*non-empty*"
        }

        It "Accepts established access token shapes" {
            (Get-Command Start-DbaAzMigration).Parameters["DestinationAccessToken"].ParameterType | Should -Be ([PSObject])
        }

        It "Rejects an explicitly bound blank string database selection before connecting" {
            $splatBlankDatabase = @{
                Source          = "not-used"
                Destination     = "not-used"
                Database        = ""
                EnableException = $true
            }

            { Start-DbaAzMigration @splatBlankDatabase } | Should -Throw "*at least one non-blank database name*"
        }

        It "Rejects an explicitly bound null database selection before connecting" {
            $splatNullDatabase = @{
                Source          = "not-used"
                Destination     = "not-used"
                Database        = $null
                EnableException = $true
            }

            { Start-DbaAzMigration @splatNullDatabase } | Should -Throw "*at least one non-blank database name*"
        }

        It "Rejects an explicitly bound empty array database selection before connecting" {
            $splatEmptyDatabaseArray = @{
                Source          = "not-used"
                Destination     = "not-used"
                Database        = @()
                EnableException = $true
            }

            { Start-DbaAzMigration @splatEmptyDatabaseArray } | Should -Throw "*at least one non-blank database name*"
        }

        It "Rejects a file path in friendly mode before connecting" {
            $filePath = Join-Path $TestDrive "not-a-directory.txt"
            Set-Content -LiteralPath $filePath -Value "not a directory"
            $warnings = @()
            # The warning is what this test is about, so it is silenced on the stream and asserted on
            # its own warning variable instead. A test run must not print warnings.
            $splatInvalidPath = @{
                Source          = "not-used"
                Destination     = "not-used"
                Path            = $filePath
                WarningVariable = "warnings"
                WarningAction   = "SilentlyContinue"
            }

            $result = Start-DbaAzMigration @splatInvalidPath

            $result | Should -BeNullOrEmpty
            @($warnings | Where-Object Message -Like "*must be a directory*").Count | Should -BeGreaterOrEqual 1
            @($warnings | Where-Object Message -Like "*Failure connecting*") | Should -BeNullOrEmpty
        }
    }

    Context "Migration lifecycle callbacks" {
        It "Invokes an injected callback with the requested lifecycle name" {
            InModuleScope dbatools {
                $script:observedMigrationCallbackName = $null
                $script:StartDbaAzMigrationCallback = {
                    param($Name)

                    $script:observedMigrationCallbackName = $Name
                }

                try {
                    Invoke-DbaAzMigrationCallback -Name "BeforeDestinationPromotion"

                    $script:observedMigrationCallbackName | Should -Be "BeforeDestinationPromotion"
                } finally {
                    Remove-Variable StartDbaAzMigrationCallback -Scope Script
                    Remove-Variable observedMigrationCallbackName -Scope Script
                }
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $script:testInstance = if ($TestConfig.InstanceSingle) { $TestConfig.InstanceSingle } else { "localhost" }
    }

    Context "Boundary validation" {
        It "Rejects an invalid export option before connecting" {
            $splatInvalidExportMigration = @{
                Source          = $script:testInstance
                Destination     = $script:testInstance
                ExportDacOption = [pscustomobject]@{ Name = "invalid" }
                EnableException = $true
            }
            if ($TestConfig.SqlCred) {
                $splatInvalidExportMigration.SourceSqlCredential = $TestConfig.SqlCred
                $splatInvalidExportMigration.DestinationSqlCredential = $TestConfig.SqlCred
            }

            { Start-DbaAzMigration @splatInvalidExportMigration } | Should -Throw "*Microsoft.SqlServer.Dac.DacExportOptions*"
        }

        It "Rejects an invalid import option before connecting" {
            $splatInvalidImportMigration = @{
                Source          = $script:testInstance
                Destination     = $script:testInstance
                ImportDacOption = [pscustomobject]@{ Name = "invalid" }
                EnableException = $true
            }
            if ($TestConfig.SqlCred) {
                $splatInvalidImportMigration.SourceSqlCredential = $TestConfig.SqlCred
                $splatInvalidImportMigration.DestinationSqlCredential = $TestConfig.SqlCred
            }

            { Start-DbaAzMigration @splatInvalidImportMigration } | Should -Throw "*Microsoft.SqlServer.Dac.DacImportOptions*"
        }

        It "Rejects a destination that is not Azure SQL Database" {
            $splatNonAzureDestinationMigration = @{
                Source          = $script:testInstance
                Destination     = $script:testInstance
                Database        = "dbatoolsci_azmigration_validation"
                EnableException = $true
            }
            if ($TestConfig.SqlCred) {
                $splatNonAzureDestinationMigration.SourceSqlCredential = $TestConfig.SqlCred
                $splatNonAzureDestinationMigration.DestinationSqlCredential = $TestConfig.SqlCred
            }

            { Start-DbaAzMigration @splatNonAzureDestinationMigration } | Should -Throw "*Azure SQL Database*Copy-DbaDatabase*"
        }
    }
}
