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
        foreach ($instance in $TestConfig.instance1, $TestConfig.instance2) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery

        }

        # create objects
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql"

        $tableQuery = @("CREATE TABLE tester_table (a int)", "CREATE USER tester FOR LOGIN tester", "GRANT INSERT ON tester_table TO tester;")
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance1 -Database tempdb -Query ($tableQuery -join '; ')
        $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -Database tempdb -Query $tableQuery[0]

        # we want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    BeforeEach {
        # cleanup targets
        Initialize-TestLogin -Instance $TestConfig.instance2 -Login tester
        Initialize-TestLogin -Instance $TestConfig.instance1 -Login tester_new
    }
    AfterAll {
        # we want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # cleanup everything
        $logins = "claudio", "port", "tester", "tester_new"

        foreach ($instance in $TestConfig.instance1, $TestConfig.instance2) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery
        }

        $null = Remove-DbaLogin -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Login 'claudio', 'port', 'tester'

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Copy login with the same properties." {
        It "Should copy successfully" {
            $results = Copy-DbaLogin -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -Login Tester
            $results.Status | Should -Be "Successful"
            $login1 = Get-DbaLogin -SqlInstance $TestConfig.instance1 -login Tester
            $login2 = Get-DbaLogin -SqlInstance $TestConfig.instance2 -login Tester

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
            $s = Connect-DbaInstance -SqlInstance $TestConfig.instance1 -SqlCredential $cred
            $s.Name | Should -Be $TestConfig.instance1
        }
    }

    Context "No overwrite" {
        It "Should say skipped" {
            $null = Invoke-DbaQuery -SqlInstance $TestConfig.instance2 -InputFile "$($TestConfig.appveyorlabrepo)\sql2008-scripts\logins.sql"
            $results = Copy-DbaLogin -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -Login tester
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "ExcludeSystemLogins Parameter" {
        It "Should say skipped" {
            $results = Copy-DbaLogin -Source $TestConfig.instance1 -Destination $TestConfig.instance2 -ExcludeSystemLogins
            $results.Status.Contains('Skipped') | Should -Be $true
            $results.Notes.Contains('System login') | Should -Be $true
        }
    }

    Context "Supports pipe" {
        It "migrates the one tester login" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login tester | Copy-DbaLogin -Destination $TestConfig.instance2 -Force
            $results.Name | Should -Be "tester"
            $results.Status | Should -Be "Successful"
        }
    }

    Context "Supports cloning" {
        It "clones the one tester login" {
            $results = Copy-DbaLogin -Source $TestConfig.instance1 -Login tester -Destination $TestConfig.instance1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login using pipe" {
            $results = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login tester | Copy-DbaLogin -Destination $TestConfig.instance1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login to a different server with a new name" {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $TestConfig.instance2 -Login $_
            }
            $results = Get-DbaLogin -SqlInstance $TestConfig.instance1 -Login tester | Copy-DbaLogin -Destination $TestConfig.instance2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $login = (Connect-DbaInstance -SqlInstance $TestConfig.instance2).Logins['tester_new']
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
                Initialize-TestLogin -Instance $TestConfig.instance2 -Login $_
            }
        }
        AfterAll {
            Remove-Item -Path $tempExportFile -Force
        }
        It "clones the one tester login with sysadmin permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.instance1 -Login tester -Destination $TestConfig.instance2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $role = $i2.Roles['sysadmin']
            $role.EnumMemberNames() | Should -Contain $results.Name
        }
        It "clones the one tester login with object permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.instance1 -Login tester -Destination $TestConfig.instance2 -LoginRenameHashtable @{ tester = 'tester_new' } -ObjectLevel
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $permissions = Export-DbaUser -SqlInstance $TestConfig.instance2 -Database tempdb -User tester_new -Passthru
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester_new`]*'
        }
        It "scripts out two tester login with object permissions" {
            $results = Copy-DbaLogin -Source $TestConfig.instance1 -Login tester, port -OutFile $tempExportFile -ObjectLevel
            $results | Should -Be $tempExportFile
            $permissions = Get-Content $tempExportFile -Raw
            $permissions | Should -BeLike '*CREATE LOGIN `[tester`]*'
            $permissions | Should -Match "(ALTER SERVER ROLE \[sysadmin\] ADD MEMBER \[tester\]|EXEC sp_addsrvrolemember @rolename=N'sysadmin', @loginame=N'tester')"
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester`]*'
            $permissions | Should -BeLike '*CREATE LOGIN `[port`]*'
            $permissions | Should -BeLike '*GRANT CONNECT SQL TO `[port`]*'
        }
    }

    Context "Linux SQL Server protection for BUILTIN\Administrators" {
        BeforeAll {
            $linuxInstance = Connect-DbaInstance -SqlInstance $TestConfig.instance3
            $isLinux = $linuxInstance.HostPlatform -eq "Linux"
        }

        It "Should skip BUILTIN\Administrators on Linux source with -Force" -Skip:(-not $isLinux) {
            $splatCopy = @{
                Source      = $TestConfig.instance3
                Destination = $TestConfig.instance1
                Login       = "BUILTIN\Administrators"
                Force       = $true
            }
            $results = Copy-DbaLogin @splatCopy
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "BUILTIN\Administrators is required on Linux SQL Server"
        }

        It "Should skip BUILTIN\Administrators on Linux destination with -Force" -Skip:(-not $isLinux) {
            $splatCopy = @{
                Source      = $TestConfig.instance1
                Destination = $TestConfig.instance3
                Login       = "BUILTIN\Administrators"
                Force       = $true
            }
            $results = Copy-DbaLogin @splatCopy
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "BUILTIN\Administrators is required on Linux SQL Server"
        }
    }
}