#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLogin",
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
                "Login",
                "IncludeFilter",
                "ExcludeLogin",
                "ExcludeFilter",
                "ExcludeSystemLogin",
                "Type",
                "HasAccess",
                "Locked",
                "Disabled",
                "MustChangePassword",
                "Detailed",
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
        $SkipLocalTest = $true # Change to $false to run the local-only tests on a local instance. This is being used because the 'locked' test makes assumptions the password policy configuration is enabled for the Windows OS.
        $random = Get-Random

        $password = ConvertTo-SecureString -String "password1A@" -AsPlainText -Force
        New-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random" -Password $password
        New-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin2_$random" -Password $password
    }

    AfterAll {
        Remove-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random", "testlogin2_$random" -Confirm:$false -Force -ErrorAction SilentlyContinue
    }

    Context "Does sql instance have a SA account" {
        BeforeAll {
            $saResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login sa
        }

        It "Should report that one account named SA exists" {
            $saResults.Count | Should -Be 1
        }
    }

    Context "Check that SA account is enabled" {
        BeforeAll {
            $enabledResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login sa
        }

        It "Should say the SA account is disabled FALSE" {
            $enabledResults.IsDisabled | Should -Be "False"
        }
    }

    Context "Check that SA account is SQL Login" {
        BeforeAll {
            $sqlLoginResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login sa -Type SQL -Detailed
        }

        It "Should report that one SQL Login named SA exists" {
            $sqlLoginResults.Count | Should -Be 1
        }
        It "Should get LoginProperties via Detailed switch" {
            $sqlLoginResults.BadPasswordCount | Should -Not -Be $null
            $sqlLoginResults.PasswordHash | Should -Not -Be $null
        }
    }

    Context "Validate params" {

        It "Multiple logins" {
            $multipleResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random", "testlogin2_$random" -Type SQL
            $multipleResults.Count | Should -Be 2
            $multipleResults.Name | Should -Contain "testlogin1_$random"
            $multipleResults.Name | Should -Contain "testlogin2_$random"
        }

        It "ExcludeLogin" {
            $excludeSingleResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -ExcludeLogin "testlogin2_$random" -Type SQL
            $excludeSingleResults.Name | Should -Not -Contain "testlogin2_$random"
            $excludeSingleResults.Name | Should -Contain "testlogin1_$random"

            $excludeMultipleResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -ExcludeLogin "testlogin1_$random", "testlogin2_$random" -Type SQL
            $excludeMultipleResults.Name | Should -Not -Contain "testlogin2_$random"
            $excludeMultipleResults.Name | Should -Not -Contain "testlogin1_$random"
        }

        It "IncludeFilter" {
            $includeFilterResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -IncludeFilter "*$random" -Type SQL
            $includeFilterResults.Count | Should -Be 2
            $includeFilterResults.Name | Should -Contain "testlogin1_$random"
            $includeFilterResults.Name | Should -Contain "testlogin2_$random"
        }

        It "ExcludeFilter" {
            $excludeFilterResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -ExcludeFilter "*$random" -Type SQL
            $excludeFilterResults.Name | Should -Not -Contain "testlogin1_$random"
            $excludeFilterResults.Name | Should -Not -Contain "testlogin2_$random"
        }

        It "ExcludeSystemLogin" {
            $excludeSystemResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -ExcludeSystemLogin -Type SQL
            $excludeSystemResults.Name | Should -Not -Contain "sa"
        }

        It "HasAccess" {
            $hasAccessResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -HasAccess -Type SQL
            $hasAccessResults.Name | Should -Contain "testlogin1_$random"
            $hasAccessResults.Name | Should -Contain "testlogin2_$random"
        }

        It "Disabled" {
            $null = Set-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random" -Disable
            $disabledResult = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Disabled
            $disabledResult.Name | Should -Contain "testlogin1_$random"
            $null = Set-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random" -Enable
        }

        It "Detailed" {
            $detailedResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Detailed -Type SQL

            $detailedResults.Count | Should -BeGreaterOrEqual 2

            ($detailedResults[0].PSobject.Properties.Name -contains "BadPasswordCount") | Should -Be $true
            ($detailedResults[0].PSobject.Properties.Name -contains "BadPasswordTime") | Should -Be $true
            ($detailedResults[0].PSobject.Properties.Name -contains "DaysUntilExpiration") | Should -Be $true
            ($detailedResults[0].PSobject.Properties.Name -contains "HistoryLength") | Should -Be $true
            ($detailedResults[0].PSobject.Properties.Name -contains "IsMustChange") | Should -Be $true
            ($detailedResults[0].PSobject.Properties.Name -contains "LockoutTime") | Should -Be $true
            ($detailedResults[0].PSobject.Properties.Name -contains "PasswordHash") | Should -Be $true
            ($detailedResults[0].PSobject.Properties.Name -contains "PasswordLastSetTime") | Should -Be $true
        }

        It -Skip:$SkipLocalTest "Locked" {
            $policyResults = Set-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $policyResults.PasswordPolicyEnforced | Should -Be $true

            # simulate a lockout
            $invalidPassword = ConvertTo-SecureString -String "invalid" -AsPlainText -Force
            $invalidSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "testlogin1_$random", $invalidPassword

            # exceed the lockout count
            for (($i = 0); $i -le 4; $i++) {
                try {
                    Connect-DbaInstance -SqlInstance $TestConfig.instance1 -SqlCredential $invalidSqlCredential
                } catch {
                    Write-Message -Level Warning -Message "invalid login credentials used on purpose to lock out account"
                    Start-Sleep -s 5
                }
            }

            $lockedResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Locked
            $lockedResults.Name | Should -Contain "testlogin1_$random"

            $checkLockedResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random" -Type SQL
            $checkLockedResults.IsLocked | Should -Be $true

            $unlockResults = Set-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random" -Unlock -Force
            $unlockResults.IsLocked | Should -Be $false

            $afterUnlockResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Locked
            $afterUnlockResults.Name | Should -Not -Contain "testlogin1_$random"

            $finalCheckResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random" -Type SQL
            $finalCheckResults.IsLocked | Should -Be $false
        }

        It "MustChangePassword" {
            $changePasswordResult = Set-DbaLogin -SqlInstance $TestConfig.instance1 -Login "testlogin1_$random" -MustChange -Password $password -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changePasswordResult.MustChangePassword | Should -Be $true

            $mustChangeResults = Get-DbaLogin -SqlInstance $TestConfig.instance1 -MustChangePassword
            $mustChangeResults.Name | Should -Contain "testlogin1_$random"
        }
    }
}