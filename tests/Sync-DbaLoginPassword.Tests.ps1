$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $command = Get-Command $CommandName
        }

        It "Should have the expected parameters" {
            $hasParameters = $command.Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = @(
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

        It "Should have Source as a mandatory parameter" {
            $command.Parameters["Source"].Attributes.Mandatory | Should -Be $true
        }

        It "Should have Destination as a mandatory parameter" {
            $command.Parameters["Destination"].Attributes.Mandatory | Should -Be $true
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $PSDefaultParameterValues["*-Dba*:Confirm"] = $false

        $primaryInstance = $TestConfig.instance2
        $secondaryInstance = $TestConfig.instance3

        $loginName1 = "dbatoolsci_syncpwd1_$(Get-Random)"
        $loginName2 = "dbatoolsci_syncpwd2_$(Get-Random)"
        $password1 = ConvertTo-SecureString -String "Th1sIsMyP@ssw0rd!" -AsPlainText -Force
        $password2 = ConvertTo-SecureString -String "An0therP@ssw0rd!" -AsPlainText -Force

        # Create test logins on both instances
        $splatLogin1Primary = @{
            SqlInstance     = $primaryInstance
            Login           = $loginName1
            SecurePassword  = $password1
        }
        $null = New-DbaLogin @splatLogin1Primary

        $splatLogin1Secondary = @{
            SqlInstance     = $secondaryInstance
            Login           = $loginName1
            SecurePassword  = $password2
        }
        $null = New-DbaLogin @splatLogin1Secondary

        $splatLogin2Primary = @{
            SqlInstance     = $primaryInstance
            Login           = $loginName2
            SecurePassword  = $password1
        }
        $null = New-DbaLogin @splatLogin2Primary

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatRemove = @{
            SqlInstance = $primaryInstance, $secondaryInstance
            Login       = $loginName1, $loginName2
        }
        $null = Remove-DbaLogin @splatRemove

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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
            $splatLogin = @{
                SqlInstance     = $primaryInstance
                Login           = $nonExistentLogin
                SecurePassword  = $password1
            }
            $null = New-DbaLogin @splatLogin

            $splatSync = @{
                Source      = $primaryInstance
                Destination = $secondaryInstance
                Login       = $nonExistentLogin
            }
            $result = Sync-DbaLoginPassword @splatSync -WarningAction SilentlyContinue

            $result | Should -BeNullOrEmpty

            $splatRemoveLogin = @{
                SqlInstance = $primaryInstance
                Login       = $nonExistentLogin
                Confirm     = $false
            }
            $null = Remove-DbaLogin @splatRemoveLogin
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
    }
}
