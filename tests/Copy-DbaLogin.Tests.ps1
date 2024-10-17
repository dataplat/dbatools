param($ModuleName = 'dbatools')

Describe "Copy-DbaLogin" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        # Helper function
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
        foreach ($instance in $instances) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery
        }

        # create objects
        $null = Invoke-DbaQuery -SqlInstance $global:instance1 -InputFile $global:appveyorlabrepo\sql2008-scripts\logins.sql

        $tableQuery = @("CREATE TABLE tester_table (a int)", "CREATE USER tester FOR LOGIN tester", "GRANT INSERT ON tester_table TO tester;")
        $null = Invoke-DbaQuery -SqlInstance $global:instance1 -Database tempdb -Query ($tableQuery -join '; ')
        $null = Invoke-DbaQuery -SqlInstance $global:instance2 -Database tempdb -Query $tableQuery[0]
    }

    BeforeEach {
        # cleanup targets
        Initialize-TestLogin -Instance $global:instance2 -Login tester
        Initialize-TestLogin -Instance $global:instance1 -Login tester_new
    }

    AfterAll {
        # cleanup everything
        $logins = "claudio", "port", "tester", "tester_new"

        foreach ($instance in $instances) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Copy-DbaLogin
        }
        It "Should have Source parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type DbaInstanceParameter
        }
        It "Should have SourceSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SourceSqlCredential -Type PSCredential
        }
        It "Should have Destination parameter" {
            $CommandUnderTest | Should -HaveParameter Destination -Type DbaInstanceParameter[]
        }
        It "Should have DestinationSqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter DestinationSqlCredential -Type PSCredential
        }
        It "Should have Login parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type Object[]
        }
        It "Should have ExcludeLogin parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeLogin -Type Object[]
        }
        It "Should have ExcludeSystemLogins parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeSystemLogins -Type Switch
        }
        It "Should have SyncSaName parameter" {
            $CommandUnderTest | Should -HaveParameter SyncSaName -Type Switch
        }
        It "Should have OutFile parameter" {
            $CommandUnderTest | Should -HaveParameter OutFile -Type String
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[]
        }
        It "Should have LoginRenameHashtable parameter" {
            $CommandUnderTest | Should -HaveParameter LoginRenameHashtable -Type Hashtable
        }
        It "Should have KillActiveConnection parameter" {
            $CommandUnderTest | Should -HaveParameter KillActiveConnection -Type Switch
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have ExcludePermissionSync parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludePermissionSync -Type Switch
        }
        It "Should have NewSid parameter" {
            $CommandUnderTest | Should -HaveParameter NewSid -Type Switch
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
        It "Should have ObjectLevel parameter" {
            $CommandUnderTest | Should -HaveParameter ObjectLevel -Type Switch
        }
    }

    Context "Copy login with the same properties" {
        It "Should copy successfully" {
            $results = Copy-DbaLogin -Source $global:instance1 -Destination $global:instance2 -Login Tester
            $results.Status | Should -Be "Successful"
            $login1 = Get-DbaLogin -SqlInstance $global:instance1 -login Tester
            $login2 = Get-DbaLogin -SqlInstance $global:instance2 -login Tester

            $login2 | Should -Not -BeNullOrEmpty

            # Compare its value
            $login2.Name | Should -Be $login1.Name
            $login2.Language | Should -Be $login1.Language
            $login2.Credential | Should -Be $login1.Credential
            $login2.DefaultDatabase | Should -Be $login1.DefaultDatabase
            $login2.IsDisabled | Should -Be $login1.IsDisabled
            $login2.IsLocked | Should -Be $login1.IsLocked
            $login2.IsPasswordExpired | Should -Be $login1.IsPasswordExpired
            $login2.PasswordExpirationEnabled | Should -Be $login1.PasswordExpirationEnabled
            $login2.PasswordPolicyEnforced | Should -Be $login1.PasswordPolicyEnforced
            $login2.Sid | Should -Be $login1.Sid
            $login2.Status | Should -Be $login1.Status
        }

        It "Should login with newly created Sql Login (also tests credential login) and gets name" {
            $password = ConvertTo-SecureString -Force -AsPlainText tester1
            $cred = New-Object System.Management.Automation.PSCredential ("tester", $password)
            $s = Connect-DbaInstance -SqlInstance $global:instance1 -SqlCredential $cred
            $s.Name | Should -Be $global:instance1
        }
    }

    Context "No overwrite" {
        BeforeAll {
            $null = Invoke-DbaQuery -SqlInstance $global:instance2 -InputFile $global:appveyorlabrepo\sql2008-scripts\logins.sql
        }
        It "Should say skipped" {
            $results = Copy-DbaLogin -Source $global:instance1 -Destination $global:instance2 -Login tester
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "ExcludeSystemLogins Parameter" {
        It "Should say skipped" {
            $results = Copy-DbaLogin -Source $global:instance1 -Destination $global:instance2 -ExcludeSystemLogins
            $results.Status.Contains('Skipped') | Should -Be $true
            $results.Notes.Contains('System login') | Should -Be $true
        }
    }

    Context "Supports pipe" {
        It "migrates the one tester login" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login tester | Copy-DbaLogin -Destination $global:instance2 -Force
            $results.Name | Should -Be "tester"
            $results.Status | Should -Be "Successful"
        }
    }

    Context "Supports cloning" {
        It "clones the one tester login" {
            $results = Copy-DbaLogin -Source $global:instance1 -Login tester -Destination $global:instance1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $global:instance1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login using pipe" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login tester | Copy-DbaLogin -Destination $global:instance1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $global:instance1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login to a different server with a new name" {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $global:instance2 -Login $_
            }
            $results = Get-DbaLogin -SqlInstance $global:instance1 -Login tester | Copy-DbaLogin -Destination $global:instance2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $login = (Connect-DbaInstance -SqlInstance $global:instance2).Logins['tester_new']
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
                Initialize-TestLogin -Instance $global:instance2 -Login $_
            }
        }
        AfterAll {
            Remove-Item -Path $tempExportFile -Force
        }
        It "clones the one tester login with sysadmin permissions" {
            $results = Copy-DbaLogin -Source $global:instance1 -Login tester -Destination $global:instance2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $global:instance2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $role = $i2.Roles['sysadmin']
            $role.EnumMemberNames() | Should -Contain $results.Name
        }
        It "clones the one tester login with object permissions" {
            $results = Copy-DbaLogin -Source $global:instance1 -Login tester -Destination $global:instance2 -LoginRenameHashtable @{ tester = 'tester_new' } -ObjectLevel
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $global:instance2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $permissions = Export-DbaUser -SqlInstance $global:instance2 -Database tempdb -User tester_new -Passthru
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester_new`]*'
        }
        It "scripts out two tester login with object permissions" {
            $results = Copy-DbaLogin -Source $global:instance1 -Login tester, port -OutFile $tempExportFile -ObjectLevel
            $results | Should -Be $tempExportFile
            $permissions = Get-Content $tempExportFile -Raw
            $permissions | Should -BeLike '*CREATE LOGIN `[tester`]*'
            $permissions | Should -Match "(ALTER SERVER ROLE \[sysadmin\] ADD MEMBER \[tester\]|EXEC sys.sp_addsrvrolemember @rolename=N'sysadmin', @loginame=N'tester')"
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester`]*'
            $permissions | Should -BeLike '*CREATE LOGIN `[port`]*'
            $permissions | Should -BeLike '*GRANT CONNECT SQL TO `[port`]*'
        }
    }
}
