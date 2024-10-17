param($ModuleName = 'dbatools')

Describe "New-DbaDbAsymmetricKey" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbAsymmetricKey
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String[]
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[]
        }
        It "Should have SecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword -Type SecureString
        }
        It "Should have Owner as a parameter" {
            $CommandUnderTest | Should -HaveParameter Owner -Type String
        }
        It "Should have KeySource as a parameter" {
            $CommandUnderTest | Should -HaveParameter KeySource -Type String
        }
        It "Should have KeySourceType as a parameter" {
            $CommandUnderTest | Should -HaveParameter KeySourceType -Type String
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[]
        }
        It "Should have Algorithm as a parameter" {
            $CommandUnderTest | Should -HaveParameter Algorithm -Type String
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
            if (!(Get-DbaDbMasterKey -SqlInstance $script:instance2 -Database master)) {
                New-DbaDbMasterKey -SqlInstance $script:instance2 -Database master -SecurePassword $tPassword -Confirm:$false
            }
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database enctest -Confirm:$false
        }

        It "Should create new key in master" {
            $keyname = 'test1'
            $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname
            $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master
            $results.database | Should -Be 'master'
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be '2048'
        }

        It "Should warn when key already exists" {
            $keyname = 'test1'
            $null = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -WarningVariable warnvar 3> $null
            $null = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -Confirm:$false
            $warnvar | Should -BeLike '*already exists in master on*'
        }

        It "Should handle algorithm changes" {
            $keyname = 'test2'
            $algorithm = 'Rsa4096'
            $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Algorithm $algorithm
            $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master
            $results.database | Should -Be 'master'
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be 4096
            $null = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -Confirm:$false
        }

        It "Should create key in non-master database" {
            $keyname = 'test4'
            $algorithm = 'Rsa4096'
            $dbuser = 'keyowner'
            $database = 'enctest'
            New-DbaDatabase -SqlInstance $script:instance2 -Name $database
            $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
            New-DbaDbMasterKey -SqlInstance $script:instance2 -Database $database -SecurePassword $tPassword -Confirm:$false
            New-DbaDbUser -SqlInstance $script:instance2 -Database $database -UserName $dbuser
            $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database $database -Name $keyname -Owner $dbuser -Algorithm $algorithm
            $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be 4096
            $results.Owner | Should -Be $dbuser
            $null = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database -Confirm:$false
        }

        It "Should set owner correctly" {
            $keyname = 'test3'
            $algorithm = 'Rsa4096'
            $dbuser = 'keyowner'
            $database = 'enctest'
            $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Owner $dbuser -Database $database -Algorithm $algorithm
            $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be 4096
            $results.Owner | Should -Be $dbuser
            $null = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database -Confirm:$false
        }

        It "Should create new key loaded from a keyfile" -Skip:(-not (Test-Path -Path "$($script:appveyorlabrepo)\keytests\keypair.snk")) {
            $keyname = 'filekey'
            $dbuser = 'keyowner'
            $database = 'enctest'
            $path = "$($script:appveyorlabrepo)\keytests\keypair.snk"
            $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database $database -Name $keyname -Owner $dbuser -KeySourceType File -KeySource $path
            $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.Owner | Should -Be $dbuser
            $null = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database -Confirm:$false
        }

        It "Should fail key creation from a missing keyfile" {
            $keyname = 'filekeybad'
            $dbuser = 'keyowner'
            $database = 'enctest'
            $path = "$($script:appveyorlabrepo)\keytests\keypair.bad"
            $null = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database $database -Name $keyname -Owner $dbuser -KeySourceType File -KeySource $path -WarningVariable warnvar 3> $null
            $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database
            $warnvar | Should -Not -BeNullOrEmpty
            $results | Should -BeNullOrEmpty
            $null = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database -Confirm:$false
        }
    }
}
