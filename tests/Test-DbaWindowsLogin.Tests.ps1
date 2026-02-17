#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Test-DbaWindowsLogin",
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
                "ExcludeLogin",
                "FilterBy",
                "IgnoreDomains",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Command actually works" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
            $results = Test-DbaWindowsLogin -SqlInstance $TestConfig.instance1 -OutVariable "global:dbatoolsciOutput"
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should return results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a Type of User, Group, or Computer" {
            $results | ForEach-Object {
                $PSItem.Type | Should -BeIn "User", "Group", "Computer"
            }
        }

        It "Should have a Found property that is a boolean" {
            $results | ForEach-Object {
                $PSItem.Found | Should -BeOfType [bool]
            }
        }
    }

    Context "Output validation" {
        AfterAll {
            $global:dbatoolsciOutput = $null
        }

        It "Should return a PSCustomObject" {
            $global:dbatoolsciOutput[0] | Should -BeOfType [PSCustomObject]
        }

        It "Should have the expected properties" {
            $expectedProperties = @(
                "Server",
                "Domain",
                "Login",
                "Type",
                "Found",
                "SamAccountNameMismatch",
                "DisabledInSQLServer",
                "AccountNotDelegated",
                "AllowReversiblePasswordEncryption",
                "CannotChangePassword",
                "PasswordExpired",
                "LockedOut",
                "Enabled",
                "PasswordNeverExpires",
                "PasswordNotRequired",
                "SmartcardLogonRequired",
                "TrustedForDelegation",
                "UserAccountControl"
            )
            $actualProperties = $global:dbatoolsciOutput[0].PSObject.Properties.Name
            Compare-Object -ReferenceObject $expectedProperties -DifferenceObject $actualProperties | Should -BeNullOrEmpty
        }

        It "Should have the correct default display columns" {
            $expectedColumns = @(
                "Server",
                "Domain",
                "Login",
                "Type",
                "Found",
                "SamAccountNameMismatch",
                "DisabledInSQLServer",
                "PasswordExpired",
                "LockedOut",
                "Enabled",
                "PasswordNotRequired"
            )
            $defaultColumns = $global:dbatoolsciOutput[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $expectedColumns -DifferenceObject $defaultColumns | Should -BeNullOrEmpty
        }

        It "Should have accurate .OUTPUTS documentation" {
            $help = Get-Help $CommandName -Full
            $help.returnValues.returnValue.type.name | Should -Match "PSCustomObject"
        }
    }
}