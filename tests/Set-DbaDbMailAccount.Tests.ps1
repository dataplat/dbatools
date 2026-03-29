#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbMailAccount",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Account",
                "InputObject",
                "DisplayName",
                "Description",
                "EmailAddress",
                "ReplyToAddress",
                "NewMailServerName",
                "Port",
                "EnableSSL",
                "UseDefaultCredentials",
                "UserName",
                "Password",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $accountName = "dbatoolsci_settest_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        if ((Get-DbaSpConfigure -SqlInstance $server -Name "Database Mail XPs").RunningValue -ne 1) {
            Set-DbaSpConfigure -SqlInstance $server -Name "Database Mail XPs" -Value 1
        }

        $splatMailAccount = @{
            SqlInstance  = $TestConfig.InstanceSingle
            Account      = $accountName
            Description  = "Original description"
            EmailAddress = "original@dbatools.net"
            DisplayName  = "Original Display Name"
        }
        $null = New-DbaDbMailAccount @splatMailAccount

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountName';"
        $server.query($mailAccountSettings)
    }

    Context "Updates mail account properties" {
        BeforeAll {
            $splatSetAccount = @{
                SqlInstance = $TestConfig.InstanceSingle
                Account     = $accountName
                Description = "Updated description"
                DisplayName = "Updated Display Name"
            }
            $results = Set-DbaDbMailAccount @splatSetAccount
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have updated Description" {
            $results.Description | Should -Be "Updated description"
        }
        It "Should have updated DisplayName" {
            $results.DisplayName | Should -Be "Updated Display Name"
        }
    }

    Context "Updates mail server port and SSL settings" {
        BeforeAll {
            $splatSetServer = @{
                SqlInstance = $TestConfig.InstanceSingle
                Account     = $accountName
                Port        = 587
                EnableSSL   = $true
            }
            $results = Set-DbaDbMailAccount @splatSetServer
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have updated port to 587" {
            $mailServer = $results.MailServers | Select-Object -First 1
            $mailServer.Port | Should -Be 587
        }
        It "Should have enabled SSL" {
            $mailServer = $results.MailServers | Select-Object -First 1
            $mailServer.EnableSsl | Should -Be $true
        }
    }

    Context "Works with pipeline input" {
        BeforeAll {
            $results = Get-DbaDbMailAccount -SqlInstance $TestConfig.InstanceSingle -Account $accountName | Set-DbaDbMailAccount -Port 25 -EnableSSL:$false
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have updated port back to 25" {
            $mailServer = $results.MailServers | Select-Object -First 1
            $mailServer.Port | Should -Be 25
        }
        It "Should have disabled SSL" {
            $mailServer = $results.MailServers | Select-Object -First 1
            $mailServer.EnableSsl | Should -Be $false
        }
    }
}
