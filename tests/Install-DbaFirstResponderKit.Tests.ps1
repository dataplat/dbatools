param($ModuleName = 'dbatools')

Describe "Install-DbaFirstResponderKit" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Install-DbaFirstResponderKit
        }

        It "has the required parameter: <_>" -ForEach @(
            "SqlInstance",
            "SqlCredential",
            "Branch",
            "Database",
            "LocalFile",
            "OnlyScript",
            "Force",
            "EnableException"
        ) {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Testing First Responder Kit installer with download" {
        BeforeAll {
            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaFirstResponderKit -SqlInstance $global:instance2 -Database $database -Branch main -Force -Verbose:$false
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsDownload[0].Database | Should -Be $database
        }
        It "Shows status of Installed" {
            $resultsDownload[0].Status | Should -Be "Installed"
        }
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            $resultsDownload.Name | Should -Contain 'sp_Blitz'
            $resultsDownload.Name | Should -Contain 'sp_BlitzIndex'
        }
        It "has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = 'SqlInstance', 'InstanceName', 'ComputerName', 'Name', 'Status', 'Database'
            $result.PsObject.Properties.Name | Should -Be $ExpectedProps
        }
        It "Shows status of Updated" {
            $resultsDownload = Install-DbaFirstResponderKit -SqlInstance $global:instance2 -Database $database -Verbose:$false
            $resultsDownload[0].Status | Should -Be 'Updated'
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "SQL-Server-First-Responder-Kit-main"
            $sqlScript = (Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1).FullName
            Add-Content $sqlScript (New-Guid).ToString()
            $result = Install-DbaFirstResponderKit -SqlInstance $global:instance2 -Database $database -Verbose:$false
            $result[0].Status | Should -Be "Error"
        }
    }

    Context "Testing First Responder Kit installer with LocalFile" {
        BeforeAll {
            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance3
            $server.Query("CREATE DATABASE $database")

            $outfile = "SQL-Server-First-Responder-Kit-main.zip"
            Invoke-WebRequest -Uri "https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/main.zip" -OutFile $outfile
            if (Test-Path $outfile) {
                $fullOutfile = (Get-ChildItem $outfile).FullName
            }
            $resultsLocalFile = Install-DbaFirstResponderKit -SqlInstance $global:instance3 -Database $database -Branch main -LocalFile $fullOutfile -Force
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
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            $resultsLocalFile.Name | Should -Contain 'sp_Blitz'
            $resultsLocalFile.Name | Should -Contain 'sp_BlitzIndex'
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = 'SqlInstance', 'InstanceName', 'ComputerName', 'Name', 'Status', 'Database'
            $result.PsObject.Properties.Name | Should -Be $ExpectedProps
        }
        It "Shows status of Updated" {
            $resultsLocalFile = Install-DbaFirstResponderKit -SqlInstance $global:instance3 -Database $database
            $resultsLocalFile[0].Status | Should -Be 'Updated'
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "SQL-Server-First-Responder-Kit-main"
            $sqlScript = (Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1).FullName
            Add-Content $sqlScript (New-Guid).ToString()
            $result = Install-DbaFirstResponderKit -SqlInstance $global:instance3 -Database $database
            $result[0].Status | Should -Be "Error"
        }
    }
}
