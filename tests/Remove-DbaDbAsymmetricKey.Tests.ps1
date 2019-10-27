$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Database', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Remove a certificate" {
        $keyname = 'test1'
        $database = 'RemAsy'
        New-DbaDatabase -SqlInstance $script:instance2 -Name $database
        $tPassword = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
        New-DbaDbMasterKey -SqlInstance $script:instance2 -Database $database -SecurePassword $tPassword -confirm:$false
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -database $database
        $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database -WarningVariable warnvar

        It  "Should create new key in $database called $keyname" {
            $warnvar | Should -BeNullOrEmpty
            $results.database | Should -Be $database
            $results.name | Should -Be $keyname
            $results.KeyLength | Should -Be '2048'
        }

        $removeResults = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database -confirm:$false
        $getResults = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database
        It "Should Remove a certificate" {
            $getResults | Should -HaveCount 0
            $removeResults.Status | Should -Be 'Success'
        }
    }
    Context "Remove a specific certificate" {
        $keyname = 'test1'
        $keyname2 = 'test2'
        $database = 'RemAsy'
        $key = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database
        $key2 = New-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname2 -Database $database
        $results = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database $database -WarningVariable warnvar

        It  "Should created new keys in $database " {
            $warnvar | Should -BeNullOrEmpty
            $results | Should -HaveCount 2
        }
        $removeResults = Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname -Database $database -confirm:$false
        $getResults = Get-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Database $database
        It "Should Remove a specific certificate" {
            $getResults | Should -HaveCount 1
            $getResults[0].Name | Should -Be $keyname2
            $removeResults.Status | Should -Be 'Success'
            $removeResults.Name | Should -Be $keyname
        }
        Remove-DbaDbAsymmetricKey -SqlInstance $script:instance2 -Name $keyname2 -Database $database -confirm:$false
    }
}
