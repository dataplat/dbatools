param($ModuleName = 'dbatools')

Describe "Read-DbaAuditFile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Read-DbaAuditFile
        }

        It "has all the required parameters" {
            $params = @(
                "Path",
                "Raw",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
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
