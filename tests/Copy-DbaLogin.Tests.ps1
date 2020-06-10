$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Login', 'ExcludeLogin', 'ExcludeSystemLogins', 'SyncSaName', 'OutFile', 'InputObject', 'LoginRenameHashtable', 'KillActiveConnection', 'Force', 'ExcludePermissionSync', 'NewSid', 'EnableException', 'ObjectLevel'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params | Write-Host
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
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
        foreach ($instance in $instances) {
            foreach ($login in $logins) {
                Initialize-TestLogin -Instance $instance -Login $login
            }
            $null = Invoke-DbaQuery -SqlInstance $instance -Database tempdb -Query $dropTableQuery

        }

        # create objects
        $null = Invoke-DbaQuery -SqlInstance $script:instance1 -InputFile $script:appveyorlabrepo\sql2008-scripts\logins.sql

        $tableQuery = @("CREATE TABLE tester_table (a int)", "CREATE USER tester FOR LOGIN tester", "GRANT INSERT ON tester_table TO tester;")
        $null = Invoke-DbaQuery -SqlInstance $script:instance1 -Database tempdb -Query ($tableQuery -join '; ')
        $null = Invoke-DbaQuery -SqlInstance $script:instance2 -Database tempdb -Query $tableQuery[0]

    }
    BeforeEach {
        # cleanup targets
        Initialize-TestLogin -Instance $script:instance2 -Login tester
        Initialize-TestLogin -Instance $script:instance1 -Login tester_new
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

    Context "Copy login with the same properties." {
        It "Should copy successfully" {
            $results = Copy-DbaLogin -Source $script:instance1 -Destination $script:instance2 -Login Tester
            $results.Status | Should -Be "Successful"
            $login1 = Get-Dbalogin -SqlInstance $script:instance1 -login Tester
            $login2 = Get-Dbalogin -SqlInstance $script:instance2 -login Tester

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
            $s = Connect-DbaInstance -SqlInstance $script:instance1 -SqlCredential $cred
            $s.Name | Should -Be $script:instance1
        }
    }

    Context "No overwrite" {
        BeforeAll {
            $null = Invoke-DbaQuery -SqlInstance $script:instance2 -InputFile $script:appveyorlabrepo\sql2008-scripts\logins.sql
        }
        $results = Copy-DbaLogin -Source $script:instance1 -Destination $script:instance2 -Login tester
        It "Should say skipped" {
            $results.Status | Should -Be "Skipped"
            $results.Notes | Should -Be "Already exists on destination"
        }
    }

    Context "ExcludeSystemLogins Parameter" {
        $results = Copy-DbaLogin -Source $script:instance1 -Destination $script:instance2 -ExcludeSystemLogins
        It "Should say skipped" {
            $results.Status.Contains('Skipped') | Should -Be $true
            $results.Notes.Contains('System login') | Should -Be $true
        }
    }

    Context "Supports pipe" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login tester | Copy-DbaLogin -Destination $script:instance2 -Force
        It "migrates the one tester login" {
            $results.Name | Should -Be "tester"
            $results.Status | Should -Be "Successful"
        }
    }

    Context "Supports cloning" {
        It "clones the one tester login" {
            $results = Copy-DbaLogin -Source $script:instance1 -Login tester -Destination $script:instance1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $script:instance1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login using pipe" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 -Login tester | Copy-DbaLogin -Destination $script:instance1 -Force -LoginRenameHashtable @{ tester = 'tester_new' } -NewSid
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            Get-DbaLogin -SqlInstance $script:instance1 -Login tester_new | Should -Not -BeNullOrEmpty
        }
        It "clones the one tester login to a different server with a new name" {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $script:instance2 -Login $_
            }
            $results = Get-DbaLogin -SqlInstance $script:instance1 -Login tester | Copy-DbaLogin -Destination $script:instance2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $login = (Connect-DbaInstance -SqlInstance $script:instance2).Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $login | Remove-DbaLogin -Force
        }
    }

    Context "Supports db object permissions" {
        BeforeEach {
            'tester', 'tester_new' | ForEach-Object {
                Initialize-TestLogin -Instance $script:instance2 -Login $_
            }
        }
        It "clones the one tester login with sysadmin permissions" {
            $results = Copy-DbaLogin -Source $script:instance1 -Login tester -Destination $script:instance2 -LoginRenameHashtable @{ tester = 'tester_new' }
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $script:instance2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $role = $i2.Roles['sysadmin']
            $role.EnumMemberNames() | Should -Contain $results.Name
        }
        It "clones the one tester login with object permissions" {
            $results = Copy-DbaLogin -Source $script:instance1 -Login tester -Destination $script:instance2 -LoginRenameHashtable @{ tester = 'tester_new' } -ObjectLevel
            $results.Name | Should -Be "tester_new"
            $results.Status | Should -Be "Successful"
            $i2 = Connect-DbaInstance -SqlInstance $script:instance2
            $login = $i2.Logins['tester_new']
            $login | Should -Not -BeNullOrEmpty
            $permissions = Export-DbaUser -SqlInstance $script:instance2 -Database tempdb -User tester_new -Passthru
            $permissions | Should -BeLike '*GRANT INSERT ON OBJECT::`[dbo`].`[tester_table`] TO `[tester_new`]*'
        }
    }
}