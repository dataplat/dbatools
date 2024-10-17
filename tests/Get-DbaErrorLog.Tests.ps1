param($ModuleName = 'dbatools')

Describe "Get-DbaErrorLog" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaErrorLog
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have LogNumber as a parameter" {
            $CommandUnderTest | Should -HaveParameter LogNumber -Type Int32[]
        }
        It "Should have Source as a parameter" {
            $CommandUnderTest | Should -HaveParameter Source -Type Object[]
        }
        It "Should have Text as a parameter" {
            $CommandUnderTest | Should -HaveParameter Text -Type String
        }
        It "Should have After as a parameter" {
            $CommandUnderTest | Should -HaveParameter After -Type DateTime
        }
        It "Should have Before as a parameter" {
            $CommandUnderTest | Should -HaveParameter Before -Type DateTime
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Correctly gets error log messages" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $sourceFilter = "Logon"
            $textFilter = "All rights reserved"
            $login = 'DaperDan'
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $l = Get-DbaLogin -SqlInstance $script:instance1 -Login $login
            if ($l) {
                Get-DbaProcess -SqlInstance $script:instance1 -Login $login | Stop-DbaProcess
                $l.Drop()
            }
            # (1) Cycle errorlog message: The error log has been reinitialized
            $null = $server.Query("EXEC sp_cycle_errorlog;")

            # (2) Need a login failure, source would be Logon
            $pwd = "p0w3rsh3llrules" | ConvertTo-SecureString -Force -AsPlainText
            $sqlCred = New-Object System.Management.Automation.PSCredential($login, $pwd)
            try {
                Connect-DbaInstance -SqlInstance $script:instance1 -SqlCredential $sqlCred -ErrorVariable whatever
            } catch {}
        }

        It "Has the correct default properties" {
            $expectedProps = 'ComputerName,InstanceName,SqlInstance,LogDate,Source,Text'.Split(',')
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 0
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($expectedProps | Sort-Object)
        }

        It "Returns filtered results for [Source = $sourceFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -Source $sourceFilter
            $results[0].Source | Should -Be $sourceFilter
        }

        It "Returns filtered result for [LogNumber = 0] and [Source = $sourceFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 0 -Source $sourceFilter
            $results[0].Source | Should -Be $sourceFilter
        }

        It "Returns filtered results for [Text = $textFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -Text $textFilter
            $results[0].Text | Should -BeLike "*$textFilter*"
        }

        It "Returns filtered result for [LogNumber = 0] and [Text = $textFilter]" {
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 0 -Text $textFilter
            $results[0].Text | Should -BeLike "*$textFilter*"
        }

        It "Returns filtered results for [After = `$afterFilter]" {
            $after = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 | Select-Object -First 1
            $afterFilter = $after.LogDate.AddMinutes(+1)
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -After $afterFilter
            $results[0].LogDate | Should -BeGreaterOrEqual $afterFilter
        }

        It "Returns filtered results for [LogNumber = 1] and [After = `$afterFilter]" {
            $after = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 | Select-Object -First 1
            $afterFilter = $after.LogDate.AddMinutes(+1)
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 -After $afterFilter
            $results[0].LogDate | Should -BeGreaterOrEqual $afterFilter
        }

        It "Returns filtered result for [Before = `$beforeFilter]" {
            $before = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 | Select-Object -Last 1
            $beforeFilter = $before.LogDate.AddMinutes(-1)
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -Before $beforeFilter
            $results[-1].LogDate | Should -BeLessOrEqual $beforeFilter
        }

        It "Returns filtered result for [LogNumber = 1] and [Before = `$beforeFilter]" {
            $before = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 | Select-Object -Last 1
            $beforeFilter = $before.LogDate.AddMinutes(-1)
            $results = Get-DbaErrorLog -SqlInstance $script:instance1 -LogNumber 1 -Before $beforeFilter
            $results[-1].LogDate | Should -BeLessOrEqual $beforeFilter
        }
    }
}
