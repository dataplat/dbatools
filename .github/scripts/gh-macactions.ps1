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
        # Create a self-signed certificate using openssl for cross-platform compatibility
        $certSubject = "DbaToolsTest-$(Get-Random)"
        $tempCertPath = "/tmp/dbatools-cert-test-$(Get-Random).pem"
        $tempKeyPath = "/tmp/dbatools-cert-key-$(Get-Random).pem"
        $tempPfxPath = "/tmp/dbatools-cert-test-$(Get-Random).pfx"
        $pfxPassword = "Test123!@#"

        # Generate private key and self-signed certificate using openssl
        $null = & openssl req -x509 -newkey rsa:2048 -keyout $tempKeyPath -out $tempCertPath -days 1 -nodes -subj "/CN=$certSubject" 2>&1

        # Convert to PFX format (PKCS12) which includes private key
        $null = & openssl pkcs12 -export -out $tempPfxPath -inkey $tempKeyPath -in $tempCertPath -password "pass:$pfxPassword" 2>&1

        # Import using Add-DbaComputerCertificate
        $splatImport = @{
            Path           = $tempPfxPath
            SecurePassword = (ConvertTo-SecureString -String $pfxPassword -AsPlainText -Force)
            Confirm        = $false
        }
        $addResult = Add-DbaComputerCertificate @splatImport
        $testThumbprint = $addResult.Thumbprint

        # Get certificate
        $getResult = Get-DbaComputerCertificate -Thumbprint $testThumbprint
        $getResult.Thumbprint | Should -Be $testThumbprint
        $getResult.Subject | Should -Match $certSubject

        # Cleanup
        Remove-DbaComputerCertificate -Thumbprint $testThumbprint -ErrorAction SilentlyContinue -Confirm:$false
        Remove-Item -Path $tempCertPath, $tempKeyPath, $tempPfxPath -ErrorAction SilentlyContinue
    }
}
