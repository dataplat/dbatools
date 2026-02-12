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

        Context "Output validation" {
            It "Returns output of the documented type" {
                $result | Should -Not -BeNullOrEmpty
                $result | Should -BeOfType PSCustomObject
            }

            It "Has the expected properties" {
                $expectedProperties = @("SourceServer", "DestinationServer", "Login", "Status", "Notes")
                foreach ($prop in $expectedProperties) {
                    $result.PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
                }
            }

            It "Has SourceServer populated" {
                $result.SourceServer | Should -Not -BeNullOrEmpty
            }

            It "Has DestinationServer populated" {
                $result.DestinationServer | Should -Not -BeNullOrEmpty
            }

            It "Has Login populated" {
                $result.Login | Should -Be $loginName1
            }

            It "Has a valid Status value" {
                $result.Status | Should -BeIn @("Success", "Failed")
            }
        }
    }
}
