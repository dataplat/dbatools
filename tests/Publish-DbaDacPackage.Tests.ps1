$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

if (-not $env:appveyor) {
    Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $script:instance1, $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $dbname = "dbatoolsci_publishdacpac"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
			$null = $db.Query("CREATE TABLE dbo.example (id int, PRIMARY KEY (id));
                INSERT dbo.example
                SELECT top 100 object_id
                FROM sys.objects")
            $publishprofile = New-DbaDacProfile -SqlInstance $script:instance1 -Database $dbname -Path C:\temp
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance1, $script:instance2 -Database $dbname -Confirm:$false
            Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
            if (Test-Path $dacpac.Path) {
                Remove-Item -Confirm:$false -Path ($dacpac).Path -ErrorAction SilentlyContinue
            }
        }
        AfterEach {
            Remove-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Confirm:$false
        }
        Context "Dacpac tests" {
            BeforeAll {
                $extractOptions = New-DbaDacOption -Action Export
                $extractOptions.ExtractAllTableData = $true
                $dacpac = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -DacOption $extractOptions
            }
            It "Performs an xml-based deployment" {
                $results = $dacpac | Publish-DbaDacPackage -PublishXml $publishprofile.FileName -Database $dbname -SqlInstance $script:instance2
                $results.Result -match 'Update complete.' | Should Be $true
                $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $script:instance2 -Query 'SELECT id FROM dbo.example'
                $ids.id | Should -Not -BeNullOrEmpty
            }
            It "Performs an SMO-based deployment" {
                $options = New-DbaDacOption -Action Publish
                $results = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $script:instance2
                $results.Result -match 'Update complete.' | Should Be $true
                $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $script:instance2 -Query 'SELECT id FROM dbo.example'
                $ids.id | Should -Not -BeNullOrEmpty
            }
        }
        Context "Bacpac tests" {
            BeforeAll {
                $extractOptions = New-DbaDacOption -Action Export -Type Bacpac
                $bacpac = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -DacOption $extractOptions -Type Bacpac
            }
            It "Performs an SMO-based deployment" {
                $options = New-DbaDacOption -Action Publish -Type Bacpac
                $results = $bacpac | Publish-DbaDacPackage -Type Bacpac -DacOption $options -Database $dbname -SqlInstance $script:instance2
                $results.Result -match 'Updating database \(Complete\)' | Should Be $true
                $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $script:instance2 -Query 'SELECT id FROM dbo.example'
                $ids.id | Should -Not -BeNullOrEmpty
            }
        }
    }
}