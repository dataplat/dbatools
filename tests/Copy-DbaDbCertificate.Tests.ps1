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
            if (-not (Get-DbaDbMasterKey -SqlInstance $script:instance2 -Database master)) {
                $masterkey = New-DbaDbMasterKey -SqlInstance $script:instance2 -Database master -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            }

            $passwd = $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force)
            $tempdbmasterkey = New-DbaDbMasterKey -SqlInstance $script:instance2 -Database tempdb -Password $passwd -Confirm:$false
            $certificateName1 = "Cert_$(Get-Random)"
            $certificateName2 = "Cert_$(Get-Random)"
            $cert1 = New-DbaDbCertificate -SqlInstance $script:instance2 -Name $certificateName1 -Confirm:$false
            $cert2 = New-DbaDbCertificate -SqlInstance $script:instance2 -Name $certificateName2 -Database tempdb -Confirm:$false
        }
        AfterAll {
            if ($tempdbmasterkey) {
                $tempdbmasterkey | Remove-DbaDbMasterKey -Confirm:$false -ErrorAction SilentlyContinue
            }
            if ($masterKey) {
                $masterkey | Remove-DbaDbMasterKey -Confirm:$false -ErrorAction SilentlyContinue
            }
            $null = $cert1 | Remove-DbaDbCertificate -Confirm:$false -ErrorAction SilentlyContinue
            $null = $cert2 | Remove-DbaDbCertificate -Confirm:$false -ErrorAction SilentlyContinue
        }
        # doing it on docker instead. this works on linux and on a homelab so i dont know
        It -Skip "Successfully copies a certificate" {
            $params1 = @{
                Source             = $script:instance2
                Destination        = $script:instance3
                EncryptionPassword = $passwd
                MasterKeyPassword  = $passwd
                Database           = "tempdb"
                SharedPath         = "C:\temp"
            }
            $results = Copy-DbaDbCertificate @params1 -Confirm:$false | Where-Object SourceDatabase -eq tempdb | Select-Object -First 1
            $results.Notes | Should -Be $null
            $results.Status | Should -Be "Successful"
        }
    }
}