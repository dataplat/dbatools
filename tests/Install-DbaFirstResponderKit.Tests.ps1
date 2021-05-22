$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Branch', 'Database', 'LocalFile', 'OnlyScript', 'Force', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Testing First Responder Kit installer with download" {
        BeforeAll {
            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $server.Query("CREATE DATABASE $database")

            $resultsDownload = Install-DbaFirstResponderKit -SqlInstance $script:instance2 -Database $database -Branch main -Force -Verbose:$false
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
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            'sp_Blitz', 'sp_BlitzIndex' | Should BeIn $resultsDownload.Name
        }
        It "has the correct properties" {
            $result = $resultsDownload[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsDownload = Install-DbaFirstResponderKit -SqlInstance $script:instance2 -Database $database -Verbose:$false
            $resultsDownload[0].Status -eq 'Updated' | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "SQL-Server-First-Responder-Kit-main"
            $sqlScript = (Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1).FullName
            Add-Content $sqlScript (New-Guid).ToString()
            $result = Install-DbaFirstResponderKit -SqlInstance $script:instance2 -Database $database -Verbose:$false
            $result[0].Status -eq "Error" | Should -Be $true
        }
    }
    Context "Testing First Responder Kit installer with LocalFile" {
        BeforeAll {
            $database = "dbatoolsci_frk_$(Get-Random)"
            $server = Connect-DbaInstance -SqlInstance $script:instance3
            $server.Query("CREATE DATABASE $database")

            $outfile = "SQL-Server-First-Responder-Kit-main.zip"
            Invoke-WebRequest -Uri "https://github.com/BrentOzarULTD/SQL-Server-First-Responder-Kit/archive/main.zip" -OutFile $outfile
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
        It "At least installed sp_Blitz and sp_BlitzIndex" {
            'sp_Blitz', 'sp_BlitzIndex' | Should BeIn $resultsLocalFile.Name
        }
        It "Has the correct properties" {
            $result = $resultsLocalFile[0]
            $ExpectedProps = 'SqlInstance,InstanceName,ComputerName,Name,Status,Database'.Split(',')
            ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
        It "Shows status of Updated" {
            $resultsLocalFile = Install-DbaFirstResponderKit -SqlInstance $script:instance3 -Database $database
            $resultsLocalFile[0].Status -eq 'Updated' | Should -Be $true
        }
        It "Shows status of Error" {
            $folder = Join-Path (Get-DbatoolsConfigValue -FullName Path.DbatoolsData) -Child "SQL-Server-First-Responder-Kit-main"
            $sqlScript = (Get-ChildItem $folder -Filter "sp_*.sql" | Select-Object -First 1).FullName
            Add-Content $sqlScript (New-Guid).ToString()
            $result = Install-DbaFirstResponderKit -SqlInstance $script:instance3 -Database $database
            $result[0].Status -eq "Error" | Should -Be $true
        }
    }
}