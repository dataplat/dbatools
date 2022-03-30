$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Source', 'SourceSqlCredential', 'Destination', 'DestinationSqlCredential', 'Database', 'ExcludeDatabase', 'Certificate', 'ExcludeCertificate', 'SharedPath', 'MasterKeyPassword', 'EncryptionPassword', 'DecryptionPassword', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Can create a database certificate" {
        BeforeAll {
            $passwd = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
            $masterkey = New-DbaDbMasterKey -SqlInstance $script:instance2 -Database master -SecurePassword $passwd -Confirm:$false -ErrorAction SilentlyContinue

            $newdbs = New-DbaDatabase -SqlInstance $script:instance2, $script:instance3 -Name dbatoolscopycred
            $null = New-DbaDbMasterKey -SqlInstance $script:instance2 -Database dbatoolscopycred -SecurePassword $passwd -Confirm:$false
            $certificateName2 = "Cert_$(Get-Random)"
            $null = New-DbaDbCertificate -SqlInstance $script:instance2 -Name $certificateName2 -Database dbatoolscopycred -Confirm:$false
        }
        AfterAll {
            $null = $newdbs | Remove-DbaDatabase -Confirm:$false -ErrorAction SilentlyContinue
            if ($masterKey) {
                $masterkey | Remove-DbaDbMasterKey -Confirm:$false -ErrorAction SilentlyContinue
            }
        }
        # doing it on docker instead. this works on linux and on a windows homelab so i dont know
        It -Skip "Successfully copies a certificate" {
            $passwd = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
            $paramscopydb = @{
                Source             = $script:instance2
                Destination        = $script:instance3
                EncryptionPassword = $passwd
                MasterKeyPassword  = $passwd
                Database           = "dbatoolscopycred"
                SharedPath         = $script:appveyorlabrepo
            }
            $results = Copy-DbaDbCertificate @paramscopydb -Confirm:$false | Where-Object SourceDatabase -eq dbatoolscopycred | Select-Object -First 1
            $results.Notes | Should -Be $null
            $results.Status | Should -Be "Successful"
            $results.SourceDatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $script:instance2 -Database dbatoolscopycred).ID
            $results.DestinationDatabaseID | Should -Be (Get-DbaDatabase -SqlInstance $script:instance3 -Database dbatoolscopycred).ID

            Get-DbaDbCertificate -SqlInstance $script:instance3 -Database dbatoolscopycred -Certificate $certificateName2 | Should -Not -BeNullOrEmpty
        }
    }
}