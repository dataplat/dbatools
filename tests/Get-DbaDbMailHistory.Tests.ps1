$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Since', 'Status', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
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
    }
    AfterAll {
        $server.Query("DELETE FROM msdb.dbo.sysmail_profile WHERE profile_id = '$profile_id'")
        $server.Query("DELETE FROM msdb.dbo.sysmail_mailitems WHERE profile_id = '$profile_id'")
    }

    Context "Gets Db Mail History" {
        $results = Get-DbaDbMailHistory -SqlInstance $script:instance2 | Where-Object {$_.Subject -eq 'Test Job'}
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have created subject" {
            $results.subject | Should be 'Test Job'
        }
        It "Should have recipient of dbatoolssci@dbatools.io" {
            $results.recipients | Should be 'dbatoolssci@dbatools.io'
        }
    }
    Context "Gets Db Mail History using -Status" {
        $results = Get-DbaDbMailHistory -SqlInstance $script:instance2 -Status Sent
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have a Normal Importance" {
            $results.Importance | Should be 'Normal'
        }
        It "Should have a Normal Sensitivity" {
            $results.sensitivity | Should be 'Normal'
        }
        It "Should have SentStatus of Sent" {
            $results.SentStatus | Should be 'Sent'
        }
    }
    Context "Gets Db Mail History using -Since" {
        $results = Get-DbaDbMailHistory -SqlInstance $script:instance2 -Since '2018-01-01'
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have a SentDate greater than 2018-01-01" {
            $results.SentDate | Should Begreaterthan '2018-01-01'
        }
        It "Should have a SendRequestDate greater than 2018-01-01" {
            $results.SendRequestDate | Should Begreaterthan '2018-01-01'
        }
    }
}