$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'PublishXml', 'Database', 'ConnectionString', 'GenerateDeploymentReport', 'ScriptOnly', 'Type', 'OutputPath', 'IncludeSqlCmdVars', 'DacOption', 'EnableException', 'DacFxPath'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
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
        AfterAll {
            if ($dacpac.Path) { Remove-Item -Confirm:$false -Path $dacpac.Path -ErrorAction SilentlyContinue }
        }
        It "Performs an xml-based deployment" {
            $results = $dacpac | Publish-DbaDacPackage -PublishXml $publishprofile.FileName -Database $dbname -SqlInstance $script:instance2 -Confirm:$false
            $results.Result | Should -BeLike '*Update complete.*'
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $script:instance2 -Query 'SELECT id FROM dbo.example'
            $ids.id | Should -Not -BeNullOrEmpty
        }
        It "Performs an SMO-based deployment" {
            $options = New-DbaDacOption -Action Publish
            $results = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $script:instance2 -Confirm:$false
            $results.Result | Should -BeLike '*Update complete.*'
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $script:instance2 -Query 'SELECT id FROM dbo.example'
            $ids.id | Should -Not -BeNullOrEmpty
        }
        It "Performs an SMO-based deployment and generates a deployment report" {
            $options = New-DbaDacOption -Action Publish
            $results = $dacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $script:instance2 -GenerateDeploymentReport -Confirm:$false
            $results.Result | Should -BeLike '*Update complete.*'
            $results.DeploymentReport | Should -Not -BeNullOrEmpty
            $deploymentReportContent = Get-Content -Path $results.DeploymentReport
            $deploymentReportContent | Should -BeLike '*DeploymentReport*'
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $script:instance2 -Query 'SELECT id FROM dbo.example'
            $ids.id | Should -Not -BeNullOrEmpty
        }
        It "Performs a script generation without deployment" {
            $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $script:instance2 -ScriptOnly -PublishXml $publishprofile.FileName  -Confirm:$false
            $results.Result | Should -BeLike '*Reporting and scripting deployment plan (Complete)*'
            $results.DatabaseScriptPath | Should -Not -BeNullOrEmpty
            Test-Path ($results.DatabaseScriptPath) | Should -Be $true
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Should -BeNullOrEmpty
            Remove-Item $results.DatabaseScriptPath
        }
        It "Performs a script generation without deployment and using an input options object" {
            $opts = New-DbaDacOption -Action Publish
            $opts.GenerateDeploymentScript = $true
            $results = $dacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $script:instance2 -DacOption $opts -Confirm:$false
            $results.Result | Should -BeLike '*Reporting and scripting deployment plan (Complete)*'
            $results.DatabaseScriptPath | Should -Not -BeNullOrEmpty
            Test-Path ($results.DatabaseScriptPath) | Should -Be $true
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Should -BeNullOrEmpty
            Remove-Item $results.DatabaseScriptPath
        }
    }
    Context "Bacpac tests" {
        BeforeAll {
            $extractOptions = New-DbaDacOption -Action Export -Type Bacpac
            $bacpac = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname -DacOption $extractOptions -Type Bacpac
        }
        AfterAll {
            if ($bacpac.Path) { Remove-Item -Confirm:$false -Path $bacpac.Path -ErrorAction SilentlyContinue }
        }
        It "Performs an SMO-based deployment" {
            $options = New-DbaDacOption -Action Publish -Type Bacpac
            $results = $bacpac | Publish-DbaDacPackage -Type Bacpac -DacOption $options -Database $dbname -SqlInstance $script:instance2 -Confirm:$false
            $results.Result | Should -BeLike '*Updating database (Complete)*'
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $script:instance2 -Query 'SELECT id FROM dbo.example'
            $ids.id | Should -Not -BeNullOrEmpty
        }
        It "Auto detects that a .bacpac is being used and sets the Type to Bacpac" {
            $options = New-DbaDacOption -Action Publish -Type Bacpac
            $results = $bacpac | Publish-DbaDacPackage -DacOption $options -Database $dbname -SqlInstance $script:instance2 -Confirm:$false
            $results.Result | Should -BeLike '*Updating database (Complete)*'
            $ids = Invoke-DbaQuery -Database $dbname -SqlInstance $script:instance2 -Query 'SELECT id FROM dbo.example'
            $ids.id | Should -Not -BeNullOrEmpty
        }
        It "Should throw when ScriptOnly is used" {
            { $bacpac | Publish-DbaDacPackage -Database $dbname -SqlInstance $script:instance2 -ScriptOnly -Type Bacpac -EnableException -Confirm:$false } | Should -Throw
        }
    }
}
