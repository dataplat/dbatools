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
                "MailServer",
                "NewMailServerName",
                "DisplayName",
                "Description",
                "EmailAddress",
                "ReplyToAddress",
                "Port",
                "EnableSSL",
                "UseDefaultCredentials",
                "UserName",
                "Password",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $accountName = "dbatoolsci_test_$(Get-Random)"
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $email_address = "dbatoolssci@dbatools.net"
        $display_name = "dbatoolsci mail alerts"
        $mailserver_name = "smtp.dbatools.io"

        if ( (Get-DbaSpConfigure -SqlInstance $server -Name "Database Mail XPs").RunningValue -ne 1 ) {
            Set-DbaSpConfigure -SqlInstance $server -Name "Database Mail XPs" -Value 1
        }

        $splatMailAccount = @{
            SqlInstance  = $TestConfig.instance2
            Account      = $accountName
            EmailAddress = $email_address
            DisplayName  = $display_name
            MailServer   = $mailserver_name
        }
        $null = New-DbaDbMailAccount @splatMailAccount

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $cleanupServer = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $mailAccountSettings = "EXEC msdb.dbo.sysmail_delete_account_sp @account_name = '$accountName';"
        $cleanupServer.Query($mailAccountSettings)

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Updates mail account properties" {
        BeforeAll {
            $splatUpdateAccount = @{
                SqlInstance  = $TestConfig.instance2
                Account      = $accountName
                DisplayName  = "Updated Display Name"
                Description  = "Updated Description"
            }
            $results = Set-DbaDbMailAccount @splatUpdateAccount
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have updated DisplayName" {
            $results.DisplayName | Should -Be "Updated Display Name"
        }

        It "Should have updated Description" {
            $results.Description | Should -Be "Updated Description"
        }
    }

    Context "Updates mail server port and SSL settings" {
        BeforeAll {
            $splatUpdateServer = @{
                SqlInstance = $TestConfig.instance2
                Account     = $accountName
                Port        = 587
                EnableSSL   = $true
            }
            $results = Set-DbaDbMailAccount @splatUpdateServer
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have updated port to 587" {
            $mailServer = Get-DbaDbMailServer -SqlInstance $TestConfig.instance2 -Account $accountName
            $mailServer.Port | Should -Be 587
        }

        It "Should have enabled SSL" {
            $mailServer = Get-DbaDbMailServer -SqlInstance $TestConfig.instance2 -Account $accountName
            $mailServer.EnableSSL | Should -Be $true
        }
    }

    Context "Works with pipeline input" {
        BeforeAll {
            $results = Get-DbaDbMailAccount -SqlInstance $TestConfig.instance2 -Account $accountName | Set-DbaDbMailAccount -Port 25 -EnableSSL:$false
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have updated port back to 25" {
            $mailServer = Get-DbaDbMailServer -SqlInstance $TestConfig.instance2 -Account $accountName
            $mailServer.Port | Should -Be 25
        }

        It "Should have disabled SSL" {
            $mailServer = Get-DbaDbMailServer -SqlInstance $TestConfig.instance2 -Account $accountName
            $mailServer.EnableSSL | Should -Be $false
        }
    }
}
