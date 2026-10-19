#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaEndpoint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Name",
                "Type",
                "Protocol",
                "Role",
                "EndpointEncryption",
                "EncryptionAlgorithm",
                "AuthenticationOrder",
                "Certificate",
                "IPAddress",
                "Port",
                "SslPort",
                "Owner",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $endpointName = "dbatoolsci_MirroringEndpoint"
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceMulti1, $TestConfig.InstanceMulti2 -EndPoint $endpointName

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When creating database mirroring endpoints" {
        BeforeAll {
            $results = New-DbaEndpoint -SqlInstance $TestConfig.InstanceMulti1 -Type DatabaseMirroring -Role Partner -Name $endpointName | Start-DbaEndpoint
        }

        It "creates an endpoint of the db mirroring type" {
            $results.EndpointType | Should -Be "DatabaseMirroring"
        }

        It "creates it with the right owner" {
            $sa = Get-SaLoginName -SqlInstance $TestConfig.InstanceMulti1
            $results.Owner | Should -Be $sa
        }
    }

    Context "When creating a database mirroring endpoint with certificate authentication" {
        BeforeAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # An instance has only one database mirroring endpoint, so this one goes to the second instance.
            # The certificate needs a master key in master, which is only created if the instance has none.
            # The $1 in the name is legal in an identifier and was taken for a group of the regex that puts the
            # certificate into the script, which then named a certificate that does not exist.
            $certificateName = "dbatoolsci_endpointcert`$1"
            $certServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2
            $masterKeyCreated = $false
            if (-not $certServer.Databases["master"].MasterKey) {
                $masterKeyPassword = ConvertTo-SecureString -String "dbatools.IO" -AsPlainText -Force
                $null = New-DbaDbMasterKey -SqlInstance $certServer -Database master -SecurePassword $masterKeyPassword
                $masterKeyCreated = $true
            }
            $null = New-DbaDbCertificate -SqlInstance $certServer -Database master -Name $certificateName -Subject $certificateName

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

            $splatCertEndpoint = @{
                SqlInstance = $TestConfig.InstanceMulti2
                Type        = "DatabaseMirroring"
                Role        = "Partner"
                Name        = $endpointName
                Certificate = $certificateName
            }
            $certResults = New-DbaEndpoint @splatCertEndpoint
        }

        AfterAll {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            # The endpoint uses the certificate, so it goes first
            $null = Remove-DbaEndpoint -SqlInstance $TestConfig.InstanceMulti2 -EndPoint $endpointName
            $null = Remove-DbaDbCertificate -SqlInstance $TestConfig.InstanceMulti2 -Database master -Certificate $certificateName
            if ($masterKeyCreated) {
                $null = Remove-DbaDbMasterKey -SqlInstance $TestConfig.InstanceMulti2 -Database master
            }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "returns only the new endpoint" {
            # Counts the output itself, $certResults.Name would skip a $null written by the command
            @($certResults).Count | Should -Be 1
            $certResults.Name | Should -Be $endpointName
        }

        It "authenticates with the certificate" {
            $authentication = $certServer.Query("SELECT c.name FROM sys.database_mirroring_endpoints AS e JOIN master.sys.certificates AS c ON c.certificate_id = e.certificate_id WHERE e.name = N'$endpointName'")
            $authentication.name | Should -Be $certificateName
        }
    }
}