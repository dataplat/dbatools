#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaDbMailHistory",
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
                "Status",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $server.Query("INSERT INTO msdb.[dbo].[sysmail_profile]
           ([name]
           ,[description]
           ,[last_mod_datetime]
           ,[last_mod_user])
        VALUES
           ('DbaToolsMail','Used to send Database Alerts and Notifications'
           ,'2018-12-9 08:00:32.700'
           ,'sa')")
        $profile_id = $($server.Query("SELECT profile_id FROM msdb.[dbo].[sysmail_profile] WHERE name = 'DbaToolsMail'")).profile_id
        $server.Query("INSERT INTO msdb.[dbo].[sysmail_mailitems]
           ([profile_id]
           ,[recipients]
           ,[copy_recipients]
           ,[blind_copy_recipients]
           ,[subject]
           ,[from_address]
           ,[reply_to]
           ,[body]
           ,[body_format]
           ,[importance]
           ,[sensitivity]
           ,[file_attachments]
           ,[attachment_encoding]
           ,[query]
           ,[execute_query_database]
           ,[attach_query_result_as_file]
           ,[query_result_header]
           ,[query_result_width]
           ,[query_result_separator]
           ,[exclude_query_output]
           ,[append_query_error]
           ,[send_request_date]
           ,[send_request_user]
           ,[sent_account_id]
           ,[sent_status]
           ,[sent_date]
           ,[last_mod_date]
           ,[last_mod_user])
        VALUES
           ($profile_id,'dbatoolssci@dbatools.io',NULL,NULL,'Test Job',NULL,NULL,'A Test Job failed to run','TEXT','Normal','Normal',NULL,'MIME',NULL,NULL,
          0,1,256,'',0,0,'2018-12-9 11:44:32.600','dbatools\dbatoolssci',1,1,'2018-12-9 11:44:33.000','2018-12-9 11:44:33.273','sa')"
        )

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server.Query("DELETE FROM msdb.dbo.sysmail_profile WHERE profile_id = '$profile_id'")
        $server.Query("DELETE FROM msdb.dbo.sysmail_mailitems WHERE profile_id = '$profile_id'")

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Gets Db Mail History" {
        BeforeAll {
            $results = Get-DbaDbMailHistory -SqlInstance $TestConfig.instance2 | Where-Object { $PSItem.Subject -eq "Test Job" }
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have created subject" {
            $results.subject | Should -Be "Test Job"
        }

        It "Should have recipient of dbatoolssci@dbatools.io" {
            $results.recipients | Should -Be "dbatoolssci@dbatools.io"
        }
    }

    Context "Gets Db Mail History using -Status" {
        BeforeAll {
            $results = Get-DbaDbMailHistory -SqlInstance $TestConfig.instance2 -Status Sent
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a Normal Importance" {
            $results.Importance | Should -Be "Normal"
        }

        It "Should have a Normal Sensitivity" {
            $results.sensitivity | Should -Be "Normal"
        }

        It "Should have SentStatus of Sent" {
            $results.SentStatus | Should -Be "Sent"
        }
    }

    Context "Gets Db Mail History using -Since" {
        BeforeAll {
            $results = Get-DbaDbMailHistory -SqlInstance $TestConfig.instance2 -Since "2018-01-01"
        }

        It "Gets results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have a SentDate greater than 2018-01-01" {
            $results.SentDate | Should -BeGreaterThan "2018-01-01"
        }

        It "Should have a SendRequestDate greater than 2018-01-01" {
            $results.SendRequestDate | Should -BeGreaterThan "2018-01-01"
        }
    }
}