#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Sync-DbaLoginPermission",
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

        $tempguid = [guid]::newguid()
        $DBUserName = "dbatoolssci_$($tempguid.guid)"
        $CreateTestUser = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
USE master;
CREATE USER [$DBUserName] FOR LOGIN [$DBUserName]
    WITH DEFAULT_SCHEMA = dbo;
GRANT VIEW ANY DEFINITION to [$DBUserName];
"@
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query $CreateTestUser -Database master

        # This is used later in the test
        $CreateTestLogin = @"
CREATE LOGIN [$DBUserName]
    WITH PASSWORD = '$($tempguid.guid)';
"@

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $DropTestUser = "DROP LOGIN [$DBUserName]"
        Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Query $DropTestUser -Database master

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Command execution and functionality" {

        It "Should not have the user permissions of $DBUserName" {
            $permissionsBefore = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceMulti2 -Database master | Where-Object { $_.member -eq $DBUserName }
            $permissionsBefore | Should -BeNullOrEmpty
        }

        It "Should execute against active nodes" {
            # Creates the user on
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $CreateTestLogin
            $results = Sync-DbaLoginPermission -Source $TestConfig.InstanceMulti1 -Destination $TestConfig.InstanceMulti2 -Login $DBUserName -ExcludeLogin "NotaLogin" -WarningVariable warn
            $results.Status | Should -Be "Successful"
            $warn | Should -BeNullOrEmpty
        }

        # The copy failes on Appveyor with: Failed to create or use STIG schema on APPVYR-WIN\sql2017
        It "Should have copied the user permissions of $DBUserName" -Skip:$env:appveyor {
            $permissionsAfter = Get-DbaUserPermission -SqlInstance $TestConfig.InstanceMulti2 -Database master | Where-Object { $_.member -eq $DBUserName -and $_.permission -eq "VIEW ANY DEFINITION" }
            $permissionsAfter.member | Should -Be $DBUserName
        }
    }

    Context "Login state synchronization" {
        BeforeAll {
            $tempLoginGuid = [guid]::newguid()
            $stateTestLogin = "dbatoolssci_state_$($tempLoginGuid.guid)"
            $createStateLogin = @"
CREATE LOGIN [$stateTestLogin]
    WITH PASSWORD = '$($tempLoginGuid.guid)';
"@
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1 -Query $createStateLogin
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti2 -Query $createStateLogin

            # Disable and deny connect on source
            $splatDisable = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Query       = "ALTER LOGIN [$stateTestLogin] DISABLE; DENY CONNECT SQL TO [$stateTestLogin];"
            }
            Invoke-DbaQuery @splatDisable
        }
        AfterAll {
            $dropStateLogin = "DROP LOGIN [$stateTestLogin]"
            Invoke-DbaQuery -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Query $dropStateLogin -Database master
        }

        It "Should sync login disabled state from source to destination" {
            $sourceLogin = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti1 -Login $stateTestLogin
            $sourceLogin.IsDisabled | Should -Be $true

            $destLoginBefore = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $stateTestLogin
            $destLoginBefore.IsDisabled | Should -Be $false

            $splatSync = @{
                Source      = $TestConfig.InstanceMulti1
                Destination = $TestConfig.InstanceMulti2
                Login       = $stateTestLogin
            }
            $results = Sync-DbaLoginPermission @splatSync
            $results.Status | Should -Be "Successful"

            $destLoginAfter = Get-DbaLogin -SqlInstance $TestConfig.InstanceMulti2 -Login $stateTestLogin
            $destLoginAfter.IsDisabled | Should -Be $true
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "The connections of the caller are left in the database they were in (#10555)" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $contextDbName = "dbatoolsci_ctx_syncperm_$(Get-Random)"
            $contextLoginName = "dbatoolsci_ctx_login_$(Get-Random)"

            # The login exists on both servers because the sync does not create logins. The database exists
            # on both servers and the login has a user in it on the source, so the permission sync walks the
            # database level collections of both servers - which is the leak this context guards against.
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1 -Name $contextDbName
            $null = New-DbaDatabase -SqlInstance $TestConfig.InstanceMulti2 -Name $contextDbName
            foreach ($contextInstance in $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2) {
                $splatContextLogin = @{
                    SqlInstance = $contextInstance
                    Login       = $contextLoginName
                    Password    = (ConvertTo-SecureString -String "dbatools.IO" -AsPlainText -Force)
                }
                $null = New-DbaLogin @splatContextLogin
            }
            $splatContextUser = @{
                SqlInstance = $TestConfig.InstanceMulti1
                Database    = $contextDbName
                Login       = $contextLoginName
                Username    = $contextLoginName
            }
            $null = New-DbaDbUser @splatContextUser

            # Only a non-pooled connection can show this. A pooled connection that is closed between two
            # calls reconnects at its default database, which puts the database back by accident.
            $sourceCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1 -NonPooledConnection
            $destCallerServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2 -NonPooledConnection
            $sourceContextBefore = $sourceCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")
            $destContextBefore = $destCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            $splatSyncPermission = @{
                Source      = $sourceCallerServer
                Destination = $destCallerServer
                Login       = $contextLoginName
            }
            $contextResult = Sync-DbaLoginPermission @splatSyncPermission

            $sourceContextAfter = $sourceCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")
            $destContextAfter = $destCallerServer.ConnectionContext.ExecuteScalar("SELECT DB_NAME()")

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = $sourceCallerServer | Disconnect-DbaInstance
            $null = $destCallerServer | Disconnect-DbaInstance
            $null = Remove-DbaDatabase -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Database $contextDbName -ErrorAction SilentlyContinue
            $null = Remove-DbaLogin -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -Login $contextLoginName -ErrorAction SilentlyContinue

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "syncs the database user of the login" {
            # Only a command that really did something can move the connections, so without this the
            # assertions below would pass for the wrong reason.
            $contextResult.Status | Should -Be "Successful"
            (Get-DbaDbUser -SqlInstance $TestConfig.InstanceMulti2 -Database $contextDbName).Name | Should -Contain $contextLoginName
        }

        It "leaves the source connection in the database it was in" {
            $sourceContextAfter | Should -Be $sourceContextBefore
        }

        It "leaves the destination connection in the database it was in" {
            $destContextAfter | Should -Be $destContextBefore
        }
    }
}