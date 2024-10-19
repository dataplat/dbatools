param($ModuleName = 'dbatools')

Describe "Get-DbaInstanceAudit" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaInstanceAudit
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Audit as a parameter" {
            $CommandUnderTest | Should -HaveParameter Audit
        }
        It "Should have ExcludeAudit as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeAudit
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command usage" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $sql = "CREATE SERVER AUDIT LoginAudit
                    TO FILE (FILEPATH = N'C:\temp',MAXSIZE = 10 MB,MAX_ROLLOVER_FILES = 1,RESERVE_DISK_SPACE = OFF)
                    WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)

                    CREATE SERVER AUDIT SPECIFICATION TrackAllLogins
                    FOR SERVER AUDIT LoginAudit ADD (SUCCESSFUL_LOGIN_GROUP) WITH (STATE = ON)

                    ALTER SERVER AUDIT LoginAudit WITH (STATE = ON)"
            $server.Query($sql)
        }
        AfterAll {
            $sql = "ALTER SERVER AUDIT SPECIFICATION TrackAllLogins WITH (STATE = OFF)
                    ALTER SERVER AUDIT LoginAudit WITH (STATE = OFF)
                    DROP SERVER AUDIT SPECIFICATION TrackAllLogins
                    DROP SERVER AUDIT LoginAudit"
            $server.Query($sql)
        }
        It "returns some results" {
            $results = Get-DbaInstanceAudit -SqlInstance $global:instance2
            $results | Should -Not -BeNullOrEmpty
        }
        It "returns LoginAudit results" {
            $results = Get-DbaInstanceAudit -SqlInstance $global:instance2 -Audit LoginAudit
            $results.Name | Should -Be 'LoginAudit'
            $results.Enabled | Should -BeTrue
        }
    }
}
