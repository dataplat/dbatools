#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMailLog",
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
                "Since",
                "Type",
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
        $server.Query("INSERT INTO msdb.[dbo].[sysmail_log]
        ([event_type]
        ,[log_date]
        ,[description]
        ,[process_id]
        ,[mailitem_id]
        ,[account_id]
        ,[last_mod_date]
        ,[last_mod_user])
        VALUES
        (1,'2018-12-09 12:18:14.920','DatabaseMail process is started',4890,NULL,NULL,'2018-12-09 12:18:14.920','dbatools\dbatoolssci')")

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $server.Query("DELETE FROM msdb.[dbo].[sysmail_log] WHERE last_mod_user = 'dbatools\dbatoolssci'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets Db Mail Log" {
        BeforeAll {
            $results = Get-DbaDbMailLog -SqlInstance $TestConfig.InstanceSingle | Where-Object Login -eq "dbatools\dbatoolssci"
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have created Description" {
            $results.description | Should -Be "DatabaseMail process is started"
        }

        It "Should have last modified user of dbatools\dbatoolssci " {
            $results.lastmoduser | Should -Be "dbatools\dbatoolssci"
        }

        It "Returns output of the documented type" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Has the expected default display properties" {
            if (-not $results) { Set-ItResult -Skipped -Because "no result to validate" }
            $defaultProps = $results.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "LogDate",
                "EventType",
                "Description",
                "Login"
            )
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }

    Context "Gets Db Mail Log using -Type" {
        BeforeAll {
            $results = Get-DbaDbMailLog -SqlInstance $TestConfig.InstanceSingle -Type Information
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have Log Id" {
            $results.logid | Should -Not -BeNullOrEmpty
        }

        It "Should have an Event Type of Information" {
            $results.eventtype | Should -Be "Information"
        }
    }

    Context "Gets Db Mail History using -Since" {
        BeforeAll {
            $results = Get-DbaDbMailLog -SqlInstance $TestConfig.InstanceSingle -Since "2018-01-01"
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a LogDate greater than 2018-01-01" {
            $results.LogDate | Should -BeGreaterThan "2018-01-01"
        }

        It "Should have a LastModDate greater than 2018-01-01" {
            $results.LastModDate | Should -BeGreaterThan "2018-01-01"
        }
    }
}