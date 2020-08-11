$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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
        $results = Get-DbaDbMailConfig -SqlInstance $script:instance2
        It "Gets results" {
            $results | Should Not Be $null
        }
        Foreach ($row in $($results)) {
            It "Should have Configured Value of $($row.name)" {
                $row.name | Should Bein $mailSettings.keys
            }
            It "Should have Configured Value settings for $($row.name) of $($row.value)" {
                $row.value | Should Bein $mailSettings.values
            }
        }
    }
    Context "Gets DbMail Settings when using -Name" {
        $results = Get-DbaDbMailConfig -SqlInstance $script:instance2 -Name "ProhibitedExtensions"
        It "Gets results" {
            $results | Should Not Be $null
        }
        It "Should have Name 'ProhibitedExtensions'" {
            $results.name | Should Be "ProhibitedExtensions"
        }
        It "Should have Value 'exe,dll,vbs,js'" {
            $results.value | Should Be "exe,dll,vbs,js"
        }
        It "Should have Description 'Extensions not allowed in outgoing mails'" {
            $results.description | Should Be "Extensions not allowed in outgoing mails"
        }
    }
}