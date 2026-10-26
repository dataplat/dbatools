#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Sync-DbaLoginPassword",
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
                "InputObject",
                "Login",
                "ExcludeLogin",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should have Source as a mandatory parameter" {
            $command = Get-Command $CommandName
            $command.Parameters["Source"].Attributes.Mandatory | Should -Be $true
        }

        It "Should have Destination as a mandatory parameter" {
            $command = Get-Command $CommandName
            $command.Parameters["Destination"].Attributes.Mandatory | Should -Be $true
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues["*-Dba*:Confirm"] = $false
        $PSDefaultParameterValues["*-Dba*:WarningAction"] = "SilentlyContinue"

        $primaryInstance = $TestConfig.InstanceMulti1
        $secondaryInstance = $TestConfig.InstanceMulti2

        $loginName1 = "dbatoolsci_syncpwd1_$(Get-Random)"
        $loginName2 = "dbatoolsci_syncpwd2_$(Get-Random)"
        $password1 = ConvertTo-SecureString -String "Th1sIsMyP@ssw0rd!" -AsPlainText -Force
        $password2 = ConvertTo-SecureString -String "An0therP@ssw0rd!" -AsPlainText -Force

        # Create test logins on both instances
        $splatLogin1Primary = @{
            SqlInstance    = $primaryInstance
            Login          = $loginName1
            SecurePassword = $password1
            Force          = $true
        }
        $null = New-DbaLogin @splatLogin1Primary

        $splatLogin1Secondary = @{
            SqlInstance    = $secondaryInstance
            Login          = $loginName1
            SecurePassword = $password2
            Force          = $true
        }
        $null = New-DbaLogin @splatLogin1Secondary

        $splatLogin2Primary = @{
            SqlInstance    = $primaryInstance
            Login          = $loginName2
            SecurePassword = $password1
            Force          = $true
        }
        $null = New-DbaLogin @splatLogin2Primary

        $splatLogin2Secondary = @{
            SqlInstance    = $secondaryInstance
            Login          = $loginName2
            SecurePassword = $password2
            Force          = $true
        }
        $null = New-DbaLogin @splatLogin2Secondary

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        $PSDefaultParameterValues.Remove("*-Dba*:WarningAction")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues["*-Dba*:WarningAction"] = "SilentlyContinue"

        $splatRemovePrimary = @{
            SqlInstance = $primaryInstance
            Login       = $loginName1, $loginName2
        }
        $null = Remove-DbaLogin @splatRemovePrimary -ErrorAction SilentlyContinue

        $splatRemoveSecondary = @{
            SqlInstance = $secondaryInstance
            Login       = $loginName1, $loginName2
        }
        $null = Remove-DbaLogin @splatRemoveSecondary -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        $PSDefaultParameterValues.Remove("*-Dba*:WarningAction")
    }

    Context "Sync passwords between instances" {
        It "Should sync password for a single login" {
            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
                Login       = $loginName1
            }
            $result = Sync-DbaLoginPassword @splatSync

            $result | Should -Not -BeNullOrEmpty
            $result.Login | Should -Be $loginName1
            $result.Status | Should -Be "Success"
        }

        It "Should sync passwords for multiple logins" {
            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
                Login       = $loginName1, $loginName2
            }
            $results = Sync-DbaLoginPassword @splatSync

            $results.Status.Count | Should -Be 2
            $results.Status | Should -Not -Contain "Failed"
        }

        It "Should skip logins that do not exist on destination" {
            $nonExistentLogin = "dbatoolsci_nonexistent_$(Get-Random)"

            # Create login on primary
            $splatLogin = @{
                SqlInstance    = $primaryInstance
                Login          = $nonExistentLogin
                SecurePassword = $password1
                Force          = $true
            }
            $null = New-DbaLogin @splatLogin

            # Ensure login does NOT exist on destination (handle AG/replication scenarios)
            $null = Get-DbaLogin -SqlInstance $secondaryInstance -Login $nonExistentLogin | Remove-DbaLogin

            # Try to sync - should skip because login doesn't exist on destination
            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
                Login       = $nonExistentLogin
            }
            $result = Sync-DbaLoginPassword @splatSync -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty

            # Cleanup
            $splatRemoveLogin = @{
                SqlInstance = $primaryInstance
                Login       = $nonExistentLogin
                Confirm     = $false
            }
            $null = Remove-DbaLogin @splatRemoveLogin -ErrorAction SilentlyContinue
        }

        It "Should support pipeline input from Get-DbaLogin" {
            $sourceLogin = Get-DbaLogin -SqlInstance $primaryInstance -Login $loginName1

            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
            }
            $result = $sourceLogin | Sync-DbaLoginPassword @splatSync

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -Be "Success"
        }

        It "Should support pipeline input with multiple logins" {
            $sourceLogins = Get-DbaLogin -SqlInstance $primaryInstance -Login $loginName1, $loginName2

            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
            }
            $results = $sourceLogins | Sync-DbaLoginPassword @splatSync

            $results.Count | Should -Be 2
            $results.Status | Should -Not -Contain "Failed"
            $results.Login | Should -Contain $loginName1
            $results.Login | Should -Contain $loginName2
        }

        It "Should filter out Windows logins when using pipeline input" {
            # Get the first Windows login that exists on the instance
            $splatGetWinLogin = @{
                SqlInstance = $primaryInstance
                Type        = "Windows"
            }
            $windowsLogin = Get-DbaLogin @splatGetWinLogin | Select-Object -First 1

            # Skip test if no Windows logins found on instance
            if (-not $windowsLogin) {
                Set-ItResult -Skipped -Because "No Windows logins found on test instance"
            }

            # Get both SQL and Windows logins
            $sqlLogin = Get-DbaLogin -SqlInstance $primaryInstance -Login $loginName1
            $mixedLogins = @($sqlLogin, $windowsLogin)

            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
            }
            $results = $mixedLogins | Sync-DbaLoginPassword @splatSync

            # Should only process SQL logins, not Windows logins
            $results.SourceServer.Count | Should -Be 1
            $results.Login | Should -Be $loginName1
        }
    }

    Context "Reports a login whose password could not be synced" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $failLoginName = "dbatoolsci_syncpwdfail_$(Get-Random)"
            $failTriggerName = "dbatoolsci_syncpwdfail_trigger_$(Get-Random)"
            $dropTriggerQuery = "IF EXISTS (SELECT * FROM sys.server_triggers WHERE name = N'$failTriggerName') DROP TRIGGER [$failTriggerName] ON ALL SERVER"

            foreach ($instance in $primaryInstance, $secondaryInstance) {
                $splatFailLogin = @{
                    SqlInstance    = $instance
                    Login          = $failLoginName
                    SecurePassword = $password1
                    Force          = $true
                }
                $null = New-DbaLogin @splatFailLogin
            }

            # Refuses every ALTER LOGIN of this login on the destination, so setting the password fails there.
            $createTriggerQuery = @"
CREATE TRIGGER [$failTriggerName] ON ALL SERVER FOR ALTER_LOGIN AS
IF EVENTDATA().value('(/EVENT_INSTANCE/ObjectName)[1]', 'sysname') = N'$failLoginName'
    THROW 50000, N'dbatoolsci: refused by the test trigger', 1;
"@
            $null = Invoke-DbaQuery -SqlInstance $secondaryInstance -Query $createTriggerQuery

            $splatFailSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
                Login       = $failLoginName
            }

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Invoke-DbaQuery -SqlInstance $secondaryInstance -Query $dropTriggerQuery
            $splatRemoveFailLogin = @{
                SqlInstance = $primaryInstance, $secondaryInstance
                Login       = $failLoginName
                ErrorAction = "SilentlyContinue"
            }
            $null = Remove-DbaLogin @splatRemoveFailLogin

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "outputs a row with status Failed and the error" {
            $result = Sync-DbaLoginPassword @splatFailSync -WarningAction SilentlyContinue

            $result.Login | Should -Be $failLoginName
            $result.Status | Should -Be "Failed"
            $result.Notes | Should -BeLike "*refused by the test trigger*"
            # Set-DbaLogin runs with -EnableException and adds its own warning, so the warnings are joined.
            ($WarnVar -join " ") | Should -BeLike "*Failed to sync password for login $failLoginName*"
        }

        It "throws with -EnableException" {
            { Sync-DbaLoginPassword @splatFailSync -EnableException } | Should -Throw
        }
    }
}
