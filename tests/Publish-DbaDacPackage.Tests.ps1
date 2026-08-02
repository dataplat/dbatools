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
                "AccessToken",
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

        It "Rejects a SQL credential and access token together" {
            $securePassword = New-Object System.Security.SecureString
            foreach ($passwordCharacter in "unused".ToCharArray()) {
                $securePassword.AppendChar($passwordCharacter)
            }
            $securePassword.MakeReadOnly()
            $credential = New-Object System.Management.Automation.PSCredential -ArgumentList "unused", $securePassword
            $splatConflictingAuthentication = @{
                SqlInstance     = "not-used"
                SqlCredential   = $credential
                AccessToken     = "unused-token"
                Path            = "not-used.dacpac"
                Database        = "not-used"
                EnableException = $true
            }

            { Publish-DbaDacPackage @splatConflictingAuthentication } | Should -Throw "*cannot be used together*"
        }

        It "Accepts established access token shapes" {
            (Get-Command Publish-DbaDacPackage).Parameters["AccessToken"].ParameterType | Should -Be ([PSObject])
        }

        It "Constructs DacServices with the exact universal authentication provider overload" {
            InModuleScope dbatools {
                if (-not ("DbaTestRenewableAccessToken" -as [type])) {
                    $renewableTokenSource = @"
public sealed class DbaTestRenewableAccessToken
{
    public int CallCount { get; private set; }

    public string GetAccessToken()
    {
        CallCount++;
        return "renewed-token-" + CallCount;
    }
}
"@
                    Add-Type -TypeDefinition $renewableTokenSource -ErrorAction Stop
                }
                $renewableToken = New-Object DbaTestRenewableAccessToken
                $services = New-DbaDacService -ConnectionString "Server=unused.database.windows.net;Database=master;Encrypt=True" -AccessToken $renewableToken
                $longTokenServices = New-DbaDacService -ConnectionString "Server=unused.database.windows.net;Database=master;Encrypt=True" -AccessToken ("x" * 129)
                $providerType = "Dataplat.Dbatools.Utility.DacAccessTokenProvider" -as [type]
                $provider = New-Object $providerType -ArgumentList $renewableToken, $true
                $secureToken = New-Object System.Security.SecureString
                foreach ($secureTokenCharacter in "secure-proof".ToCharArray()) {
                    $secureToken.AppendChar($secureTokenCharacter)
                }
                $secureToken.MakeReadOnly()
                $secureTokenProvider = New-Object $providerType -ArgumentList $secureToken, $false
                $constructorTypes = [type[]]@([string], [Microsoft.SqlServer.Dac.IUniversalAuthProvider])
                $universalAuthConstructor = [Microsoft.SqlServer.Dac.DacServices].GetConstructor($constructorTypes)

                $services | Should -BeOfType ([Microsoft.SqlServer.Dac.DacServices])
                $longTokenServices | Should -BeOfType ([Microsoft.SqlServer.Dac.DacServices])
                $universalAuthConstructor.GetParameters()[1].ParameterType | Should -Be ([Microsoft.SqlServer.Dac.IUniversalAuthProvider])
                $renewableToken.CallCount | Should -Be 0
                $provider -is [Microsoft.SqlServer.Dac.IUniversalAuthProvider] | Should -BeTrue
                $provider.GetValidAccessToken() | Should -Be "renewed-token-1"
                $provider.GetValidAccessToken() | Should -Be "renewed-token-2"
                $secureTokenProvider.GetValidAccessToken() | Should -Be "secure-proof"
            }
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
        $script:publishprofile = New-DbaDacProfile -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -Path $TestConfig.Temp

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy1, $TestConfig.InstanceCopy2 -Database $dbname
        Remove-Item -Path $script:publishprofile.FileName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterEach {
        Remove-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $dbname
    }
    Context "Dacpac tests" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export
            $extractOptions.ExtractAllTableData = $true
            $script:dacpac = Export-DbaDacPackage -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -DacOption $extractOptions
        }

        AfterAll {
            if ($script:dacpac.Path) { Remove-Item -Path $script:dacpac.Path -ErrorAction SilentlyContinue }
        }

        It "Performs an xml-based deployment" {
            $results = $script:dacpac | Publish-DbaDacPackage -PublishXml $script:publishprofile.FileName -Database $dbname -SqlInstance $TestConfig.InstanceCopy2
            $results.Result | Should -BeLike "*Update complete.*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Performs an SMO-based deployment" {
            $options = New-DbaDacOption -Action Publish
            $results = $script:dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2
            $results.Result | Should -BeLike "*Update complete.*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Performs an SMO-based deployment and generates a deployment report" {
            $options = New-DbaDacOption -Action Publish
            $results = $script:dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -GenerateDeploymentReport
            $results.Result | Should -BeLike "*Update complete.*"
            $results.DeploymentReport | Should -Not -BeNullOrEmpty
            $deploymentReportContent = Get-Content -Path $results.DeploymentReport
            $deploymentReportContent | Should -BeLike "*DeploymentReport*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Performs a script generation without deployment" {
            $results = $script:dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -ScriptOnly -PublishXml $script:publishprofile.FileName
            $results.Result | Should -BeLike "*Reporting and scripting deployment plan (Complete)*"
            $results.DatabaseScriptPath | Should -Not -BeNullOrEmpty
            Test-Path ($results.DatabaseScriptPath) | Should -Be $true
            Get-DbaDatabase -SqlInstance $TestConfig.InstanceCopy2 -Database $dbname | Should -BeNullOrEmpty
            Remove-Item $results.DatabaseScriptPath
        }

        It "Performs a script generation without deployment and using an input options object" {
            $opts = New-DbaDacOption -Action Publish
            $opts.GenerateDeploymentScript = $true
            $results = $script:dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -DacOption $opts
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
            $results = $script:dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -DacOption $opts
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
            $script:bacpac = Export-DbaDacPackage -SqlInstance $TestConfig.InstanceCopy1 -Database $dbname -DacOption $extractOptions -Type Bacpac
        }

        AfterAll {
            if ($script:bacpac.Path) { Remove-Item -Path $script:bacpac.Path -ErrorAction SilentlyContinue }
        }

        It "Performs an SMO-based deployment" {
            $options = New-DbaDacOption -Action Publish -Type Bacpac
            $results = $script:bacpac | Publish-DbaDacPackage -Type Bacpac -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2
            $results.Result | Should -BeLike "*Updating database (Complete)*"
            $connectionPassword = $TestConfig.SqlCred.GetNetworkCredential().Password
            $results.ConnectionString.Contains($connectionPassword) | Should -BeFalse
            $results.ConnectionString | Should -Match "Password=\*{8}"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Auto detects that a .bacpac is being used and sets the Type to Bacpac" {
            $options = New-DbaDacOption -Action Publish -Type Bacpac
            $results = $script:bacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $TestConfig.InstanceCopy2
            $results.Result | Should -BeLike "*Updating database (Complete)*"
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -Query "SELECT id FROM dbo.example"
            $ids.id | Should -Not -BeNullOrEmpty
        }

        It "Should throw when ScriptOnly is used" {
            { $script:bacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $TestConfig.InstanceCopy2 -ScriptOnly -Type Bacpac -EnableException } | Should -Throw
        }

        It "Throws and emits no success result when a BACPAC import cannot authenticate" {
            $badPassword = New-Object System.Security.SecureString
            foreach ($character in "definitely-wrong".ToCharArray()) {
                $badPassword.AppendChar($character)
            }
            $badPassword.MakeReadOnly()
            $badCredential = New-Object System.Management.Automation.PSCredential -ArgumentList $TestConfig.SqlCred.UserName, $badPassword
            $splatBadConnection = @{
                SqlInstance   = $TestConfig.InstanceCopy2
                SqlCredential = $badCredential
                Database      = "master"
            }
            $badConnectionString = New-DbaConnectionString @splatBadConnection
            $splatPublishFailure = @{
                ConnectionString = $badConnectionString
                Database        = $dbname
                Path            = $script:bacpac.Path
                Type            = "Bacpac"
                EnableException = $true
                Confirm         = $false
            }

            $publishOutput = New-Object System.Collections.ArrayList
            $failureRecord = $null
            try {
                Publish-DbaDacPackage @splatPublishFailure | ForEach-Object {
                    $null = $publishOutput.Add($PSItem)
                }
            } catch {
                $failureRecord = $PSItem
            }

            $failureRecord.Exception.Message | Should -BeLike "*Login failed*"
            $publishOutput | Should -BeNullOrEmpty
        }
    }
}
