$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance','SqlCredential','Name','Database','InputObject','EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Remove a certificate" {
        $keyname = 'test1'
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname
        $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -WarningVariable warnvar
        $removeResults = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -confirm:$false
        $getResults = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master
        It  "Should create new key in master called $keyname" {
            ($warnvar -eq $null) | Should -Be $True
            $results.database | Should -Be 'master'
            $results.name | Should -Be $keyname
            $results.KeyEncryptionAlgorithm | Should -Be 'Rsa2048'
        }
        It "Should Remove a certificate" {
            $getResults | Should -HaveCount 0
            $removeResults.Status | Should -Be 'Success'
        }
    }
    Context "Remove a specific certificate" {
        $keyname = 'test1'
        $keyname2 = 'test2'
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname
        $key2 = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname2
        $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -WarningVariable warnvar
        $removeResults = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master -confirm:$false
        $getResults = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database master
        It  "Should new keys in master " {
            ($warnvar -eq $null) | Should -Be $True
            $results | Should -HaveCount 2
        }
        It "Should Remove a specific certificate" {
            $getResults | Should -HaveCount 1
            $getResults[0].Name | Should -Be $keyname2
            $removeResults.Status | Should -Be 'Success'
            $removeResults.Name | Should -Be $keyname
        }
    }
}
