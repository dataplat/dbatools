$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
$base = (Get-Module -Name dbatools | Where-Object ModuleBase -notmatch net).ModuleBase

# Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XE.Core.dll"
# Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XEvent.Configuration.dll"
# Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XEvent.dll"
# Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XEvent.Linq.dll"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Path', 'Exact', 'Raw', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $path = $server.ErrorLogPath
        $sql = "CREATE SERVER AUDIT LoginAudit
                TO FILE (FILEPATH = N'$path',MAXSIZE = 10 MB,MAX_ROLLOVER_FILES = 1,RESERVE_DISK_SPACE = OFF)
                WITH (QUEUE_DELAY = 1000, ON_FAILURE = CONTINUE)

                CREATE SERVER AUDIT SPECIFICATION TrackAllLogins
                FOR SERVER AUDIT LoginAudit ADD (SUCCESSFUL_LOGIN_GROUP) WITH (STATE = ON)

                ALTER SERVER AUDIT LoginAudit WITH (STATE = ON)"
        $server.Query($sql)
        # generate a login
        $null = Get-DbaDatabase -SqlInstance $script:instance2
        $null = Get-DbaDbFile -SqlInstance $script:instance2
        # Give it a chance to write
        Start-Sleep 2
    }
    AfterAll {
        $sql = "ALTER SERVER AUDIT SPECIFICATION TrackAllLogins WITH (STATE = OFF)
                ALTER SERVER AUDIT LoginAudit WITH (STATE = OFF)
                DROP SERVER AUDIT SPECIFICATION TrackAllLogins
                DROP SERVER AUDIT LoginAudit"
        $server.Query($sql)
    }
    Context "Verifying command output" {
        It "returns some results" {
            $results = Get-DbaInstanceAudit -SqlInstance $script:instance2 -Audit LoginAudit | Read-DbaAuditFile -Raw -WarningAction SilentlyContinue
            [System.Linq.Enumerable]::Count($results) -gt 1 | Should Be $true
        }
        It "returns some results" {
            $results = Get-DbaInstanceAudit -SqlInstance $script:instance2 -Audit LoginAudit | Read-DbaAuditFile | Select-Object -First 1
            $results.server_principal_name | Should -Not -Be $null
        }
    }
}