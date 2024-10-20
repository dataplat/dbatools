$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Database', 'SecurePassword', 'Owner', 'KeySource', 'KeySourceType', 'InputObject', 'Algorithm', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    AfterAll {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database enctest -Confirm:$false
    }

    Context "commands work as expected" {
        $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
        if (!(Get-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master )) {
            New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database master -SecurePassword $tpassword -confirm:$false
        }
        $keyname = 'test1'
        $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname
        $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database master -WarningVariable warnvar
        It  "Should create new key in master called $keyname" {
            $warnvar | Should -BeNullOrEmpty
            $results.database | Should -Be 'master'
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be '2048'
        }
    }

    Context "Handles pre-existing key" {
        $keyname = 'test1'
        $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database master -WarningVariable warnvar 3> $null
        $null = Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database master -confirm:$false
        It "Should Warn that they key $keyname already exists" {
            $Warnvar | Should -BeLike '*already exists in master on*'
        }
    }

    Context "Handles Algorithm changes" {
        $keyname = 'test2'
        $algorithm = 'Rsa4096'
        $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Algorithm $algorithm -WarningVariable warnvar
        $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database master
        It "Should Create new key in master called $keyname" {
            $warnvar | Should -BeNullOrEmpty
            $results.database | Should -Be 'master'
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be 4096
        }
        $null = Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database master -confirm:$false

    }

    Context "Non master database" {
        $keyname = 'test4'
        $algorithm = 'Rsa4096'
        $dbuser = 'keyowner'
        $database = 'enctest'
        New-DbaDatabase -SqlInstance $TestConfig.instance2 -Name $database
        $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
        New-DbaDbMasterKey -SqlInstance $TestConfig.instance2 -Database $database -SecurePassword $tpassword -Confirm:$false
        New-DbaDbUser -SqlInstance $TestConfig.instance2 -Database $database -UserName $dbuser
        $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Database $database -Name $keyname -Owner keyowner -Algorithm $algorithm -WarningVariable warnvar
        $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database $database
        It "Should Create new key in master called $keyname" {
            $warnvar | Should -BeNullOrEmpty
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be 4096
            $results.Owner | Should -Be $dbuser
        }
        $null = Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database $database -confirm:$false

    }

    Context "Sets owner correctly" {
        $keyname = 'test3'
        $algorithm = 'Rsa4096'
        $dbuser = 'keyowner'
        $database = 'enctest'
        $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Owner keyowner -Database $database -Algorithm $algorithm -WarningVariable warnvar
        $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database $database

        It "Should Create new key in master called $keyname" {
            $warnvar | Should -BeNullOrEmpty
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be 4096
            $results.Owner | Should -Be $dbuser
        }
        $null = Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database $database -confirm:$false
    }

    Context "Create new key loaded from a keyfile" {
        $skip = $false
        $keyname = 'filekey'
        $dbuser = 'keyowner'
        $database = 'enctest'
        $path = "$($TestConfig.appveyorlabrepo)\keytests\keypair.snk"
        if (Test-Path -Path $path) {
            $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Database $database -Name $keyname -Owner keyowner -WarningVariable warnvar -KeySourceType File -KeySource $path
            $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database $database
        } else {
            Write-Warning -Message "No keypair found in path [$path], skipping tests."
            $skip = $true
        }
        It -Skip:$skip "Should Create new key in master called $keyname" {
            $warnvar | Should -BeNullOrEmpty
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.Owner | Should -Be $dbuser
        }
        $null = Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database $database -confirm:$false
    }

    Context "Failed key creation from a missing keyfile" {
        $keyname = 'filekeybad'
        $dbuser = 'keyowner'
        $database = 'enctest'
        $path = "$($TestConfig.appveyorlabrepo)\keytests\keypair.bad"
        $key = New-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Database $database -Name $keyname -Owner keyowner -WarningVariable warnvar -KeySourceType File -KeySource $path 3> $null
        $results = Get-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database $database
        It "Should not Create new key in $database called $keyname" {
            $warnvar | Should -Not -BeNullOrEmpty
            $results | Should -BeNullorEmpty
        }
        $null = Remove-DbaDbAsymmetricKey -SqlInstance $TestConfig.instance2 -Name $keyname -Database $database -confirm:$false

    }
}
