#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAzAccessToken",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Type",
                "Subtype",
                "Config",
                "Credential",
                "Tenant",
                "Thumbprint",
                "Store",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
Describe $CommandName -Tag IntegrationTests {
    # Characterization tests (TA-032): all scenarios run WITHOUT an Azure context and pin
    # the lab-proven offline behaviors of the retired function so the compiled port cannot
    # drift. Nothing here needs a SQL instance or network access.

    Context "Guard rails without Azure context" {
        It "Warns and returns nothing when ServicePrincipal is requested without Credential and Tenant" {
            $results = @(New-DbaAzAccessToken -Type ServicePrincipal -WarningVariable warn -WarningAction SilentlyContinue)
            $results.Count | Should -BeExactly 0
            $warn | Should -Match "You must specify a Credential and Tenant"
        }
    }

    Context "RenewableServicePrincipal token object" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString -String "dbatoolsci_fake" -AsPlainText -Force
            $azCredential = New-Object System.Management.Automation.PSCredential("dbatoolsci_appid", $securePassword)
            $tokenResult = New-DbaAzAccessToken -Type RenewableServicePrincipal -Tenant "dbatoolsci.onmicrosoft.com" -Credential $azCredential
        }

        It "Returns a PsObjectIRenewableToken implementing IRenewableToken" {
            $tokenResult.GetType().Name | Should -Be "PsObjectIRenewableToken"
            ($tokenResult -is [Microsoft.SqlServer.Management.Common.IRenewableToken]) | Should -BeTrue
        }

        It "Captures the service principal identity on the token" {
            $tokenResult.UserId | Should -Be "dbatoolsci_appid"
            $tokenResult.Tenant | Should -Be "dbatoolsci.onmicrosoft.com"
            $tokenResult.Resource | Should -Be "https://database.windows.net/"
            $tokenResult.ClientSecret | Should -Be "dbatoolsci_fake"
        }

        It "Initializes TokenExpiry to the DateTimeOffset minimum" {
            $tokenResult.TokenExpiry | Should -Be ([System.DateTimeOffset]::MinValue)
        }
    }

    Context "Process failures warn as Failure and continue the caller" {
        It "Warns Failure with the null-method text when only Tenant is supplied" {
            # Stop-Function -Continue crosses the function boundary, so the call rides
            # inside a loop that absorbs the caller-level continue.
            $warn = @()
            foreach ($iteration in 1..1) {
                $null = New-DbaAzAccessToken -Type RenewableServicePrincipal -Tenant "dbatoolsci.onmicrosoft.com" -WarningVariable warn -WarningAction SilentlyContinue
            }
            $warn | Should -Match "Failure"
            $warn | Should -Match "You cannot call a method on a null-valued expression"
        }
    }
}

<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>