$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance2
        $mailSettings = @{
            AccountRetryAttempts           = '1'
            AccountRetryDelay              = '60'
            DatabaseMailExeMinimumLifeTime = '600'
            DefaultAttachmentEncoding      = 'MIME'
            LoggingLevel                   = '2'
            MaxFileSize                    = '1000'
            ProhibitedExtensions           = 'exe,dll,vbs,js'
        }
        foreach ($m in $mailSettings.GetEnumerator()) {
            $server.query("exec msdb.dbo.sysmail_configure_sp '$($m.key)','$($m.value)';")
        }
    }

    Context "Gets DbMail Settings" {
        $results = Get-DbaDbMail -SqlInstance $script:instance2
        It "Gets results" {
            $results | Should Not Be $null
        }
        Foreach ($row in $($results.ConfigurationValues)) {
            It "Should have ConfiguredValues of $($row.name)" {
                $row.name | Should Bein $mailSettings.keys
            }
            It "Should have ConfiguredValues settings for $($row.name) of $($row.value)" {
                $row.value | Should Bein $mailSettings.values
            }
        }
    }
}