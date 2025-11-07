#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Sync-DbaLoginSid",
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

        $primaryInstance = $TestConfig.instance2
        $secondaryInstance = $TestConfig.instance3

        $loginName1 = "dbatoolsci_syncsid1_$(Get-Random)"
        $loginName2 = "dbatoolsci_syncsid2_$(Get-Random)"
        $password = ConvertTo-SecureString -String "Th1sIsMyP@ssw0rd!" -AsPlainText -Force

        # Create test logins on primary instance
        $splatLogin1Primary = @{
            SqlInstance    = $primaryInstance
            Login          = $loginName1
            SecurePassword = $password
            Force          = $true
        }
        $primaryLogin1 = New-DbaLogin @splatLogin1Primary

        $splatLogin2Primary = @{
            SqlInstance    = $primaryInstance
            Login          = $loginName2
            SecurePassword = $password
            Force          = $true
        }
        $primaryLogin2 = New-DbaLogin @splatLogin2Primary

        # Create same logins on secondary instance with different passwords to ensure different SIDs
        $password2 = ConvertTo-SecureString -String "D1fferentP@ssw0rd!" -AsPlainText -Force

        $splatLogin1Secondary = @{
            SqlInstance    = $secondaryInstance
            Login          = $loginName1
            SecurePassword = $password2
            Force          = $true
        }
        $secondaryLogin1 = New-DbaLogin @splatLogin1Secondary

        $splatLogin2Secondary = @{
            SqlInstance    = $secondaryInstance
            Login          = $loginName2
            SecurePassword = $password2
            Force          = $true
        }
        $secondaryLogin2 = New-DbaLogin @splatLogin2Secondary

        # Verify SIDs are different before sync
        $primarySid1 = (Get-DbaLogin -SqlInstance $primaryInstance -Login $loginName1).Sid
        $secondarySid1 = (Get-DbaLogin -SqlInstance $secondaryInstance -Login $loginName1).Sid
        $global:sidsAreDifferent = ([System.BitConverter]::ToString($primarySid1) -ne [System.BitConverter]::ToString($secondarySid1))

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

    Context "Sync SIDs between instances" {
        It "Should sync SID for a single login" {
            # Skip if SIDs somehow ended up the same during setup
            if (-not $global:sidsAreDifferent) {
                Set-ItResult -Skipped -Because "Test logins have matching SIDs, cannot test sync"
            }

            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
                Login       = $loginName1
            }
            $result = Sync-DbaLoginSid @splatSync

            $result | Should -Not -BeNullOrEmpty
            $result.Login | Should -Be $loginName1
            $result.Status | Should -BeIn "Success", "AlreadyMatched"

            # Verify SID was actually synced
            $primarySid = (Get-DbaLogin -SqlInstance $primaryInstance -Login $loginName1).Sid
            $secondarySid = (Get-DbaLogin -SqlInstance $secondaryInstance -Login $loginName1).Sid
            [System.BitConverter]::ToString($primarySid) | Should -Be ([System.BitConverter]::ToString($secondarySid))
        }

        It "Should sync SIDs for multiple logins" {
            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
                Login       = $loginName1, $loginName2
            }
            $results = Sync-DbaLoginSid @splatSync

            $results.Status.Count | Should -BeGreaterThan 0
            $results.Status | Should -Not -Contain "Failed"
        }

        It "Should skip logins that do not exist on destination" {
            $nonExistentLogin = "dbatoolsci_nonexistent_$(Get-Random)"

            # Create login on primary only
            $splatLogin = @{
                SqlInstance    = $primaryInstance
                Login          = $nonExistentLogin
                SecurePassword = $password
                Force          = $true
            }
            $null = New-DbaLogin @splatLogin

            # Ensure login does NOT exist on destination
            $null = Remove-DbaLogin -SqlInstance $secondaryInstance -Login $nonExistentLogin -Confirm:$false -ErrorAction SilentlyContinue

            # Try to sync - should skip because login doesn't exist on destination
            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
                Login       = $nonExistentLogin
            }
            $result = Sync-DbaLoginSid @splatSync -WarningAction SilentlyContinue

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
            $sourceLogin = Get-DbaLogin -SqlInstance $primaryInstance -Login $loginName2

            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
            }
            $result = $sourceLogin | Sync-DbaLoginSid @splatSync

            $result | Should -Not -BeNullOrEmpty
            $result.Status | Should -BeIn "Success", "AlreadyMatched"
        }

        It "Should support pipeline input with multiple logins" {
            # Recreate logins with different SIDs for this test
            $password3 = ConvertTo-SecureString -String "An0th3rP@ssw0rd!" -AsPlainText -Force

            $splatRecreate = @{
                SqlInstance    = $secondaryInstance
                Login          = $loginName1, $loginName2
                SecurePassword = $password3
                Force          = $true
            }
            $null = New-DbaLogin @splatRecreate

            $sourceLogins = Get-DbaLogin -SqlInstance $primaryInstance -Login $loginName1, $loginName2

            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
            }
            $results = $sourceLogins | Sync-DbaLoginSid @splatSync

            $results.Status.Count | Should -BeGreaterThan 0
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
            $results = $mixedLogins | Sync-DbaLoginSid @splatSync

            # Should only process SQL logins, not Windows logins
            $results.Login | Should -Not -Contain $windowsLogin.Name
            $results.Login | Should -Contain $loginName1
        }

        It "Should skip logins that already have matching SIDs" {
            # First sync to ensure SIDs match
            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
                Login       = $loginName1
            }
            $null = Sync-DbaLoginSid @splatSync

            # Try syncing again - should report already matched
            $result = Sync-DbaLoginSid @splatSync

            $result.Status | Should -Be "AlreadyMatched"
            $result.Notes | Should -Be "SIDs already match"
        }
    }
}
