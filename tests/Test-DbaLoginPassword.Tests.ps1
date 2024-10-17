param($ModuleName = 'dbatools')

Describe "Test-DbaLoginPassword" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Get-PasswordHash.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaLoginPassword
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Login parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[]
        }
        It "Should have Dictionary parameter" {
            $CommandUnderTest | Should -HaveParameter Dictionary -Type String[]
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Login[]
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $weaksauce = "dbatoolsci_testweak"
            $weakpass = ConvertTo-SecureString $weaksauce -AsPlainText -Force
            $newlogin = New-DbaLogin -SqlInstance $script:instance1 -Login $weaksauce -HashedPassword (Get-PasswordHash $weakpass $server.VersionMajor) -Force
        }
        AfterAll {
            try {
                $newlogin.Drop()
            } catch {
                # don't care
            }
        }

        It "finds the new weak password and supports piping" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 | Test-DbaLoginPassword
            $results.SqlLogin | Should -Contain $weaksauce
        }
        It "returns just one login" {
            $results = Test-DbaLoginPassword -SqlInstance $script:instance1 -Login $weaksauce
            $results.SqlLogin | Should -Be $weaksauce
        }
        It "handles passwords with quotes, see #9095" {
            $results = Test-DbaLoginPassword -SqlInstance $script:instance1 -Login $weaksauce -Dictionary "&é`"'(-", "hello"
            $results.SqlLogin | Should -Be $weaksauce
        }
    }
}
