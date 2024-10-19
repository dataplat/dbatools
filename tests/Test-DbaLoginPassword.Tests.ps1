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
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Login parameter" {
            $CommandUnderTest | Should -HaveParameter Login
        }
        It "Should have Dictionary parameter" {
            $CommandUnderTest | Should -HaveParameter Dictionary
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $weaksauce = "dbatoolsci_testweak"
            $weakpass = ConvertTo-SecureString $weaksauce -AsPlainText -Force
            $newlogin = New-DbaLogin -SqlInstance $global:instance1 -Login $weaksauce -HashedPassword (Get-PasswordHash $weakpass $server.VersionMajor) -Force
        }
        AfterAll {
            try {
                $newlogin.Drop()
            } catch {
                # don't care
            }
        }

        It "finds the new weak password and supports piping" {
            $results = Get-DbaLogin -SqlInstance $global:instance1 | Test-DbaLoginPassword
            $results.SqlLogin | Should -Contain $weaksauce
        }
        It "returns just one login" {
            $results = Test-DbaLoginPassword -SqlInstance $global:instance1 -Login $weaksauce
            $results.SqlLogin | Should -Be $weaksauce
        }
        It "handles passwords with quotes, see #9095" {
            $results = Test-DbaLoginPassword -SqlInstance $global:instance1 -Login $weaksauce -Dictionary "&é`"'(-", "hello"
            $results.SqlLogin | Should -Be $weaksauce
        }
    }
}
