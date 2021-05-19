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
            $database = "dbatoolsci_dd_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaDarlingData -SqlInstance $script:instance2 -Database $database -Branch master -Force -Verbose:$false
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsDownload[0].Database -eq $database | Should Be $true
        }
        It "Shows status of Installed" {
            $resultsDownload[0].Status -eq "Installed" | Should Be $true
        }
        It "At least installed sp_humanevents and sp_pressuredetector" {
            'sp_humanevents', 'sp_pressuredetector' | Should BeIn $resultsDownload.Name
        }
        It "has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsDownload = Install-DbaDarlingData -SqlInstance $script:instance2 -Database $database -Verbose:$false
            $resultsDownload[0].Status -eq 'Updated' | Should -Be $true
        }
    }
    Context "Testing First Responder Kit installer with LocalFile" {
        BeforeAll {
            $database = "dbatoolsci_dd_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance3
            $server.Query("CREATE DATABASE $database")

            $outfile = "DarlingData-master.zip"
            Invoke-WebRequest -Uri "https://github.com/erikdarlingdata/DarlingData/archive/master.zip" -OutFile $outfile
            if (Test-Path $outfile) {
                $fullOutfile = (Get-ChildItem $outfile).FullName
            }
            $resultsLocalFile = Install-DbaFirstResponderKit -SqlInstance $script:instance3 -Database $database -Branch main -LocalFile $fullOutfile  -Force
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance3 -Database $database -Confirm:$false
        }

        It "Installs to specified database: $database" {
            $resultsLocalFile[0].Database -eq $database | Should -Be $true
        }
        It "Shows status of Installed" {
            $resultsLocalFile[0].Status -eq "Installed" | Should -Be $true
        }
        It "At least installed sp_humanevents and sp_pressuredetector" {
            'sp_humanevents', 'sp_pressuredetector' | Should BeIn $resultsLocalFile.Name
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsLocalFile = Install-DbaDarlingData -SqlInstance $script:instance3 -Database $database
            $resultsLocalFile[0].Status -eq 'Updated' | Should -Be $true
        }
    }
}