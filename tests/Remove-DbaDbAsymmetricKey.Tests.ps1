param($ModuleName = 'dbatools')

Describe "Remove-DbaDbAsymmetricKey" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDbAsymmetricKey
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
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type AsymmetricKey[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Remove a certificate" {
        BeforeAll {
            $database = 'RemAsy'
            $null = New-DbaDatabase -SqlInstance $env:instance2 -Name $database
            $keyname = 'test1'
            $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
            New-DbaDbMasterKey -SqlInstance $env:instance2 -Database $database -SecurePassword $tPassword -Confirm:$false
            $key = New-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Name $keyname -Database $database
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $env:instance2 -Database $database -Confirm:$false
        }

        It "Should create new key in $database called $keyname" {
            $results = Get-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Name $keyname -Database $database
            $results.Database | Should -Be $database
            $results.Name | Should -Be $keyname
            $results.KeyLength | Should -Be '2048'
        }

        It "Should Remove a certificate" {
            $removeResults = Remove-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Name $keyname -Database $database -Confirm:$false
            $getResults = Get-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Name $keyname -Database $database
            $getResults | Should -HaveCount 0
            $removeResults.Status | Should -Be 'Success'
        }
    }

    Context "Remove a specific certificate" {
        BeforeAll {
            $database = 'RemAsy'
            $keyname = 'test1'
            $keyname2 = 'test2'
            $null = New-DbaDatabase -SqlInstance $env:instance2 -Name $database
            $key = New-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Name $keyname -Database $database
            $key2 = New-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Name $keyname2 -Database $database
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $env:instance2 -Database $database -Confirm:$false
        }

        It "Should create new keys in $database" {
            $results = Get-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Database $database
            $results | Should -HaveCount 2
        }

        It "Should Remove a specific certificate" {
            $removeResults = Remove-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Name $keyname -Database $database -Confirm:$false
            $getResults = Get-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Database $database
            $getResults | Should -HaveCount 1
            $getResults[0].Name | Should -Be $keyname2
            $removeResults.Status | Should -Be 'Success'
            $removeResults.Name | Should -Be $keyname
        }

        It "Should remove the remaining certificate" {
            $removeResults = Remove-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Name $keyname2 -Database $database -Confirm:$false
            $getResults = Get-DbaDbAsymmetricKey -SqlInstance $env:instance2 -Database $database
            $getResults | Should -HaveCount 0
            $removeResults.Status | Should -Be 'Success'
            $removeResults.Name | Should -Be $keyname2
        }
    }
}
