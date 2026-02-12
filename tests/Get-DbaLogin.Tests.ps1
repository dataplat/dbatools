#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLogin",
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
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $SkipLocalTest = $true # Change to $false to run the local-only tests on a local instance. This is being used because the 'locked' test makes assumptions the password policy configuration is enabled for the Windows OS.
        $random = Get-Random

        $password = ConvertTo-SecureString -String "password1A@" -AsPlainText -Force
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Password $password
        $null = New-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin2_$random" -Password $password

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random", "testlogin2_$random" -Force

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Does sql instance have a SA account" {
        It "Should report that one account named SA exists" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login sa
            $results.Count | Should -BeExactly 1
        }
    }

    Context "Check that SA account is enabled" {
        It "Should say the SA account is disabled FALSE" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login sa
            $results.IsDisabled | Should -Be $false
        }
    }

    Context "Check that SA account is SQL Login" {
        BeforeAll {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login sa -Type SQL -Detailed
        }

        It "Should report that one SQL Login named SA exists" {
            $results.Count | Should -BeExactly 1
        }

        It "Should get LoginProperties via Detailed switch" {
            $results.BadPasswordCount | Should -Not -BeNullOrEmpty
            $results.PasswordHash | Should -Not -BeNullOrEmpty
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
            $results[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Login"
        }

        It "Has the expected default display properties" {
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Name", "LoginType", "CreateDate", "LastLogin", "HasAccess", "IsLocked", "IsDisabled", "MustChangePassword")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }

    Context "Validate params" {

        It "Multiple logins" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random", "testlogin2_$random" -Type SQL
            $results.Count | Should -Be 2
            $results.Name | Should -Contain "testlogin1_$random"
            $results.Name | Should -Contain "testlogin2_$random"
        }

        It "ExcludeLogin" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeLogin "testlogin2_$random" -Type SQL
            $results.Name | Should -Not -Contain "testlogin2_$random"
            $results.Name | Should -Contain "testlogin1_$random"

            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeLogin "testlogin1_$random", "testlogin2_$random" -Type SQL
            $results.Name | Should -Not -Contain "testlogin2_$random"
            $results.Name | Should -Not -Contain "testlogin1_$random"
        }

        It "IncludeFilter" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -IncludeFilter "*$random" -Type SQL
            $results.Count | Should -Be 2
            $results.Name | Should -Contain "testlogin1_$random"
            $results.Name | Should -Contain "testlogin2_$random"
        }

        It "ExcludeFilter" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeFilter "*$random" -Type SQL
            $results.Name | Should -Not -Contain "testlogin1_$random"
            $results.Name | Should -Not -Contain "testlogin2_$random"
        }

        It "ExcludeSystemLogin" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -ExcludeSystemLogin -Type SQL
            $results.Name | Should -Not -Contain "sa"
        }

        It "HasAccess" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -HasAccess -Type SQL
            $results.Name | Should -Contain "testlogin1_$random"
            $results.Name | Should -Contain "testlogin2_$random"
        }

        It "Disabled" {
            $null = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Disable
            $result = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Disabled
            $result.Name | Should -Contain "testlogin1_$random"
            $null = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Enable
        }

        It "Detailed" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Detailed -Type SQL

            $results.Count | Should -BeGreaterOrEqual 2

            ($results[0].PSobject.Properties.Name -contains "BadPasswordCount") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "BadPasswordTime") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "DaysUntilExpiration") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "HistoryLength") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "IsMustChange") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "LockoutTime") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "PasswordHash") | Should -Be $true
            ($results[0].PSobject.Properties.Name -contains "PasswordLastSetTime") | Should -Be $true
        }

        It "Locked - Requires password policy enforcement" {
            # Skip this test if not running locally with proper password policy configured
            if ($SkipLocalTest) {
                Set-ItResult -Skipped -Because "Local test disabled - password policy configuration required"
                return
            }

            try {
                # Ensure password policy is enforced for the test login
                $policyResult = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
                $policyResult.PasswordPolicyEnforced | Should -Be $true

                # simulate a lockout
                $invalidPassword = ConvertTo-SecureString -String "invalid" -AsPlainText -Force
                $invalidSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "testlogin1_$random", $invalidPassword

                # exceed the lockout count
                for ($i = 0; $i -le 4; $i++) {
                    try {
                        Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $invalidSqlCredential -ErrorAction SilentlyContinue
                    } catch {
                        Write-Debug "Invalid login attempt $i - expected for account lockout test"
                    }
                    Start-Sleep -Seconds 2
                }

                # Wait a moment for the lockout to register
                Start-Sleep -Seconds 5

                # Test that the account appears in locked accounts
                $lockedResults = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Locked

                # Validate we have results and they contain our test login
                if (-not $lockedResults) {
                    throw "No locked logins returned - account lockout may not be working in this environment"
                }

                # Ensure we have an array for proper Contains operation
                $lockedLoginNames = @($lockedResults | ForEach-Object { $_.Name })
                $lockedLoginNames | Should -Contain "testlogin1_$random"

                # Verify the specific login shows as locked
                $specificResult = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Type SQL
                $specificResult.IsLocked | Should -Be $true

                # Unlock the account for cleanup
                $unlockResult = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Unlock -Force
                $unlockResult.IsLocked | Should -Be $false

                # Verify account no longer appears in locked list
                $lockedResultsAfterUnlock = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Locked
                if ($lockedResultsAfterUnlock) {
                    $unlockedLoginNames = @($lockedResultsAfterUnlock | ForEach-Object { $_.Name })
                    $unlockedLoginNames | Should -Not -Contain "testlogin1_$random"
                }

                # Final verification that the specific login is unlocked
                $finalResult = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Type SQL
                $finalResult.IsLocked | Should -Be $false
            } catch {
                # Clean up in case of failure
                try {
                    Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -Unlock -Force -ErrorAction SilentlyContinue
                } catch {
                    Write-Warning "Failed to unlock test login during cleanup: $_"
                }
                throw
            }
        }

        It "MustChangePassword" {
            $changeResult = Set-DbaLogin -SqlInstance $TestConfig.InstanceSingle -Login "testlogin1_$random" -MustChange -Password $password -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changeResult.MustChangePassword | Should -Be $true

            $result = Get-DbaLogin -SqlInstance $TestConfig.InstanceSingle -MustChangePassword

            # Handle potential null results
            if ($result) {
                $resultNames = @($result | ForEach-Object { $_.Name })
                $resultNames | Should -Contain "testlogin1_$random"
            } else {
                throw "No logins requiring password change found when expected"
            }
        }
    }

}