$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Database', 'InputObject', 'EnableException', 'ExcludeDatabase'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Gets a certificate" {
        $keyname = 'test4'
        $keyname2 = 'test5'
        $algorithm = 'Rsa4096'
        $dbuser = 'keyowner'
        $database = 'GetAsKey'
        New-DbaDatabase -SqlInstance $script:instance2 -Name $database
        $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
        New-DbaDbMasterKey -SqlInstance $script:instance2 -Database $database -SecurePassword $tPassword -confirm:$false
        New-DbaDbUser -SqlInstance $script:instance2 -Database $database -UserName $dbuser
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database $database -Name $keyname -Owner keyowner -Algorithm $algorithm -WarningVariable warnvar
        $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database
        It "Should Create new key in $database called $keyname" {
            $warnvar | Should -BeNullOrEmpty
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.Owner | Should -Be $dbuser
            $results | Should -HaveCount 1
        }
        $pipeResults = Get-DbaDatabase -SqlInstance $script:instance2 -Database $database | Get-DbaDbAsymmetricKey
        It "Should work with a piped database" {
            $pipeResults.database | Should -Be $database
            $pipeResults.name | Should -Be $keyname
            $pipeResults.Owner | Should -Be $dbuser
            $pipeResults | Should -HaveCount 1
        }

        $key2 = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database $database -Name $keyname2 -Owner keyowner -Algorithm $algorithm -WarningVariable warnvar
        $multiResults = Get-DbaDatabase -SqlInstance $script:instance2 -Database $database | Get-DbaDbAsymmetricKey
        It "Should return 2 keys" {
            $multiResults | Should -HaveCount 2
            $multiresults.name | Should -Contain $keyname
            $multiresults.name | Should -Contain $keyname2
        }
        $drop = Remove-DbaDatabase -SqlInstance $script:instance2 -Database $database -confirm:$false
        It "Should drop database" {
            $drop.Status | Should -Be 'Dropped'
        }
    }
}