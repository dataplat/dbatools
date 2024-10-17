param($ModuleName = 'dbatools')

Describe "Get-DbaDbMail" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMail
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch -Not -Mandatory
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
