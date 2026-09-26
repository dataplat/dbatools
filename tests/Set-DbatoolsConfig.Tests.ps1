#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbatoolsConfig",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "FullName",
                "Module",
                "Name",
                "Value",
                "PersistedValue",
                "PersistedType",
                "Description",
                "Validation",
                "Handler",
                "Hidden",
                "Default",
                "Initialize",
                "SimpleExport",
                "ModuleExport",
                "DisableValidation",
                "DisableHandler",
                "PassThru",
                "Register",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}
<#
    Integration test are custom to the command you are writing for.
    Read https://github.com/dataplat/dbatools/blob/development/contributing.md#tests
    for more guidence
#>

Describe $CommandName -Tag IntegrationTests {
    Context "When setting configuration values" {
        It "impacts the connection timeout" {
            $null = Set-DbatoolsConfig -FullName sql.connection.timeout -Value 60
            $results = New-DbaConnectionString -SqlInstance test -Database dbatools -ConnectTimeout ([Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout)
            $results | Should -Match "Connect Timeout=60"
        }
    }

    Context "When the module is imported again in another runspace of the process" {
        BeforeAll {
            # The maintenance runspace imports the module a second time a few seconds after Import-Module.
            # That import must not apply the persisted values again, because the configuration is shared by the whole process.
            $configName = "dbatoolsci.test.persisted$(Get-Random)"
            $null = Set-DbatoolsConfig -FullName $configName -Value "persisted"
            Register-DbatoolsConfig -FullName $configName -Scope UserDefault
        }

        AfterAll {
            Unregister-DbatoolsConfig -FullName $configName -Scope UserDefault
        }

        It "keeps the value set in the session" {
            $null = Set-DbatoolsConfig -FullName $configName -Value "session"

            $modulePath = Join-Path -Path ([Dataplat.Dbatools.dbaSystem.SystemHost]::ModuleBase) -ChildPath "dbatools.psm1"
            $powershell = [PowerShell]::Create()
            try {
                $null = $powershell.AddScript("Import-Module `"$modulePath`"").Invoke()
            } finally {
                $powershell.Dispose()
            }

            Get-DbatoolsConfigValue -FullName $configName | Should -Be "session"
        }
    }
}