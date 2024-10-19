param($ModuleName = 'dbatools')

Describe "Export-DbaCredential Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaCredential
        }
        It "Should have SqlInstance as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Identity as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Identity
        }
        It "Should have SqlCredential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Credential as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Path as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have FilePath as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath
        }
        It "Should have ExcludePassword as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludePassword
        }
        It "Should have Append as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Append
        }
        It "Should have InputObject as a non-mandatory parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }
}

Describe "Export-DbaCredential Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $plaintext = "ReallyT3rrible!"
        $password = ConvertTo-SecureString $plaintext -AsPlainText -Force
        $null = New-DbaCredential -SqlInstance $global:instance2 -Name dbatoolsci_CaptainAcred -Identity dbatoolsci_CaptainAcredId -Password $password
        $null = New-DbaCredential -SqlInstance $global:instance2 -Identity dbatoolsci_Hulk -Password $password
        $allfiles = @()
    }
    AfterAll {
        try {
            (Get-DbaCredential -SqlInstance $global:instance2 -Identity dbatoolsci_CaptainAcred, dbatoolsci_Hulk -ErrorAction Stop -WarningAction SilentlyContinue).Drop()
        } catch { }
        $null = $allfiles | Remove-Item -ErrorAction Ignore
    }

    Context "Should export all credentials" {
        BeforeAll {
            $file = Export-DbaCredential -SqlInstance $global:instance2
            $results = Get-Content -Path $file -Raw
            $allfiles += $file
        }
        It "Should have information" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have all users" {
            $results | Should -Match 'CaptainACred|Hulk'
        }
        It "Should have the password" {
            $results | Should -Match 'ReallyT3rrible!'
        }
    }

    Context "Should export a specific credential" {
        BeforeAll {
            $filepath = "$env:USERPROFILE\Documents\dbatoolsci_credential.sql"
            $null = Export-DbaCredential -SqlInstance $global:instance2 -Identity 'dbatoolsci_CaptainAcredId' -FilePath $filepath
            $results = Get-Content -Path $filepath
            $allfiles += $filepath
        }
        It "Should have information" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should only have one credential" {
            $results | Should -Match 'CaptainAcred'
        }
        It "Should have the password" {
            $results | Should -Match 'ReallyT3rrible!'
        }
    }

    Context "Should export a specific credential and append it to existing export" {
        BeforeAll {
            $filepath = "$env:USERPROFILE\Documents\dbatoolsci_credential.sql"
            $null = Export-DbaCredential -SqlInstance $global:instance2 -Identity 'dbatoolsci_Hulk' -FilePath $filepath -Append
            $results = Get-Content -Path $filepath
        }
        It "Should have information" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should have multiple credentials" {
            $results | Should -Match 'Hulk|CaptainA'
        }
        It "Should have the password" {
            $results | Should -Match 'ReallyT3rrible!'
        }
    }

    Context "Should export a specific credential excluding the password" {
        BeforeAll {
            $filepath = "$env:USERPROFILE\Documents\temp-credential.sql"
            $null = Export-DbaCredential -SqlInstance $global:instance2 -Identity 'dbatoolsci_CaptainAcredId' -FilePath $filepath -ExcludePassword
            $results = Get-Content -Path $filepath
            $allfiles += $filepath
        }
        It "Should have information" {
            $results | Should -Not -BeNullOrEmpty
        }
        It "Should contain the correct identity (see #7282)" {
            $results | Should -Match "IDENTITY = N'dbatoolsci_CaptainAcredId'"
        }
        It "Should not have the password" {
            $results | Should -Not -Match 'ReallyT3rrible!'
        }
    }
}
