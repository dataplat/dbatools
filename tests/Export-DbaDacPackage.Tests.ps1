param($ModuleName = 'dbatools')

Describe "Export-DbaDacPackage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaDacPackage
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Not -Mandatory
        }
        It "Should have ExcludeDatabase as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type Object[] -Not -Mandatory
        }
        It "Should have AllUserDatabases as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter AllUserDatabases -Type Switch -Not -Mandatory
        }
        It "Should have Path as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Not -Mandatory
        }
        It "Should have FilePath as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type String -Not -Mandatory
        }
        It "Should have DacOption as a non-mandatory parameter of type Object" {
            $CommandUnderTest | Should -HaveParameter DacOption -Type Object -Not -Mandatory
        }
        It "Should have ExtendedParameters as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ExtendedParameters -Type String -Not -Mandatory
        }
        It "Should have ExtendedProperties as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ExtendedProperties -Type String -Not -Mandatory
        }
        It "Should have Type as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Type -Type String -Not -Mandatory
        }
        It "Should have Table as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Table -Type String[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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
