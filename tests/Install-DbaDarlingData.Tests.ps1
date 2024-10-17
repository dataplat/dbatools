param($ModuleName = 'dbatools')

Describe "Install-DbaDarlingData" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Install-DbaDarlingData
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object
        }
        It "Should have Branch as a parameter" {
            $CommandUnderTest | Should -HaveParameter Branch -Type String
        }
        It "Should have Procedure as a parameter" {
            $CommandUnderTest | Should -HaveParameter Procedure -Type String[]
        }
        It "Should have LocalFile as a parameter" {
            $CommandUnderTest | Should -HaveParameter LocalFile -Type String
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Testing DarlingData installer with download" {
        BeforeAll {
            $database = "dbatoolsci_darling_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $env:instance3
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaDarlingData -SqlInstance $env:instance3 -Database $database -Branch main -Force -Verbose:$false
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $env:instance3 -Database $database -Confirm:$false
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
            $server = Connect-DbaInstance -SqlInstance $env:instance3
            $server.Query("CREATE DATABASE $database")

            $outfile = "DarlingData-main.zip"
            Invoke-WebRequest -Uri "https://github.com/erikdarlingdata/DarlingData/archive/main.zip" -OutFile $outfile
            if (Test-Path $outfile) {
                $fullOutfile = (Get-ChildItem $outfile).FullName
            }
            $resultsLocalFile = Install-DbaDarlingData -SqlInstance $env:instance3 -Database $database -Branch main -LocalFile $fullOutfile -Force
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $env:instance3 -Database $database -Confirm:$false
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
