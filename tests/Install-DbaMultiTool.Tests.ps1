param($ModuleName = 'dbatools')

Describe "Install-DbaMultiTool" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Install-DbaMultiTool
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Branch parameter" {
            $CommandUnderTest | Should -HaveParameter Branch
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have LocalFile parameter" {
            $CommandUnderTest | Should -HaveParameter LocalFile
        }
        It "Should have Force parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Testing DBA MultiTool installer with download" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $branch = "main"
            $database = "dbatoolsci_multitool_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaMultiTool -SqlInstance $global:instance2 -Database $database -Branch $branch -Force -Verbose:$false
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
        It "Installed sp_doc, sp_helpme, sp_sizeoptimiser, and sp_estindex" {
            $resultsDownload.Name | Should -Contain 'sp_doc'
            $resultsDownload.Name | Should -Contain 'sp_helpme'
            $resultsDownload.Name | Should -Contain 'sp_sizeoptimiser'
            $resultsDownload.Name | Should -Contain 'sp_estindex'
        }
        It "Has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = 'SqlInstance', 'InstanceName', 'ComputerName', 'Name', 'Status', 'Database'
            $result.PsObject.Properties.Name | Should -Be $ExpectedProps
        }
        It "Shows status of Updated" {
            $resultsDownload = Install-DbaMultiTool -SqlInstance $global:instance2 -Database $database -Verbose:$false
            $resultsDownload[0].Status | Should -Be 'Updated'
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "dba-multitool-$branch"
            $sqlScript = Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1
            Add-Content $sqlScript.FullName (New-Guid).ToString()
            $result = Install-DbaMultiTool -SqlInstance $global:instance2 -Database $database -Verbose:$false
            $result = $result | Where-Object Name -eq $sqlScript.BaseName
            $result.Status | Should -Be "Error"
        }
    }

    Context "Testing DBA MultiTool installer with LocalFile" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $branch = "main"
            $database = "dbatoolsci_multitool_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $global:instance3
            $server.Query("CREATE DATABASE $database")

            $outfile = "dba-multitool-$branch.zip"
            Invoke-WebRequest -Uri "https://github.com/LowlyDBA/dba-multitool/archive/$branch.zip" -OutFile $outfile
            if (Test-Path $outfile) {
                $fullOutfile = (Get-ChildItem $outfile).FullName
            }
            $resultsLocalFile = Install-DbaMultiTool -SqlInstance $global:instance3 -Database $database -Branch $branch -LocalFile $fullOutfile -Force
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
        It "Installed sp_doc, sp_helpme, sp_sizeoptimiser, and sp_estindex" {
            $resultsLocalFile.Name | Should -Contain 'sp_doc'
            $resultsLocalFile.Name | Should -Contain 'sp_helpme'
            $resultsLocalFile.Name | Should -Contain 'sp_sizeoptimiser'
            $resultsLocalFile.Name | Should -Contain 'sp_estindex'
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = 'SqlInstance', 'InstanceName', 'ComputerName', 'Name', 'Status', 'Database'
            $result.PsObject.Properties.Name | Should -Be $ExpectedProps
        }
        It "Shows status of Updated" {
            $resultsLocalFile = Install-DbaMultiTool -SqlInstance $global:instance3 -Database $database
            $resultsLocalFile[0].Status | Should -Be 'Updated'
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "dba-multitool-$branch"
            $sqlScript = Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1
            Add-Content $sqlScript.FullName (New-Guid).ToString()
            $result = Install-DbaMultiTool -SqlInstance $global:instance3 -Database $database -Verbose:$false
            $result = $result | Where-Object Name -eq $sqlScript.BaseName
            $result.Status | Should -Be "Error"
        }
    }
}
