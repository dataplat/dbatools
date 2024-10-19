param($ModuleName = 'dbatools')

Describe "Enable-DbaFilestream" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Enable-DbaFilestream
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
        It "Should have FileStreamLevel as a parameter" {
            $CommandUnderTest | Should -HaveParameter FileStreamLevel
        }
        It "Should have ShareName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ShareName
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Enable-DbaFilestream Integration Tests" -Tag "IntegrationTests" {
    BeforeDiscovery {
        $OriginalFileStream = Get-DbaFilestream -SqlInstance $global:instance1
    }

    BeforeAll {
        $OriginalFileStream = Get-DbaFilestream -SqlInstance $global:instance1
    }

    AfterAll {
        if ($OriginalFileStream.InstanceAccessLevel -eq 0) {
            Disable-DbaFilestream -SqlInstance $global:instance1 -Confirm:$false
        } else {
            Enable-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $OriginalFileStream.InstanceAccessLevel -Confirm:$false
        }
    }

    Context "Changing FileStream Level" {
        BeforeAll {
            $NewLevel = ($OriginalFileStream.FileStreamStateId + 1) % 3 #Move it on one, but keep it less than 4 with modulo division
            $results = Enable-DbaFilestream -SqlInstance $global:instance1 -FileStreamLevel $NewLevel -Confirm:$false
        }

        It "Should have changed the FileStream Level" {
            $results.InstanceAccessLevel | Should -Be $NewLevel
        }
    }
}
