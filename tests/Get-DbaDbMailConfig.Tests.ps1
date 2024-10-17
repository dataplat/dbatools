param($ModuleName = 'dbatools')

Describe "Get-DbaDbMailConfig" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbMailConfig
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Name as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Name -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory parameter of type SqlMail[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type SqlMail[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
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
            BeforeAll {
                $results = Get-DbaDbMailConfig -SqlInstance $script:instance2
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
                $results = Get-DbaDbMailConfig -SqlInstance $script:instance2 -Name "ProhibitedExtensions"
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
