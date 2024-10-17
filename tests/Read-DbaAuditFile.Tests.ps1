param($ModuleName = 'dbatools')

Describe "Read-DbaAuditFile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Read-DbaAuditFile
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type Object[] -Mandatory:$false
        }
        It "Should have Raw as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Raw -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $path = $server.ErrorLogPath
            $sql = @"
CREATE SERVER AUDIT LoginAudit
TO FILE (FILEPATH = N'$path',MAXSIZE = 10 MB,MAX_ROLLOVER_FILES = 1,RESERVE_DISK_SPACE = OFF)
WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)

CREATE SERVER AUDIT SPECIFICATION TrackAllLogins
FOR SERVER AUDIT LoginAudit ADD (SUCCESSFUL_LOGIN_GROUP) WITH (STATE = ON)

ALTER SERVER AUDIT LoginAudit WITH (STATE = ON)
"@
            $server.Query($sql)
            # generate a login
            $null = Get-DbaDatabase -SqlInstance $global:instance2
            $null = Get-DbaDbFile -SqlInstance $global:instance2
            # Give it a chance to write
            Start-Sleep 2
        }

        AfterAll {
            $sql = @"
ALTER SERVER AUDIT SPECIFICATION TrackAllLogins WITH (STATE = OFF)
ALTER SERVER AUDIT LoginAudit WITH (STATE = OFF)
DROP SERVER AUDIT SPECIFICATION TrackAllLogins
DROP SERVER AUDIT LoginAudit
"@
            $server.Query($sql)
        }

        It "returns some results when using -Raw parameter" {
            $results = Get-DbaInstanceAudit -SqlInstance $global:instance2 -Audit LoginAudit | Read-DbaAuditFile -Raw -WarningAction SilentlyContinue
            $results.Count | Should -BeGreaterThan 1
        }

        It "returns results with server_principal_name" {
            $results = Get-DbaInstanceAudit -SqlInstance $global:instance2 -Audit LoginAudit | Read-DbaAuditFile | Select-Object -First 1
            $results.server_principal_name | Should -Not -BeNullOrEmpty
        }
    }
}
