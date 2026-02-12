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

            # Output validation
            $outputDbName = "dbatoolsci_yourpublishoutput"
            $outputDb = New-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Name $outputDbName
            $null = $outputDb.Query("CREATE TABLE dbo.outputexample (id int, PRIMARY KEY (id));
                INSERT dbo.outputexample
                SELECT top 10 object_id
                FROM sys.objects")
            $outputExtractOptions = New-DbaDacOption -Action Export
            $outputExtractOptions.ExtractAllTableData = $true
            $outputDacpac = Export-DbaDacPackage -SqlInstance $TestConfig.InstanceCopy1 -Database $outputDbName -DacOption $outputExtractOptions
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $outputDbName -Confirm:$false
            $outputOptions = New-DbaDacOption -Action Publish
            $script:validationResult = $outputDacpac | Publish-DbaDacPackage -DacOption $outputOptions -Database $outputDbName -SqlInstance $TestConfig.InstanceCopy1
        }

        AfterAll {
            if ($dacpac.Path) { Remove-Item -Path $dacpac.Path -ErrorAction SilentlyContinue }
            Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1 -Database $outputDbName -Confirm:$false -ErrorAction SilentlyContinue
            if ($outputDacpac.Path) { Remove-Item -Path $outputDacpac.Path -ErrorAction SilentlyContinue }
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

        Context "Output validation" {
            It "Returns output of the documented type" {
                $script:validationResult | Should -Not -BeNullOrEmpty
                $script:validationResult[0] | Should -BeOfType [PSCustomObject]
            }

            It "Has the expected default display properties" {
                if (-not $script:validationResult) { Set-ItResult -Skipped -Because "no result to validate" }
                $defaultProps = $script:validationResult[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
                $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Dacpac", "PublishXml", "Result", "DeployOptions", "SqlCmdVariableValues")
                foreach ($prop in $expectedDefaults) {
                    $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
                }
            }

            It "Has the expected properties on the output object" {
                if (-not $script:validationResult) { Set-ItResult -Skipped -Because "no result to validate" }
                $expectedProperties = @("ComputerName", "InstanceName", "SqlInstance", "Database", "Dacpac", "PublishXml", "Result", "DeployOptions", "SqlCmdVariableValues", "ConnectionString")
                foreach ($prop in $expectedProperties) {
                    $script:validationResult[0].PSObject.Properties.Name | Should -Contain $prop -Because "property '$prop' should exist on the output object"
                }
            }
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
}