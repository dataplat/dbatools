#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMail",
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

        # Set variables. They are available in all the It blocks.
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $mailSettings = @{
            AccountRetryAttempts           = "1"
            AccountRetryDelay              = "60"
            DatabaseMailExeMinimumLifeTime = "600"
            DefaultAttachmentEncoding      = "MIME"
            LoggingLevel                   = "2"
            MaxFileSize                    = "1000"
            ProhibitedExtensions           = "exe,dll,vbs,js"
        }
        foreach ($m in $mailSettings.GetEnumerator()) {
            $server.query("exec msdb.dbo.sysmail_configure_sp '$($m.key)','$($m.value)';")
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets DbMail Settings" {
        BeforeAll {
            $results = Get-DbaDbMail -SqlInstance $TestConfig.InstanceSingle
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have the expected mail settings" {
            foreach ($row in $results.ConfigurationValues) {
                $row.name | Should -BeIn $mailSettings.Keys
                $row.value | Should -BeIn $mailSettings.Values
            }
        }
    }
}