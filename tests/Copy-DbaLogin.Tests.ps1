#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Login",
                "ExcludeLogin",
                "ExcludeSystemLogins",
                "SyncSaName",
                "OutFile",
                "InputObject",
                "LoginRenameHashtable",
                "KillActiveConnection",
                "ExcludePermissionSync",
                "NewSid",
                "ObjectLevel",
                "Force",
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

        # drop all objects
        Function Initialize-TestLogin {
            Param ($Instance, $Login)
            Get-DbaProcess -SqlInstance $Instance -Login $Login | Stop-DbaProcess
            if ($l = Get-DbaLogin -SqlInstance $Instance -Login $Login) {
                foreach ($map in $l.EnumDatabaseMappings()) {
                    $null = Invoke-DbaQuery -SqlInstance $Instance -Database $map.DbName -Query "DROP USER [$($map.Username)]"
                }
                $l.Drop()
            }
            $dropUserQuery = "IF EXISTS (SELECT * FROM sys.database_principals WHERE name = '{0}') DROP USER [{0}]" -f $Login
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropUserQuery
        }
        $logins = "claudio", "port", "tester", "tester_new"
        $dropTableQuery = "IF EXISTS (SELECT * FROM sys.tables WHERE name = 'tester_table') DROP TABLE tester_table"
        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery

        }

        # create objects
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql"

        $tableQuery = @("CREATE TABLE tester_table (a int)", "CREATE USER tester FOR LOGIN tester", "GRANT INSERT ON tester_table TO tester;")
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy1 -Database tempdb -Query ($tableQuery -join '; ')
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -Query $tableQuery[0]

        # we want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    BeforeEach {
        # cleanup targets
        Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login tester
        Initialize-TestLogin -Instance $TestConfig.InstanceCopy1 -Login tester_new
    }
    AfterAll {
        # we want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # cleanup everything
        $logins = "claudio", "port", "tester", "tester_new"

        foreach ($instance in $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Copy login with the same properties." {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        }
        It "Should copy successfully" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Login Tester
            $script:outputValidationResults = $results
            $results.Status | Should -Be "Successful"
            $login1 = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -login Tester
            $login2 = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy2 -login Tester

            $login2 | Should -Not -BeNullOrEmpty

            # Compare its value
            $login1.Name | Should -Be $login2.Name
            $login1.Language | Should -Be $login2.Language
            $login1.Credential | Should -Be $login2.Credential
            $login1.DefaultDatabase | Should -Be $login2.DefaultDatabase
            $login1.IsDisabled | Should -Be $login2.IsDisabled
            $login1.IsLocked | Should -Be $login2.IsLocked
            $login1.IsPasswordExpired | Should -Be $login2.IsPasswordExpired
            $login1.PasswordExpirationEnabled | Should -Be $login2.PasswordExpirationEnabled
            $login1.PasswordPolicyEnforced | Should -Be $login2.PasswordPolicyEnforced
            $login1.Sid | Should -Be $login2.Sid
            $login1.Status | Should -Be $login2.Status
        }

        It "Should login with newly created Sql Login (also tests credential login) and gets name" {
            $password = ConvertTo-SecureString -Force -AsPlainText tester1
            $cred = New-Object System.Management.Automation.PSCredential ("tester", $password)
            $s = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy1 -SqlCredential $cred
            $s.Name | Should -Be $TestConfig.InstanceCopy1
        }

        It "Returns output of the expected type" {
            $outputResult = $script:outputValidationResults
            $outputResult | Should -Not -BeNullOrEmpty
            $outputResult[0].psobject.TypeNames | Should -Contain "dbatools.MigrationObject"
        }

        It "Has the expected default display properties" {
            $outputResult = $script:outputValidationResults
            $defaultProps = $outputResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("DateTime", "SourceServer", "DestinationServer", "Name", "Type", "Status", "Notes")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }

        It "Has the correct values for key properties" {
            $outputResult = $script:outputValidationResults
            $outputResult[0].Name | Should -BeExactly "tester"
            $outputResult[0].Type | Should -BeLike "Login - *"
            $outputResult[0].Status | Should -BeExactly "Successful"
            $outputResult[0].SourceServer | Should -Not -BeNullOrEmpty
            $outputResult[0].DestinationServer | Should -Not -BeNullOrEmpty
        }
    }

    Context "No overwrite" {
        It "Should say skipped" {
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.InstanceCopy2 -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql"
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -Login tester
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "ExcludeSystemLogins Parameter" {
        It "Should say skipped" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Destination $TestConfig.InstanceCopy2 -ExcludeSystemLogins
            $results.Status | Should -Contain 'Skipped'
            if (([DbaInstanceParameter]$TestConfig.InstanceCopy1).ComputerName -ne ([DbaInstanceParameter]$TestConfig.InstanceCopy2).ComputerName) {
                $results.Notes | Should -Contain 'Local machine name'
            } else {
                $results.Notes | Should -Contain 'System login'
            }
        }
    }

    Context "Supports pipe" {
        It "migrates the one tester login" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester | Copy-DbaLogin -Destination $TestConfig.InstanceCopy2 -Force
            $results.Name | Should -Be "tester"
            $results.Status | Should -Be "Successful"
        }
    }

    Context "Supports cloning" {
        It "clones the one tester login" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester -Destination $TestConfig.InstanceCopy1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login using pipe" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester | Copy-DbaLogin -Destination $TestConfig.InstanceCopy1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login to a different server with a new name" {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login $_
            }
            $results = Get-DbaLogin -SqlInstance $TestConfig.InstanceCopy1 -Login tester | Copy-DbaLogin -Destination $TestConfig.InstanceCopy2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $login = (Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2).Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $login | Remove-DbaLogin -Force
        }
    }

    Context "Supports db object permissions" {
        BeforeAll {
            $tempExportFile = [System.IO.Path]::GetTempFileName()
        }
        BeforeEach {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $TestConfig.InstanceCopy2 -Login $_
            }
        }
        AfterAll {
            Remove-Item -Path $tempExportFile -Force
        }
        It "clones the one tester login with sysadmin permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester -Destination $TestConfig.InstanceCopy2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $role = $i2.Roles['sysadmin']
            $role.EnumMemberNames() | Should -Contain $results.Name
        }
        It "clones the one tester login with object permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester -Destination $TestConfig.InstanceCopy2 -LoginRenameHashtable @{ tester = 'tester_new' } -ObjectLevel
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceCopy2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $permissions = Export-DbaUser -SqlInstance $TestConfig.InstanceCopy2 -Database tempdb -User tester_new -Passthru
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester_new`]*'
        }
        It "scripts out two tester login with object permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.InstanceCopy1 -Login tester, port -OutFile $tempExportFile -ObjectLevel
            $results | Should -Be $tempExportFile
            $permissions = Get-Content $tempExportFile -Raw
            $permissions | Should -BeLike '*CREATE LOGIN `[tester`]*'
            $permissions | Should -Match "(ALTER SERVER ROLE \[sysadmin\] ADD MEMBER \[tester\]|EXEC sp_addsrvrolemember @rolename=N'sysadmin', @loginame=N'tester')"
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester`]*'
            $permissions | Should -BeLike '*CREATE LOGIN `[port`]*'
            $permissions | Should -BeLike '*GRANT CONNECT SQL TO `[port`]*'
        }
    }

    Context "Linux SQL Server protection for BUILTIN\Administrators" -Skip:(-not $TestConfig.instanceLinux) {
        It "Should skip BUILTIN\Administrators on Linux source with -Force" {
            $splatCopy = @{
                Source      = $TestConfig.instanceLinux
                Destination = $TestConfig.InstanceCopy1
                Login       = "BUILTIN\Administrators"
                Force       = $true
            }
            $results = Copy-DbaLogin @splatCopy
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "BUILTIN\Administrators is a critical system login"
        }

        It "Should skip BUILTIN\Administrators on Linux destination with -Force" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.instanceLinux
                Login       = "BUILTIN\Administrators"
                Force       = $true
            }
            $results = Copy-DbaLogin @splatCopy
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "BUILTIN\Administrators is a critical system login"
        }
    }

    Context "Regression test for issue #9163 - Warn when login not found" {
        It "Should warn when specified login does not exist on source" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "nonexistentlogin"
            }
            $result = Copy-DbaLogin @splatCopy -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warn | Should -Not -BeNullOrEmpty
            $warn | Should -BeLike "*nonexistentlogin*not found*"
        }

        It "Should warn for each non-existent login when multiple are specified" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "nonexistent1", "nonexistent2"
            }
            $result = Copy-DbaLogin @splatCopy -WarningVariable warn -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warn.Count | Should -Be 2
            $warn[0] | Should -BeLike "*nonexistent1*not found*"
            $warn[1] | Should -BeLike "*nonexistent2*not found*"
        }

        It "Should not warn when login exists" {
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "tester"
            }
            $result = Copy-DbaLogin @splatCopy -WarningVariable warn -WarningAction SilentlyContinue
            $result.Status | Should -Be "Successful"
            $warn | Should -BeNullOrEmpty
        }
    }

    Context "Regression test for issue #8572 - Windows group lockout protection" {
        It "Should not throw when processing SQL logins with -Force" {
            # Verify SQL logins are not affected by Windows group checks
            $splatCopy = @{
                Source      = $TestConfig.InstanceCopy1
                Destination = $TestConfig.InstanceCopy2
                Login       = "tester"
                Force       = $true
            }
            $results = Copy-DbaLogin @splatCopy
            $results.Status | Should -Be "Successful"
        }

        It "Should handle Windows logins gracefully when not in a domain" {
            # This test verifies the code path doesn't break non-domain scenarios
            # In CI (non-domain), Windows logins typically fail earlier in the process
            # but the lockout protection code should not introduce new errors
            {
                $splatCopy = @{
                    Source      = $TestConfig.InstanceCopy1
                    Destination = $TestConfig.InstanceCopy2
                    Login       = "NT AUTHORITY\SYSTEM"
                    Force       = $true
                }
                Copy-DbaLogin @splatCopy -WarningAction SilentlyContinue
            } | Should -Not -Throw
        }

        It "Should verify the safety check logic exists for Windows groups" {
            # This test verifies the safety check added in issue #8572
            # The safety check should skip Windows groups that provide the current user's only access
            # when those groups have high privileges (sysadmin, securityadmin, or ALTER ANY LOGIN)

            # Note: Full automated testing requires:
            # 1. A Windows domain environment with AD groups
            # 2. A test user that accesses SQL only via an AD group (no direct login)
            # 3. The ability to test the actual lockout scenario

            # This test verifies that the protection code exists and is properly structured
            # Manual testing should be performed in a domain environment to verify the protection works

            $testPath = $PSScriptRoot
            if (-not $testPath) {
                $testPath = Split-Path -Path $MyInvocation.MyCommand.Path -Parent
            }
            $moduleRoot = Split-Path -Path $testPath -Parent
            $functionPath = Join-Path -Path $moduleRoot -ChildPath "public\Copy-DbaLogin.ps1"
            $functionContent = Get-Content -Path $functionPath -Raw
            $functionContent | Should -BeLike '*LoginType -eq "WindowsGroup"*'
            $functionContent | Should -BeLike '*potential lockout risk*'
            $functionContent | Should -BeLike '*xp_logininfo*'
        }
    }

}
