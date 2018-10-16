$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 13
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Publish-DbaDacPackage).Parameters.Keys
        $knownParameters = 'SqlInstance','SqlCredential','Path','PublishXml','Database','ConnectionString','GenerateDeploymentScript','GenerateDeploymentReport','ScriptOnly','OutputPath','IncludeSqlCmdVars','EnableException','DacFxPath'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

if (-not $env:appveyor) {
    Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            Get-DbaProcess -SqlInstance $script:instance1, $script:instance2 -Program 'dbatools PowerShell module - dbatools.io' | Stop-DbaProcess -WarningAction SilentlyContinue
            $dbname = "dbatoolsci_publishdacpac"
            $server = Connect-DbaInstance -SqlInstance $script:instance1
            $null = $server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $script:instance1 -Database $dbname
            $null = $db.Query("CREATE TABLE dbo.example (id int);
            INSERT dbo.example
            SELECT top 100 1
            FROM sys.objects")
            $publishprofile = New-DbaDacProfile -SqlInstance $script:instance1 -Database $dbname -Path C:\temp
            $dacpac = Export-DbaDacPackage -SqlInstance $script:instance1 -Database $dbname
        }
        AfterAll {
            Remove-DbaDatabase -SqlInstance $script:instance1, $script:instance2 -Database $dbname -Confirm:$false
            Remove-Item -Confirm:$false -Path $publishprofile.FileName -ErrorAction SilentlyContinue
        }

        It "shows that the update is complete" {
            $results = $dacpac | Publish-DbaDacPackage -PublishXml $publishprofile.FileName -Database $dbname -SqlInstance $script:instance2
            $results.Result -match 'Update complete.' | Should Be $true
            if (($dacpac).Path) {
                Remove-Item -Confirm:$false -Path ($dacpac).Path -ErrorAction SilentlyContinue
            }
        }
    }
}