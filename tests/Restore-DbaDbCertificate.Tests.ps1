$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Restore-DbaDbCertificate).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'Database', 'SecurePassword', 'EncryptionPassword', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Can create a database certificate" {
        BeforeAll {
            $masterkey = New-DbaDbMasterKey -SqlInstance $script:instance1 -Database tempdb -Password $(ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force) -Confirm:$false
            $password = ConvertTo-SecureString -AsPlainText "GoodPass1234!!" -Force
            $cert = New-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb -Confirm:$false
            $backup = Backup-DbaDbCertificate -SqlInstance $script:instance1 -Database tempdb -EncryptionPassword $password -Confirm:$false
        }
        AfterAll {
            $null = Remove-DbaDbCertificate -SqlInstance $script:instance1 -Certificate $cert.Name -Database tempdb -Confirm:$false
            $null = $masterkey | Remove-DbaDbMasterKey -Confirm:$false
        }

        It "restores the db cert" {
            $results = Restore-DbaDbCertificate -SqlInstance $script:instance1 -Path $backup.ExportPath -Password $password -Database tempdb -EncryptionPassword $password -Confirm:$false
            $results.Parent.Name | Should Be 'tempdb'
            $results.Name | Should Not BeNullOrEmpty
            $results.PrivateKeyEncryptionType | Should Be "MasterKey" # Should Be "Password"
            $results | Remove-DbaDbCertificate -Confirm:$false
            # TODO: Create a test for password generated cert
            # From what I can tell, what matters is creation, not restore.
        }
    }
}