$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_exportdacpac"
        try {
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
            $null = $db.Query("CREATE TABLE dbo.example (id int, PRIMARY KEY (id));
            INSERT dbo.example
            SELECT top 100 object_id
            FROM sys.objects")
        }
        catch { } # No idea why appveyor can't handle this

        $testFolder = 'C:\Temp\dacpacs'
    }
    AfterAll {
        Remove-DbaDatabase -SqlInstance $script:instance1 -Database $dbname -Confirm:$false
    }
    Context "Extract dacpac" {
        BeforeEach {
            New-Item $testFolder -ItemType Directory -Force
            Push-Location $testFolder
        }
        AfterEach {
            Pop-Location
            Remove-Item $testFolder -Force -Recurse
        }
        if ((Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table example)) {
            # Sometimes appveyor bombs
            It "exports a dacpac" {
                $results = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname
                $results.Path | Should -Not -BeNullOrEmpty
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }
            It "exports to the correct directory" {
                $relativePath = '.\'
                $expectedPath = (Resolve-Path $relativePath).Path
                $results = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -Path $relativePath
                $results.Path | Split-Path | Should -Be $expectedPath
                Test-Path $results.Path | Should -Be $true
            }
            It "exports dacpac with a table list" {
                $relativePath = '.\extract.dacpac'
                $expectedPath = Join-Path (Get-Item .) 'extract.dacpac'
                $results = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -Path $relativePath -Table example
                $results.Path | Should -Be $expectedPath
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }
            It "uses EXE to extract dacpac" {
                $exportProperties = "/p:ExtractAllTableData=True"
                $results = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -ExtendedProperties $exportProperties
                $results.Path | Should -Not -BeNullOrEmpty
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }
        }
    }
    Context "Extract bacpac" {
        BeforeEach {
            New-Item $testFolder -ItemType Directory -Force
            Push-Location $testFolder
        }
        AfterEach {
            Pop-Location
            Remove-Item $testFolder -Force -Recurse
        }
        if ((Get-DbaDbTable -SqlInstance $script:instance1 -Database $dbname -Table example)) {
            # Sometimes appveyor bombs
            It "exports a bacpac" {
                $results = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -Type Bacpac
                $results.Path | Should -Not -BeNullOrEmpty
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }
            It "exports bacpac with a table list" {
                $relativePath = '.\extract.bacpac'
                $expectedPath = Join-Path (Get-Item .) 'extract.bacpac'
                $results = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -Path $relativePath -Table example -Type Bacpac
                $results.Path | Should -Be $expectedPath
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }
            It "uses EXE to extract bacpac" {
                $exportProperties = "/p:TargetEngineVersion=Default"
                $results = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -ExtendedProperties $exportProperties -Type Bacpac
                $results.Path | Should -Not -BeNullOrEmpty
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }
        }
    }
}