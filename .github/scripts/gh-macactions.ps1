Describe "Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        if (-not (Get-Module dbatools)) {
            Write-Warning "Importing dbatools from source"
            Import-Module dbatools.library
            Import-Module ./dbatools.psd1 -Force
        }
    }

    It "creates a dac object" {
        $extractOptions = New-DbaDacOption -Action Export
        $extractOptions.ExtractAllTableData = $true
        $extractOptions | Should -Not -BeNullOrEmpty
    }

    It "connects to Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
        Connect-DbaInstance -SqlInstance "Server=dbatoolstest.database.windows.net; Authentication=Active Directory Service Principal; Database=test; User Id=$env:CLIENTID; Password=$env:CLIENTSECRET;" | Select-Object -ExpandProperty ComputerName | Should -Be "dbatoolstest.database.windows.net"
    }

    It "gets a database from Azure" {
        $PSDefaultParameterValues.Clear()
        $securestring = ConvertTo-SecureString $env:CLIENTSECRET -AsPlainText -Force
        $azurecred = New-Object PSCredential -ArgumentList $env:CLIENTID, $securestring
        $server = Connect-DbaInstance -SqlInstance dbatoolstest.database.windows.net -SqlCredential $azurecred -Tenant $env:TENANTID
        (Get-DbaDatabase -SqlInstance $server -Database test).Name | Should -Be "test"
    }

    It "adds and gets a computer certificate" {
        # Create a self-signed certificate for testing
        $certSubject = "CN=DbaToolsTest-$(Get-Random)"
        $splatNewCert = @{
            Subject           = $certSubject
            CertStoreLocation = "Cert:\CurrentUser\My"
            KeyExportPolicy   = "Exportable"
            KeySpec           = "Signature"
            KeyLength         = 2048
            KeyAlgorithm      = "RSA"
            HashAlgorithm     = "SHA256"
            NotAfter          = (Get-Date).AddDays(1)
        }
        $testCert = New-SelfSignedCertificate @splatNewCert
        $testThumbprint = $testCert.Thumbprint

        # Export to PFX
        $tempPath = "/tmp/dbatools-cert-test-$(Get-Random).pfx"
        $pfxPassword = ConvertTo-SecureString -String "Test123!@#" -AsPlainText -Force
        $null = Export-PfxCertificate -Cert $testCert -FilePath $tempPath -Password $pfxPassword

        # Remove from CurrentUser store
        Remove-Item -Path "Cert:\CurrentUser\My\$testThumbprint" -ErrorAction SilentlyContinue

        # Import using Add-DbaComputerCertificate
        $splatImport = @{
            Path           = $tempPath
            SecurePassword = $pfxPassword
            Confirm        = $false
        }
        $addResult = Add-DbaComputerCertificate @splatImport
        $addResult.Thumbprint | Should -Contain $testThumbprint

        # Get certificate
        $getResult = Get-DbaComputerCertificate -Thumbprint $testThumbprint
        $getResult.Thumbprint | Should -Be $testThumbprint
        $getResult.Subject | Should -Be $certSubject

        # Cleanup
        Remove-DbaComputerCertificate -Thumbprint $testThumbprint -ErrorAction SilentlyContinue -Confirm:$false
        Remove-Item -Path $tempPath -ErrorAction SilentlyContinue
    }
}
