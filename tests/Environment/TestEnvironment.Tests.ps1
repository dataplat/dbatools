#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0"}
param(
    $ModuleName               = "dbatools",
    $TestConfig               = (Get-TestConfig),
    $PSDefaultParameterValues = $TestConfig.Defaults
)

BeforeDiscovery {
    $instance = $TestConfig.instance1, $TestConfig.instance2, $TestConfig.instance3
}

Describe "the temporary files" {
    It "Has no files in legacy temp folder" {
        Get-ChildItem -Path C:\Temp | Should -BeNullOrEmpty
    }

    It "Has no files in new temp folder" {
        Get-ChildItem -Path $TestConfig.Temp | Should -BeNullOrEmpty
    }
}

Describe "the instance <_>" -ForEach $instance {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $PSItem
        $netConf = Get-DbaNetworkConfiguration -SqlInstance $PSItem
        $agHadr = Get-DbaAgHadr -SqlInstance $PSItem
    }

    It "Has no user databases" {
        $userDatabaseNames = ($server.Databases | Where-Object Name -notin 'master', 'tempdb', 'model', 'msdb').Name
        $userDatabaseNames | Should -BeNullOrEmpty
    }

    It "Has no mirroring endpoints" {
        $mirroringEndpointNames = ($server.Endpoints | Where-Object EndpointType -eq DatabaseMirroring).Name
        $mirroringEndpointNames | Should -BeNullOrEmpty
    }

    It "Has named pipes enabled" {
        $netConf.NamedPipesEnabled | Should -BeTrue
    }

    It "Has the correct TCP port configured" {
        if ($PSItem -eq 'CLIENT') {
            $configTcpPort = 1433
        } elseif ($PSItem -eq 'CLIENT\SQLInstance2') {
            $configTcpPort = 14333
        } elseif ($PSItem -eq 'CLIENT\SQLInstance3') {
            $configTcpPort = 14334
        }

        ($netConf.TcpIpAddresses | Where-Object Name -eq IPAll).TcpPort | Should -Be $configTcpPort
    }

    It "Has the correct Hadr setting" {
        if ($PSItem -eq 'CLIENT') {
            $targeIsHadrEnabled = $false
        } elseif ($PSItem -eq 'CLIENT\SQLInstance2') {
            $targeIsHadrEnabled = $true
        } elseif ($PSItem -eq 'CLIENT\SQLInstance3') {
            $targeIsHadrEnabled = $true
        }

        $agHadr.IsHadrEnabled | Should -Be $targeIsHadrEnabled
    }

    It "Has a certificate (if needed)" {
        if ($PSItem -eq 'CLIENT\SQLInstance3') {
            $server.Databases['master'].Certificates | Where-Object Name -eq 'dbatoolsci_AGCert' | Should -Not -BeNullOrEmpty
        }
        if ($PSItem -ne 'CLIENT\SQLInstance3') {
            $server.Databases['master'].Certificates | Where-Object Name -eq 'dbatoolsci_AGCert' | Should -BeNullOrEmpty
        }
    }
}
