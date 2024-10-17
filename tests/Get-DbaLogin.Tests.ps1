param($ModuleName = 'dbatools')

Describe "Get-DbaLogin" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $password = ConvertTo-SecureString -String "password1A@" -AsPlainText -Force
        New-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random" -Password $password
        New-DbaLogin -SqlInstance $global:instance1 -Login "testlogin2_$random" -Password $password
    }

    AfterAll {
        Remove-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random", "testlogin2_$random" -Confirm:$false -Force
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaLogin
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Login parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[] -Not -Mandatory
        }
        It "Should have IncludeFilter parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeFilter -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeLogin parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeLogin -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeFilter parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeFilter -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeSystemLogin parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemLogin -Type Switch -Not -Mandatory
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String -Not -Mandatory
        }
        It "Should have HasAccess parameter" {
            $CommandUnderTest | Should -HaveParameter HasAccess -Type Switch -Not -Mandatory
        }
        It "Should have Locked parameter" {
            $CommandUnderTest | Should -HaveParameter Locked -Type Switch -Not -Mandatory
        }
        It "Should have Disabled parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type Switch -Not -Mandatory
        }
        It "Should have MustChangePassword parameter" {
            $CommandUnderTest | Should -HaveParameter MustChangePassword -Type Switch -Not -Mandatory
        }
        It "Should have Detailed parameter" {
            $CommandUnderTest | Should -HaveParameter Detailed -Type Switch -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Does sql instance have a SA account" {
        It "Should report that one account named SA exists" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login sa
            $results.Count | Should -Be 1
        }
    }

    Context "Check that SA account is enabled" {
        It "Should say the SA account is disabled FALSE" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login sa
            $results.IsDisabled | Should -Be "False"
        }
    }

    Context "Check that SA account is SQL Login" {
        It "Should report that one SQL Login named SA exists" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login sa -Type SQL -Detailed
            $results.Count | Should -Be 1
        }
        It "Should get LoginProperties via Detailed switch" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login sa -Type SQL -Detailed
            $results.BadPasswordCount | Should -Not -BeNullOrEmpty
            $results.PasswordHash | Should -Not -BeNullOrEmpty
        }
    }

    Context "Validate params" {
        It "Multiple logins" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random", "testlogin2_$random" -Type SQL
            $results.Count | Should -Be 2
            $results.Name | Should -Contain "testlogin1_$random"
            $results.Name | Should -Contain "testlogin2_$random"
        }

        It "ExcludeLogin" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -ExcludeLogin "testlogin2_$random" -Type SQL
            $results.Name | Should -Not -Contain "testlogin2_$random"
            $results.Name | Should -Contain "testlogin1_$random"

            $results = Get-DbaLogin -SqlInstance $global:instance1 -ExcludeLogin "testlogin1_$random", "testlogin2_$random" -Type SQL
            $results.Name | Should -Not -Contain "testlogin2_$random"
            $results.Name | Should -Not -Contain "testlogin1_$random"
        }

        It "IncludeFilter" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -IncludeFilter "*$random" -Type SQL
            $results.Count | Should -Be 2
            $results.Name | Should -Contain "testlogin1_$random"
            $results.Name | Should -Contain "testlogin2_$random"
        }

        It "ExcludeFilter" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -ExcludeFilter "*$random" -Type SQL
            $results.Name | Should -Not -Contain "testlogin1_$random"
            $results.Name | Should -Not -Contain "testlogin2_$random"
        }

        It "ExcludeSystemLogin" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -ExcludeSystemLogin -Type SQL
            $results.Name | Should -Not -Contain "sa"
        }

        It "HasAccess" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -HasAccess -Type SQL
            $results.Name | Should -Contain "testlogin1_$random"
            $results.Name | Should -Contain "testlogin2_$random"
        }

        It "Disabled" {
            $null = Set-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random" -Disable
            $result = Get-DbaLogin -SqlInstance $global:instance1 -Disabled
            $result.Name | Should -Contain "testlogin1_$random"
            $null = Set-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random" -Enable
        }

        It "Detailed" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -Detailed -Type SQL

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

        It "MustChangePassword" {
            $changeResult = Set-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random" -MustChange -Password $password -PasswordPolicyEnforced -PasswordExpirationEnabled
            $changeResult.MustChangePassword | Should -Be $true

            $result = Get-DbaLogin -SqlInstance $global:instance1 -MustChangePassword
            $result.Name | Should -Contain "testlogin1_$random"
        }
    }

    Context "Locked" {
        BeforeDiscovery {
            $SkipLocalTest = [Environment]::GetEnvironmentVariable('SkipLocalTest') -eq $true
        }
        It "Should lock and unlock a login" -Skip:$SkipLocalTest {
            $results = Set-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random" -PasswordPolicyEnforced -EnableException
            $results.PasswordPolicyEnforced | Should -Be $true

            # simulate a lockout
            $invalidPassword = ConvertTo-SecureString -String 'invalid' -AsPlainText -Force
            $invalidSqlCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "testlogin1_$random", $invalidPassword

            # exceed the lockout count
            for (($i = 0); $i -le 4; $i++) {
                try {
                    Connect-DbaInstance -SqlInstance $global:instance1 -SqlCredential $invalidSqlCredential
                } catch {
                    Write-Message -Level Warning -Message "invalid login credentials used on purpose to lock out account"
                    Start-Sleep -s 5
                }
            }

            $results = Get-DbaLogin -SqlInstance $global:instance1 -Locked
            $results.Name | Should -Contain "testlogin1_$random"

            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random" -Type SQL
            $results.IsLocked | Should -Be $true

            $results = Set-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random" -Unlock -Force
            $results.IsLocked | Should -Be $false

            $results = Get-DbaLogin -SqlInstance $global:instance1 -Locked
            $results.Name | Should -Not -Contain "testlogin1_$random"

            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login "testlogin1_$random" -Type SQL
            $results.IsLocked | Should -Be $false
        }
    }
}
