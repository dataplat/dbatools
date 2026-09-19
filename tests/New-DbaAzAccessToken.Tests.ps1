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
<#
    Integration test should appear below and are custom to the command you are writing.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence.
#>
Describe $CommandName -Tag IntegrationTests {
    Context "When the service principal cannot be authenticated" {
        BeforeAll {
            $badPassword = ConvertTo-SecureString -String "dbatoolsci" -AsPlainText -Force
            $badCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList "dbatoolsci", $badPassword
        }

        # The ServicePrincipal path is the one that reaches the catch: it refuses to run on Core before any
        # request is made, so the test runs on Windows PowerShell only, which is what CI runs anyway.
        It "Warns without eating an iteration of the caller's loop" -Skip:($PSVersionTable.PSEdition -eq "Core") {
            # The catch used to run Stop-Function -Continue at the end of the process block, where no loop
            # encloses it - the continue escaped the command and consumed an iteration of this very loop, so
            # the counter stayed at zero (#10638). A tenant that does not exist makes the token request fail.
            $loopCount = 0
            foreach ($i in 1..3) {
                $splatBadTenant = @{
                    Type          = "ServicePrincipal"
                    Tenant        = "dbatoolsci.invalid"
                    Credential    = $badCredential
                    WarningAction = "SilentlyContinue"
                }
                $null = New-DbaAzAccessToken @splatBadTenant
                $loopCount++
            }
            $loopCount | Should -Be 3
            ($WarnVar -join " ") | Should -BeLike "*Failure*"
        }
    }
}
