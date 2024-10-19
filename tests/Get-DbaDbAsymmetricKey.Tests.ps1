param($ModuleName = 'dbatools')

Describe "Get-DbaDbAsymmetricKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbAsymmetricKey
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Gets a certificate" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $keyname = 'test4'
            $keyname2 = 'test5'
            $algorithm = 'Rsa4096'
            $dbuser = 'keyowner'
            $database = 'GetAsKey'
            $newDB = New-DbaDatabase -SqlInstance $global:instance2 -Name $database
            $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
            New-DbaDbMasterKey -SqlInstance $global:instance2 -Database $database -SecurePassword $tPassword
            New-DbaDbUser -SqlInstance $global:instance2 -Database $database -UserName $dbuser
            $null = New-DbaDbAsymmetricKey -SqlInstance $global:instance2 -Database $database -Name $keyname -Owner keyowner -Algorithm $algorithm -WarningVariable warnvar
        }

        It "Should Create new key in $database called $keyname" {
            $results = Get-DbaDbAsymmetricKey -SqlInstance $global:instance2 -Name $keyname -Database $database
            $warnvar | Should -BeNullOrEmpty
            $results.database | Should -Be $database
            $results.DatabaseId | Should -Be $newDB.ID
            $results.name | Should -Be $keyname
            $results.Owner | Should -Be $dbuser
            $results | Should -HaveCount 1
        }

        It "Should work with a piped database" {
            $pipeResults = Get-DbaDatabase -SqlInstance $global:instance2 -Database $database | Get-DbaDbAsymmetricKey
            $pipeResults.database | Should -Be $database
            $pipeResults.name | Should -Be $keyname
            $pipeResults.Owner | Should -Be $dbuser
            $pipeResults | Should -HaveCount 1
        }

        It "Should return 2 keys" {
            $null = New-DbaDbAsymmetricKey -SqlInstance $global:instance2 -Database $database -Name $keyname2 -Owner keyowner -Algorithm $algorithm -WarningVariable warnvar
            $multiResults = Get-DbaDatabase -SqlInstance $global:instance2 -Database $database | Get-DbaDbAsymmetricKey
            $multiResults | Should -HaveCount 2
            $multiResults.name | Should -Contain $keyname
            $multiResults.name | Should -Contain $keyname2
        }

        AfterAll {
            $drop = Remove-DbaDatabase -SqlInstance $global:instance2 -Database $database -Confirm:$false
            $drop.Status | Should -Be 'Dropped'
        }
    }
}
