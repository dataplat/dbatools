$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Branch', 'Database', 'LocalFile', 'Force', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing DBA MultiTool installer with download" {
        BeforeAll {
            $branch = "main"
            $database = "dbatoolsci_multitool_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaMultiTool -SqlInstance $TestConfig.instance2 -Database $database -Branch $branch -Force -Verbose:$false
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsDownload[0].Database -eq $database | Should Be $true
        }
        It "Shows status of Installed" {
            $resultsDownload[0].Status -eq "Installed" | Should Be $true
        }
        It "Installed sp_doc, sp_helpme, sp_sizeoptimiser, and sp_estindex" {
            'sp_doc', 'sp_helpme', 'sp_sizeoptimiser', 'sp_estindex' | Should BeIn $resultsDownload.Name
        }
        It "Has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsDownload = Install-DbaMultiTool -SqlInstance $TestConfig.instance2 -Database $database -Verbose:$false
            $resultsDownload[0].Status -eq 'Updated' | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "dba-multitool-$branch"
            $sqlScript = Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1
            Add-Content $sqlScript.FullName (New-Guid).ToString()
            $result = Install-DbaMultiTool -SqlInstance $TestConfig.instance2 -Database $database -Verbose:$false
            $result = $result | Where-Object Name -eq $sqlScript.BaseName
            $result.Status -eq "Error" | Should -Be $true
        }
    }
    Context "Testing DBA MultiTool installer with LocalFile" {
        BeforeAll {
            $branch = "main"
            $database = "dbatoolsci_multitool_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $TestConfig.instance3
            $server.Query("CREATE DATABASE $database")

            $outfile = "dba-multitool-$branch.zip"
            Invoke-WebRequest -Uri "https://github.com/LowlyDBA/dba-multitool/archive/$branch.zip" -OutFile $outfile
            if (Test-Path $outfile) {
                $fullOutfile = (Get-ChildItem $outfile).FullName
            }
            $resultsLocalFile = Install-DbaMultiTool -SqlInstance $TestConfig.instance3 -Database $database -Branch $branch -LocalFile $fullOutfile -Force
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $TestConfig.instance3 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsLocalFile[0].Database -eq $database | Should -Be $true
        }
        It "Shows status of Installed" {
            $resultsLocalFile[0].Status -eq "Installed" | Should -Be $true
        }
        It "Installed sp_doc, sp_helpme, sp_sizeoptimiser, and sp_estindex" {
            'sp_doc', 'sp_helpme', 'sp_sizeoptimiser', 'sp_estindex' | Should -BeIn $resultsLocalFile.Name
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsLocalFile = Install-DbaMultiTool -SqlInstance $TestConfig.instance3 -Database $database
            $resultsLocalFile[0].Status -eq 'Updated' | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "dba-multitool-$branch"
            $sqlScript = Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1
            Add-Content $sqlScript.FullName (New-Guid).ToString()
            $result = Install-DbaMultiTool -SqlInstance $TestConfig.instance3 -Database $database -Verbose:$false
            $result = $result | Where-Object Name -eq $sqlScript.BaseName
            $result.Status -eq "Error" | Should -Be $true
        }
    }
}
