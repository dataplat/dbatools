$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance','SqlCredential','Name','Database','InputObject','EnableException','ExcludeDatabase'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Gets a certificate" {
        $keyname = 'test4'
        $keyname2  = 'test5'
        $algorithm = 'Rsa4096'
        $dbuser = 'keyowner'
        $database = 'GetAsKey'
        New-DbaDbDatabase -SqlInstance $sciprt:instance2 -Name $database
        New-DbaDbUser -SqlInstance $script:instance2 -Database $database -UserName $dbuser
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database $database -Name $keyname -Owner keyowner -Algorithm $algorithm -WarningVariable warnvar
        $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master
        It "Should Create new key in master called $keyname"{
            ($warnvar -eq $null) | Should -Be $True
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.KeyEncryptionAlgorithm | Should -Be $algorithm
            $results.Owner | Should -Be $dbuser
            $results | Should -HaveCount 1
        }
        $pipeResults = Get-DbaDbDatabase -SqlInstance $script:instance2 -Database $database | Get-DbaDbAsymmetricKey
        It "Should work with a piped database" {
            $pipeResults.database | Should -Be $database
            $pipeResults.name | Should -Be $keyname
            $pipeResults.KeyEncryptionAlgorithm | Should -Be $algorithm
            $pipeResults.Owner | Should -Be $dbuser
            $pipeResults | Should -HaveCount 1
        }
        It "Should Cleanup after itself" {
            $null = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database
        }
        $key2 = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database $database -Name $keyname2 -Owner keyowner -Algorithm $algorithm -WarningVariable warnvar
        $multiResults = = Get-DbaDbDatabase -SqlInstance $script:instance2 -Database $database | Get-DbaDbAsymmetricKey
        It "Should return 2 keys" {
            $multiResults | Should -HaveCounte 2
            $multiresults.name | Should -Contain $keyname
            $multiresults.name | Should -Contain $keyname2
        }
    }
}