param($ModuleName = 'dbatools')

Describe "Export-DbaDacPackage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaDacPackage
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "AllUserDatabases",
                "Path",
                "FilePath",
                "DacOption",
                "ExtendedParameters",
                "ExtendedProperties",
                "Type",
                "Table",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Integration Tests" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $random = Get-Random
            $dbname = "dbatoolsci_exportdacpac_$random"
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $null = $server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname
            $null = $db.Query("CREATE TABLE dbo.example (id int, PRIMARY KEY (id));
            INSERT dbo.example
            SELECT top 100 object_id
            FROM sys.objects")

            $testFolder = 'C:\Temp\dacpacs'

            $dbName2 = "dbatoolsci:2_$random"
            $dbName2Escaped = "dbatoolsci`$2_$random"

            $null = New-DbaDatabase -SqlInstance $global:instance1 -Name $dbName2
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance1 -Database $dbname, $dbName2 -Confirm:$false
        }

        Context "Ensure the database name is part of the generated filename" {
            It "Database name is included in the output filename" {
                $result = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname
                $result.Path | Should -BeLike "*$($dbName)*"
            }

            It "Database names with invalid filesystem chars are successfully exported" {
                $result = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname, $dbName2
                $result.Path.Count | Should -Be 2
                $result.Path[0] | Should -BeLike "*$($dbName)*"
                $result.Path[1] | Should -BeLike "*$($dbName2Escaped)*"
            }
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

            It "exports a dacpac" -Skip:(-not (Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table example)) {
                $results = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname
                $results.Path | Should -Not -BeNullOrEmpty
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }

            It "exports to the correct directory" -Skip:(-not (Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table example)) {
                $relativePath = '.\'
                $expectedPath = (Resolve-Path $relativePath).Path
                $results = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname -Path $relativePath
                $results.Path | Split-Path | Should -Be $expectedPath
                Test-Path $results.Path | Should -Be $true
            }

            It "exports dacpac with a table list" -Skip:(-not (Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table example)) {
                $relativePath = '.\extract.dacpac'
                $expectedPath = Join-Path (Get-Item .) 'extract.dacpac'
                $results = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname -FilePath $relativePath -Table example
                $results.Path | Should -Be $expectedPath
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }

            It "uses EXE to extract dacpac" -Skip:(-not (Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table example)) {
                $exportProperties = "/p:ExtractAllTableData=True"
                $results = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname -ExtendedProperties $exportProperties
                $results.Path | Should -Not -BeNullOrEmpty
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
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

            It "exports a bacpac" -Skip:(-not (Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table example)) {
                $results = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname -Type Bacpac
                $results.Path | Should -Not -BeNullOrEmpty
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }

            It "exports bacpac with a table list" -Skip:(-not (Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table example)) {
                $relativePath = '.\extract.bacpac'
                $expectedPath = Join-Path (Get-Item .) 'extract.bacpac'
                $results = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname -FilePath $relativePath -Table example -Type Bacpac
                $results.Path | Should -Be $expectedPath
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }

            It "uses EXE to extract bacpac" -Skip:(-not (Get-DbaDbTable -SqlInstance $global:instance1 -Database $dbname -Table example)) {
                $exportProperties = "/p:TargetEngineVersion=Default"
                $results = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname -ExtendedProperties $exportProperties -Type Bacpac
                $results.Path | Should -Not -BeNullOrEmpty
                Test-Path $results.Path | Should -Be $true
                if (($results).Path) {
                    Remove-Item -Confirm:$false -Path ($results).Path -ErrorAction SilentlyContinue
                }
            }
        }
    }
}
