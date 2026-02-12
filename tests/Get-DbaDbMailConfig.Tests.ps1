#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMailConfig",
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
                "Name",
                "InputObject",
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

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # No specific cleanup needed for DbMail config tests

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets DbMail Settings" {
        BeforeAll {
            $results = Get-DbaDbMailConfig -SqlInstance $TestConfig.InstanceSingle
            $mailSettings = @{
                AccountRetryAttempts           = "1"
                AccountRetryDelay              = "60"
                DatabaseMailExeMinimumLifeTime = "600"
                DefaultAttachmentEncoding      = "MIME"
                LoggingLevel                   = "2"
                MaxFileSize                    = "1000"
                ProhibitedExtensions           = "exe,dll,vbs,js"
            }
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have all configured settings" {
            foreach ($row in $results) {
                $row.name | Should -BeIn $mailSettings.keys
                $row.value | Should -BeIn $mailSettings.values
            }
        }

        It "Returns output of the documented type" {
            $results[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.Mail.ConfigurationValue"
        }

        It "Has the expected default display properties" {
            $defaultProps = $results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Name", "Value", "Description")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }

    Context "Gets DbMail Settings when using -Name" {
        BeforeAll {
            $results = Get-DbaDbMailConfig -SqlInstance $TestConfig.InstanceSingle -Name "ProhibitedExtensions"
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Name 'ProhibitedExtensions'" {
            $results.name | Should -BeExactly "ProhibitedExtensions"
        }

        It "Should have Value 'exe,dll,vbs,js'" {
            $results.value | Should -BeExactly "exe,dll,vbs,js"
        }

        It "Should have Description 'Extensions not allowed in outgoing mails'" {
            $results.description | Should -BeExactly "Extensions not allowed in outgoing mails"
        }
    }

}