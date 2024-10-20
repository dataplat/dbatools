param($ModuleName = 'dbatools')

Describe "Get-DbaDbMailLog" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMailLog
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Since",
            "Type",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            # Run setup code to get script variables within scope of the discovery phase
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
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
        }

        AfterAll {
            $server.Query("DELETE FROM msdb.[dbo].[sysmail_log] WHERE last_mod_user = 'dbatools\dbatoolssci'")
        }

        Context "Gets Db Mail Log" {
            BeforeAll {
                $results = Get-DbaDbMailLog -SqlInstance $global:instance2 | Where-Object {$_.Login -eq 'dbatools\dbatoolssci'}
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have created Description" {
                $results.description | Should -Be 'DatabaseMail process is started'
            }

            It "Should have last modified user of dbatools\dbatoolssci" {
                $results.lastmoduser | Should -Be 'dbatools\dbatoolssci'
            }
        }

        Context "Gets Db Mail Log using -Type" {
            BeforeAll {
                $results = Get-DbaDbMailLog -SqlInstance $global:instance2 -Type Information
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have Log Id" {
                $results.logid | Should -Not -BeNullOrEmpty
            }

            It "Should have an Event Type of Information" {
                $results.eventtype | Should -Be 'Information'
            }
        }

        Context "Gets Db Mail History using -Since" {
            BeforeAll {
                $results = Get-DbaDbMailLog -SqlInstance $global:instance2 -Since '2018-01-01'
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have a LogDate greater than 2018-01-01" {
                $results.LogDate | Should -BeGreaterThan '2018-01-01'
            }

            It "Should have a LastModDate greater than 2018-01-01" {
                $results.LastModDate | Should -BeGreaterThan '2018-01-01'
            }
        }
    }
}
