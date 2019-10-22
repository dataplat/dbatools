$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance','SqlCredential','Name','Database','SecurePassword','Owner','KeySource','KeySourceType','InputObject','Algorithm','EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "commands work as expected" {
        $keyname = 'test1'
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname
        $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -WarningVariable warnvar
        It Should "Create new key in master called $keyname"{
            ($warnvar -eq $null) | Should -Be $True
            $results.database | Should -Be 'master'
            $results.name | Should -Be $keyname
            $results.KeyEncryptionAlgorithm | Should -Be 'Rsa2048'
        }
    }

    Context "Handles pre-existing key" {
        $keyname = 'test1'
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name test1 -Database master -WarningVariable -warnvar
        It Should "Warn that they key already exists" {
            $Warnvar | Should -BeLike "*asymmetric key with name '$keyname' already exists*"
        }
    }

    Context "Handles Algorithm changes" {
        $keyname = 'test2'
        $algorithm = 'Rsa4096'
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname
        $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -Algorithm $algorithm -WarningVariable warnvar
        It Should "Create new key in master called $keyname"{
            ($warnvar -eq $null) | Should -Be $True
            $results.database | Should -Be 'master'
            $results.name | Should -Be $keyname
            $results.KeyEncryptionAlgorithm | Should -Be $algorithm
        }
    }

    Context "Sets owner correctly" {
        $keyname = 'test3'
        $algorithm = 'Rsa4096'
        $dbuser = 'keyowner'
        New-DbaDbUser -SqlInstance $script:instance2 -Database Master -UserName $dbuser
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Owner keyowner
        $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -Algorithm $algorithm -WarningVariable warnvar
        It Should "Create new key in master called $keyname"{
            ($warnvar -eq $null) | Should -Be $True
            $results.database | Should -Be 'master'
            $results.name | Should -Be $keyname
            $results.KeyEncryptionAlgorithm | Should -Be $algorithm
            $results.Owner | Should -Be $dbuser
        }
    }

    # Context "Non master database" {    }

    # Context "Loaded from a keyfile" {}
}