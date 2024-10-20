param($ModuleName = 'dbatools')

Describe "Install-DbaDarlingData" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Install-DbaDarlingData
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "Branch",
            "Procedure",
            "LocalFile",
            "Force",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Testing DarlingData installer with download" {
        BeforeAll {
            $database = "dbatoolsci_darling_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance3
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaDarlingData -SqlInstance $global:instance3 -Database $database -Branch main -Force -Verbose:$false
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance3 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsDownload[0].Database | Should -Be $database
        }
        It "Shows status of Installed" {
            $resultsDownload[0].Status | Should -Be "Installed"
        }
        It "has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = 'SqlInstance', 'InstanceName', 'ComputerName', 'Name', 'Status', 'Database'
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }

    Context "Testing DarlingData installer with LocalFile" {
        BeforeAll {
            $database = "dbatoolsci_darling_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance3
            $server.Query("CREATE DATABASE $database")

            $outfile = "DarlingData-main.zip"
            Invoke-WebRequest -Uri "https://github.com/erikdarlingdata/DarlingData/archive/main.zip" -OutFile $outfile
            if (Test-Path $outfile) {
                $fullOutfile = (Get-ChildItem $outfile).FullName
            }
            $resultsLocalFile = Install-DbaDarlingData -SqlInstance $global:instance3 -Database $database -Branch main -LocalFile $fullOutfile -Force
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance3 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsLocalFile[0].Database | Should -Be $database
        }
        It "Shows status of Installed" {
            $resultsLocalFile[0].Status | Should -Be "Installed"
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = 'SqlInstance', 'InstanceName', 'ComputerName', 'Name', 'Status', 'Database'
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}
