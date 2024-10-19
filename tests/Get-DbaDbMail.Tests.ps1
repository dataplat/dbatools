param($ModuleName = 'dbatools')

Describe "Get-DbaDbMail" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMail
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
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
                $results = Get-DbaDbMail -SqlInstance $global:instance2
            }

            It "Gets results" {
                $results | Should -Not -BeNullOrEmpty
            }

            It "Should have ConfiguredValues of <_.name>" -ForEach $results.ConfigurationValues {
                $_.name | Should -BeIn $mailSettings.keys
            }

            It "Should have ConfiguredValues settings for <_.name> of <_.value>" -ForEach $results.ConfigurationValues {
                $_.value | Should -BeIn $mailSettings.values
            }
        }
    }
}
