$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $versionName = $server.GetSqlServerVersionName()
        $random = Get-Random
        $dbname = "dbatoolsci_detatch_$random"
        $server.Query("CREATE DATABASE $dbname")
        $path = (Get-DbaDbFile -SqlInstance $TestConfig.instance2 -Database $dbname | Where-object {$_.PhysicalName -like '*.mdf'}).physicalname
        Detach-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Force
    }

    AfterAll {
        $server.Query("CREATE DATABASE $dbname
            ON (FILENAME = '$path')
            FOR ATTACH")
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false
    }

    Context "Command actually works" {
        $results = Get-DbaDbDetachedFileInfo -SqlInstance $TestConfig.instance2 -Path $path
        it "Gets Results" {
            $results | Should Not Be $null
        }
        It "Should be created database" {
            $results.name | Should Be $dbname
        }
        It "Should be the correct version" {
            $results.version | Should Be $versionName
        }
        It "Should have Data files" {
            $results.DataFiles | Should Not Be $null
        }
        It "Should have Log files" {
            $results.LogFiles | Should Not Be $null
        }
    }
}
