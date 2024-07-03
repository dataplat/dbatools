$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Branch', 'Database', 'LocalFile', 'Procedure', 'Force', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing DarlingData installer with download" {
        BeforeAll {
            $database = "dbatoolsci_darling_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance3
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaDarlingData -SqlInstance $script:instance3 -Database $database -Branch main -Force -Verbose:$false
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance3 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsDownload[0].Database | Should -Be $database
        }
        It "Shows status of Installed" {
            $resultsDownload[0].Status | Should -Be "Installed"
        }
        It "has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
    Context "Testing DarlingData installer with LocalFile" {
        BeforeAll {
            $database = "dbatoolsci_darling_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance3
            $server.Query("CREATE DATABASE $database")

            $outfile = "DarlingData-main.zip"
            Invoke-WebRequest -Uri "https://github.com/erikdarlingdata/DarlingData/archive/main.zip" -OutFile $outfile
            if (Test-Path $outfile) {
                $fullOutfile = (Get-ChildItem $outfile).FullName
            }
            $resultsLocalFile = Install-DbaDarlingData -SqlInstance $script:instance3 -Database $database -Branch main -LocalFile $fullOutfile  -Force
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance3 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsLocalFile[0].Database | Should -Be $database
        }
        It "Shows status of Installed" {
            $resultsLocalFile[0].Status | Should -Be "Installed"
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}