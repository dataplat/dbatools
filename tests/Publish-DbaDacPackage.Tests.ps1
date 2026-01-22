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

        $null = Install-DbaSqlPackage

        $dbname = "dbatoolsci_publishdacpac"
        $db = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $dbname
        $null = $db.Query("CREATE TABLE dbo.example (id int, PRIMARY KEY (id));
            INSERT dbo.example
            SELECT top 100 object_id
            FROM sys.objects")
        $publishprofile = New-DbaDacProfile -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -Path $TestConfig.Temp

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbname
        Remove-Item -Path $publishprofile.FileName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $dbname
    }
    Context "Dacpac tests" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export
            $extractOptions.ExtractAllTableData = $true
            $dacpac = Export-DbaDacPackage -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -DacOption $extractOptions
        }

        AfterAll {
            if ($dacpac.Path) { Remove-Item -Path $dacpac.Path -ErrorAction SilentlyContinue }
        }

        It "Performs an xml-based deployment" {
            $results = $dacpac | Publish-DbaDacPackage -PublishXml $publishprofile.FileName -Database $dbname -SqlInstance $TestConfig.InstanceCopy2
            $results.Result | Should -BeLike "*Update complete.*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Performs an SMO-based deployment" {
            $options = New-DbaDacOption -Action Publish
            $results = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2
            $results.Result | Should -BeLike "*Update complete.*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Performs an SMO-based deployment and generates a deployment report" {
            $options = New-DbaDacOption -Action Publish
            $results = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -GenerateDeploymentReport
            $results.Result | Should -BeLike "*Update complete.*"
            $results.DeploymentReport | Should -Not -BeNullOrEmpty
            $deploymentReportContent = Get-Content -Path $results.DeploymentReport
            $deploymentReportContent | Should -BeLike "*DeploymentReport*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Performs a script generation without deployment" {
            $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -ScriptOnly -PublishXml $publishprofile.FileName
            $results.Result | Should -BeLike "*Reporting and scripting deployment plan (Complete)*"
            $results.DatabaseScriptPath | Should -Not -BeNullOrEmpty
            Test-Path ($results.DatabaseScriptPath) | Should -Be $true
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $dbname | Should -BeNullOrEmpty
            Remove-Item $results.DatabaseScriptPath
        }

        It "Performs a script generation without deployment and using an input options object" {
            $opts = New-DbaDacOption -Action Publish
            $opts.GenerateDeploymentScript = $true
            $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -DacOption $opts
            $results.Result | Should -BeLike "*Reporting and scripting deployment plan (Complete)*"
            $results.DatabaseScriptPath | Should -Not -BeNullOrEmpty
            Test-Path ($results.DatabaseScriptPath) | Should -Be $true
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $dbname | Should -BeNullOrEmpty
            Remove-Item $results.DatabaseScriptPath
        }

        It "Performs a script generation using custom path" {
            $splatOption = @{
                Action   = "Publish"
                Property = @{
                    GenerateDeploymentScript = $true
                    DatabaseScriptPath       = "$($TestConfig.Temp)\testdb.sql"
                }
            }
            $opts = New-DbaDacOption @splatOption
            $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -DacOption $opts
            $results.Result | Should -BeLike "*Reporting and scripting deployment plan (Complete)*"
            $results.DatabaseScriptPath | Should -Be "$($TestConfig.Temp)\testdb.sql"
            Test-Path ($results.DatabaseScriptPath) | Should -Be $true
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $dbname | Should -BeNullOrEmpty
            Remove-Item $results.DatabaseScriptPath
        }
    }
    Context "Bacpac tests" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export -Type Bacpac
            $bacpac = Export-DbaDacPackage -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -DacOption $extractOptions -Type Bacpac
        }

        AfterAll {
            if ($bacpac.Path) { Remove-Item -Path $bacpac.Path -ErrorAction SilentlyContinue }
        }

        It "Performs an SMO-based deployment" {
            $options = New-DbaDacOption -Action Publish -Type Bacpac
            $results = $bacpac | Publish-DbaDacPackage -Type Bacpac -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2
            $results.Result | Should -BeLike "*Updating database (Complete)*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Auto detects that a .bacpac is being used and sets the Type to Bacpac" {
            $options = New-DbaDacOption -Action Publish -Type Bacpac
            $results = $bacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2
            $results.Result | Should -BeLike "*Updating database (Complete)*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Should throw when ScriptOnly is used" {
            { $bacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -ScriptOnly -Type Bacpac -EnableException } | Should -Throw
        }
    }

    Context "Output Validation - Dacpac" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export
            $extractOptions.ExtractAllTableData = $true
            $dacpac = Export-DbaDacPackage -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -DacOption $extractOptions
            $result = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        }

        AfterAll {
            if ($dacpac.Path) { Remove-Item -Path $dacpac.Path -ErrorAction SilentlyContinue }
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $dbname -Confirm:$false
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties for Dacpac deployment" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Dacpac",
                "PublishXml",
                "Result",
                "DeployOptions",
                "SqlCmdVariableValues"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }

    Context "Output Validation - Dacpac with ScriptOnly" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export
            $extractOptions.ExtractAllTableData = $true
            $dacpac = Export-DbaDacPackage -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -DacOption $extractOptions
            $publishprofile = New-DbaDacProfile -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -Path $TestConfig.Temp
            $result = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -ScriptOnly -PublishXml $publishprofile.FileName -EnableException
        }

        AfterAll {
            if ($dacpac.Path) { Remove-Item -Path $dacpac.Path -ErrorAction SilentlyContinue }
            if ($result.DatabaseScriptPath) { Remove-Item -Path $result.DatabaseScriptPath -ErrorAction SilentlyContinue }
            if ($publishprofile.FileName) { Remove-Item -Path $publishprofile.FileName -ErrorAction SilentlyContinue }
        }

        It "Includes script path properties when ScriptOnly is specified" {
            $result.PSObject.Properties.Name | Should -Contain "DatabaseScriptPath" -Because "ScriptOnly should generate script path"
            $result.PSObject.Properties.Name | Should -Contain "MasterDbScriptPath" -Because "ScriptOnly should include master script path"
        }
    }

    Context "Output Validation - Dacpac with GenerateDeploymentReport" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export
            $extractOptions.ExtractAllTableData = $true
            $dacpac = Export-DbaDacPackage -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -DacOption $extractOptions
            $options = New-DbaDacOption -Action Publish
            $result = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -GenerateDeploymentReport -EnableException
        }

        AfterAll {
            if ($dacpac.Path) { Remove-Item -Path $dacpac.Path -ErrorAction SilentlyContinue }
            if ($result.DeploymentReport) { Remove-Item -Path $result.DeploymentReport -ErrorAction SilentlyContinue }
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $dbname -Confirm:$false
        }

        It "Includes DeploymentReport property when -GenerateDeploymentReport is specified" {
            $result.PSObject.Properties.Name | Should -Contain "DeploymentReport" -Because "GenerateDeploymentReport should create deployment report"
        }
    }

    Context "Output Validation - Bacpac" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export -Type Bacpac
            $bacpac = Export-DbaDacPackage -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -DacOption $extractOptions -Type Bacpac
            $options = New-DbaDacOption -Action Publish -Type Bacpac
            $result = $bacpac | Publish-DbaDacPackage -Type Bacpac -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -EnableException
        }

        AfterAll {
            if ($bacpac.Path) { Remove-Item -Path $bacpac.Path -ErrorAction SilentlyContinue }
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $dbname -Confirm:$false
        }

        It "Returns PSCustomObject" {
            $result.PSObject.TypeNames | Should -Contain "System.Management.Automation.PSCustomObject"
        }

        It "Has the expected default display properties for Bacpac import" {
            $expectedProps = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Database",
                "Bacpac",
                "Result",
                "DeployOptions"
            )
            $actualProps = $result.PSObject.Properties.Name
            foreach ($prop in $expectedProps) {
                $actualProps | Should -Contain $prop -Because "property '$prop' should be in default display"
            }
        }
    }
}