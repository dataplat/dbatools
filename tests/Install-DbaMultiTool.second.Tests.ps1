$CommandName = $MyInvocation.MyCommand.Name.Replace(".second.Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing DBA MultiTool installer with unsupported SQL Server version" {
        BeforeAll {
            $branch = "master"
            $database = "dbatoolsci_multitool_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $server.Query("CREATE DATABASE $database")

            $outfile = "DBA-MultiTool-$branch.zip"
            Invoke-WebRequest -Uri "https://github.com/LowlyDBA/dba-multitool/archive/$branch.zip" -OutFile $outfile
            if (Test-Path $outfile) {
                $fullOutfile = (Get-ChildItem $outfile).FullName
            }
            $resultsLocalFile = Install-DbaMultiTool -SqlInstance $script:instance1 -Database $database -Branch $branch -LocalFile $fullOutfile -Force
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance1 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsLocalFile[0].Database -eq $database | Should -Be $true
        }
        It "Shows status of Skipped" {
            $resultsLocalFile[0].Status -eq "Skipped" | Should -Be $true
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}