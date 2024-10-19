param($ModuleName = 'dbatools')

Describe "Get-DbaDbMailConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMailConfig
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Name",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
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
            BeforeAll {
                $results = Get-DbaDbMailConfig -SqlInstance $global:instance2
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should have Configured Value of <_.name>" -ForEach $results {
                $_.name | Should -BeIn $mailSettings.keys
            }
            It "Should have Configured Value settings for <_.name> of <_.value>" -ForEach $results {
                $_.value | Should -BeIn $mailSettings.values
            }
        }

        Context "Gets DbMail Settings when using -Name" {
            BeforeAll {
                $results = Get-DbaDbMailConfig -SqlInstance $global:instance2 -Name "ProhibitedExtensions"
            }
            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }
            It "Should have Name 'ProhibitedExtensions'" {
                $results.name | Should -Be "ProhibitedExtensions"
            }
            It "Should have Value 'exe,dll,vbs,js'" {
                $results.value | Should -Be "exe,dll,vbs,js"
            }
            It "Should have Description 'Extensions not allowed in outgoing mails'" {
                $results.description | Should -Be "Extensions not allowed in outgoing mails"
            }
        }
    }
}
