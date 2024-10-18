param($ModuleName = 'dbatools')

Describe "Publish-DbaDacPackage" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Publish-DbaDacPackage
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Path parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String
        }
        It "Should have PublishXml parameter" {
            $CommandUnderTest | Should -HaveParameter PublishXml -Type System.String
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.String[]
        }
        It "Should have ConnectionString parameter" {
            $CommandUnderTest | Should -HaveParameter ConnectionString -Type System.String[]
        }
        It "Should have GenerateDeploymentReport parameter" {
            $CommandUnderTest | Should -HaveParameter GenerateDeploymentReport -Type System.Management.Automation.SwitchParameter
        }
        It "Should have ScriptOnly parameter" {
            $CommandUnderTest | Should -HaveParameter ScriptOnly -Type System.Management.Automation.SwitchParameter
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type System.String
        }
        It "Should have OutputPath parameter" {
            $CommandUnderTest | Should -HaveParameter OutputPath -Type System.String
        }
        It "Should have IncludeSqlCmdVars parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSqlCmdVars -Type System.Management.Automation.SwitchParameter
        }
        It "Should have DacOption parameter" {
            $CommandUnderTest | Should -HaveParameter DacOption -Type Object
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
        }
        It "Should have DacFxPath parameter" {
            $CommandUnderTest | Should -HaveParameter DacFxPath -Type System.String
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $dbname = "dbatoolsci_publishdacpac"
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $null = $server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $global:instance1 -Database $dbname
            $null = $db.Query("CREATE TABLE dbo.example (id int, PRIMARY KEY (id));
                INSERT dbo.example
                SELECT top 100 object_id
                FROM sys.objects")
            $publishprofile = New-DbaDacProfile -SqlInstance $global:instance1 -Database $dbname -Path C:\temp
        }

        AfterAll {
            Remove-DbaDatabase -SqlInstance $global:instance1, $global:instance2 -Database $dbname -Confirm:$false
            Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
        }

        AfterEach {
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
        }

        Context "Dacpac tests" {
            BeforeAll {
                $extractOptions = New-DbaDacOption -Action Export
                $extractOptions.ExtractAllTableData = $true
                $dacpac = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname -DacOption $extractOptions
            }

            AfterAll {
                if ($dacpac.Path) { Remove-Item -Confirm:$false -Path $dacpac.Path -ErrorAction SilentlyContinue }
            }

            It "Performs an xml-based deployment" {
                $results = $dacpac | Publish-DbaDacPackage -PublishXml $publishprofile.FileName -Database $dbname -SqlInstance $global:instance2 -Confirm:$false
                $results.Result | Should -BeLike '*Update complete.*'
                $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $global:instance2 -Query 'SELECT id FROM dbo.example'
                $ids.id | Should -Not -BeNullOrEmpty
            }

            It "Performs an SMO-based deployment" {
                $options = New-DbaDacOption -Action Publish
                $results = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $global:instance2 -Confirm:$false
                $results.Result | Should -BeLike '*Update complete.*'
                $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $global:instance2 -Query 'SELECT id FROM dbo.example'
                $ids.id | Should -Not -BeNullOrEmpty
            }

            It "Performs an SMO-based deployment and generates a deployment report" {
                $options = New-DbaDacOption -Action Publish
                $results = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $global:instance2 -GenerateDeploymentReport -Confirm:$false
                $results.Result | Should -BeLike '*Update complete.*'
                $results.DeploymentReport | Should -Not -BeNullOrEmpty
                $deploymentReportContent = Get-Content -Path $results.DeploymentReport
                $deploymentReportContent | Should -BeLike '*DeploymentReport*'
                $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $global:instance2 -Query 'SELECT id FROM dbo.example'
                $ids.id | Should -Not -BeNullOrEmpty
            }

            It "Performs a script generation without deployment" {
                $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $global:instance2 -ScriptOnly -PublishXml $publishprofile.FileName -Confirm:$false
                $results.Result | Should -BeLike '*Reporting and scripting deployment plan (Complete)*'
                $results.DatabaseScriptPath | Should -Not -BeNullOrEmpty
                Test-Path ($results.DatabaseScriptPath) | Should -Be $true
                Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Should -BeNullOrEmpty
                Remove-Item $results.DatabaseScriptPath
            }

            It "Performs a script generation without deployment and using an input options object" {
                $opts = New-DbaDacOption -Action Publish
                $opts.GenerateDeploymentScript = $true
                $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $global:instance2 -DacOption $opts -Confirm:$false
                $results.Result | Should -BeLike '*Reporting and scripting deployment plan (Complete)*'
                $results.DatabaseScriptPath | Should -Not -BeNullOrEmpty
                Test-Path ($results.DatabaseScriptPath) | Should -Be $true
                Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Should -BeNullOrEmpty
                Remove-Item $results.DatabaseScriptPath
            }

            It "Performs a script generation using custom path" {
                $opts = New-DbaDacOption -Action Publish -Property @{
                    GenerateDeploymentScript = $true
                    DatabaseScriptPath       = 'C:\Temp\testdb.sql'
                }
                $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $global:instance2 -DacOption $opts -Confirm:$false
                $results.Result | Should -BeLike '*Reporting and scripting deployment plan (Complete)*'
                $results.DatabaseScriptPath | Should -Be 'C:\Temp\testdb.sql'
                Test-Path ($results.DatabaseScriptPath) | Should -Be $true
                Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname | Should -BeNullOrEmpty
                Remove-Item $results.DatabaseScriptPath
            }
        }

        Context "Bacpac tests" {
            BeforeAll {
                $extractOptions = New-DbaDacOption -Action Export -Type Bacpac
                $bacpac = Export-DbaDacPackage -SqlInstance $global:instance1 -Database $dbname -DacOption $extractOptions -Type Bacpac
            }

            AfterAll {
                if ($bacpac.Path) { Remove-Item -Confirm:$false -Path $bacpac.Path -ErrorAction SilentlyContinue }
            }

            It "Performs an SMO-based deployment" {
                $options = New-DbaDacOption -Action Publish -Type Bacpac
                $results = $bacpac | Publish-DbaDacPackage -Type Bacpac -DacOption $options -Database $dbname -SqlInstance $global:instance2 -Confirm:$false
                $results.Result | Should -BeLike '*Updating database (Complete)*'
                $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $global:instance2 -Query 'SELECT id FROM dbo.example'
                $ids.id | Should -Not -BeNullOrEmpty
            }

            It "Auto detects that a .bacpac is being used and sets the Type to Bacpac" {
                $options = New-DbaDacOption -Action Publish -Type Bacpac
                $results = $bacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $global:instance2 -Confirm:$false
                $results.Result | Should -BeLike '*Updating database (Complete)*'
                $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $global:instance2 -Query 'SELECT id FROM dbo.example'
                $ids.id | Should -Not -BeNullOrEmpty
            }

            It "Should throw when ScriptOnly is used" {
                { $bacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $global:instance2 -ScriptOnly -Type Bacpac -EnableException -Confirm:$false } | Should -Throw
            }
        }
    }
}
