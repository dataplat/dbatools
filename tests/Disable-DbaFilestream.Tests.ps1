param($ModuleName = 'dbatools')

Describe "Disable-DbaFilestream" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Disable-DbaFilestream
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

<#
Describe "Disable-DbaFilestream Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $OriginalFileStream = Get-DbaFilestream -SqlInstance $global:instance1
    }
    AfterAll {
        Set-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $OriginalFileStream.InstanceAccessLevel -Force
    }

    Context "Changing FileStream Level" {
        BeforeAll {
            $NewLevel = ($OriginalFileStream.FileStreamStateId + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
            $results = Set-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $NewLevel -Force -WarningAction SilentlyContinue -ErrorVariable errvar -ErrorAction SilentlyContinue
        }
        It "Should have changed the FileStream Level" {
            $results.InstanceAccessLevel | Should -Be $NewLevel
        }
    }
}
#>
