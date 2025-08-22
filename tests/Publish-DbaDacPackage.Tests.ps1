#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Publish-DbaDacPackage",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "PublishXml",
                "Database",
                "ConnectionString",
                "GenerateDeploymentReport",
                "ScriptOnly",
                "Type",
                "OutputPath",
                "IncludeSqlCmdVars",
                "DacOption",
                "EnableException",
                "DacFxPath"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Check if SqlPackage is available since Export-DbaDacPackage is used in these tests
        $sqlPackagePath = Get-DbaSqlPackagePath
        if (-not $sqlPackagePath) {
            Write-Warning "SqlPackage.exe not found. Attempting to install..."
            try {
                Install-DbaSqlPackage -ErrorAction Stop
                $sqlPackagePath = Get-DbaSqlPackagePath
                if (-not $sqlPackagePath) {
                    throw "SqlPackage installation failed"
                }
                Write-Host "SqlPackage installed successfully" -ForegroundColor Green
            } catch {
                Write-Warning "Could not install SqlPackage. Tests will be skipped. Error: $_"
                return
            }
        } else {
            Write-Host "SqlPackage found at: $sqlPackagePath" -ForegroundColor Green
        }

        Get-DbaProcess -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Program "dbatools PowerShell module - dbatools.io" | Stop-DbaProcess -WarningAction SilentlyContinue
        $dbname = "dbatoolsci_publishdacpac"
        $splatConnection = @{
            SqlInstance = $TestConfig.instance1
        }
        $server = Connect-DbaInstance @splatConnection
        $null = $server.Query("Create Database [$dbname]")
        $db = Get-DbaDatabase -SqlInstance $TestConfig.instance1 -Database $dbname
        $null = $db.Query("CREATE TABLE dbo.example (id int, PRIMARY KEY (id));
            INSERT dbo.example
            SELECT top 100 object_id
            FROM sys.objects")
        $publishprofile = New-DbaDacProfile -SqlInstance $TestConfig.instance1 -Database $dbname -Path C:\temp

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.instance1, $TestConfig.instance2 -Database $dbname -Confirm:$false
        Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false
    }
    Context "Dacpac tests" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export
            $extractOptions.ExtractAllTableData = $true
            $dacpac = Export-DbaDacPackage -SqlInstance $TestConfig.instance1 -Database $dbname -DacOption $extractOptions
        }

        AfterAll {
            if ($dacpac.Path) { Remove-Item -Confirm:$false -Path $dacpac.Path -ErrorAction SilentlyContinue }
        }

        It "Performs an xml-based deployment" {
            $results = $dacpac | Publish-DbaDacPackage -PublishXml $publishprofile.FileName -Database $dbname -SqlInstance $TestConfig.instance2 -Confirm:$false
            $results.Result | Should -BeLike "*Update complete.*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.instance2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Performs an SMO-based deployment" {
            $options = New-DbaDacOption -Action Publish
            $results = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.instance2 -Confirm:$false
            $results.Result | Should -BeLike "*Update complete.*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.instance2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Performs an SMO-based deployment and generates a deployment report" {
            $options = New-DbaDacOption -Action Publish
            $results = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.instance2 -GenerateDeploymentReport -Confirm:$false
            $results.Result | Should -BeLike "*Update complete.*"
            $results.DeploymentReport | Should -Not -BeNullOrEmpty
            $deploymentReportContent = Get-Content -Path $results.DeploymentReport
            $deploymentReportContent | Should -BeLike "*DeploymentReport*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.instance2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Performs a script generation without deployment" {
            $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.instance2 -ScriptOnly -PublishXml $publishprofile.FileName -Confirm:$false
            $results.Result | Should -BeLike "*Reporting and scripting deployment plan (Complete)*"
            $results.DatabaseScriptPath | Should -Not -BeNullOrEmpty
            Test-Path ($results.DatabaseScriptPath) | Should -Be $true
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname | Should -BeNullOrEmpty
            Remove-Item $results.DatabaseScriptPath
        }

        It "Performs a script generation without deployment and using an input options object" {
            $opts = New-DbaDacOption -Action Publish
            $opts.GenerateDeploymentScript = $true
            $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.instance2 -DacOption $opts -Confirm:$false
            $results.Result | Should -BeLike "*Reporting and scripting deployment plan (Complete)*"
            $results.DatabaseScriptPath | Should -Not -BeNullOrEmpty
            Test-Path ($results.DatabaseScriptPath) | Should -Be $true
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname | Should -BeNullOrEmpty
            Remove-Item $results.DatabaseScriptPath
        }

        It "Performs a script generation using custom path" {
            $splatOption = @{
                Action   = "Publish"
                Property = @{
                    GenerateDeploymentScript = $true
                    DatabaseScriptPath       = "C:\Temp\testdb.sql"
                }
            }
            $opts = New-DbaDacOption @splatOption
            $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.instance2 -DacOption $opts -Confirm:$false
            $results.Result | Should -BeLike "*Reporting and scripting deployment plan (Complete)*"
            $results.DatabaseScriptPath | Should -Be "C:\Temp\testdb.sql"
            Test-Path ($results.DatabaseScriptPath) | Should -Be $true
            Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname | Should -BeNullOrEmpty
            Remove-Item $results.DatabaseScriptPath
        }
    }
    Context "Bacpac tests" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export -Type Bacpac
            $bacpac = Export-DbaDacPackage -SqlInstance $TestConfig.instance1 -Database $dbname -DacOption $extractOptions -Type Bacpac
        }

        AfterAll {
            if ($bacpac.Path) { Remove-Item -Confirm:$false -Path $bacpac.Path -ErrorAction SilentlyContinue }
        }

        It "Performs an SMO-based deployment" {
            $options = New-DbaDacOption -Action Publish -Type Bacpac
            $results = $bacpac | Publish-DbaDacPackage -Type Bacpac -DacOption $options -Database $dbname -SqlInstance $TestConfig.instance2 -Confirm:$false
            $results.Result | Should -BeLike "*Updating database (Complete)*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.instance2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Auto detects that a .bacpac is being used and sets the Type to Bacpac" {
            $options = New-DbaDacOption -Action Publish -Type Bacpac
            $results = $bacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.instance2 -Confirm:$false
            $results.Result | Should -BeLike "*Updating database (Complete)*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.instance2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Should throw when ScriptOnly is used" {
            { $bacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.instance2 -ScriptOnly -Type Bacpac -EnableException -Confirm:$false } | Should -Throw
        }
    }
}