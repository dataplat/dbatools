param($ModuleName = 'dbatools')

Describe "Get-DbaDbDetachedFileInfo" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbDetachedFileInfo
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Command actually works" {
        BeforeDiscovery {
            . "$PSScriptRoot\constants.ps1"
        }

        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $versionName = $server.GetSqlServerVersionName()
            $random = Get-Random
            $dbname = "dbatoolsci_detatch_$random"
            $server.Query("CREATE DATABASE $dbname")
            $path = (Get-DbaDbFile -SqlInstance $global:instance2 -Database $dbname | Where-Object {$_.PhysicalName -like '*.mdf'}).physicalname
            Detach-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Force
        }

        AfterAll {
            $server.Query("CREATE DATABASE $dbname
                ON (FILENAME = '$path')
                FOR ATTACH")
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
        }

        It "Gets Results" {
            $results = Get-DbaDbDetachedFileInfo -SqlInstance $global:instance2 -Path $path
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should be created database" {
            $results = Get-DbaDbDetachedFileInfo -SqlInstance $global:instance2 -Path $path
            $results.name | Should -Be $dbname
        }

        It "Should be the correct version" {
            $results = Get-DbaDbDetachedFileInfo -SqlInstance $global:instance2 -Path $path
            $results.version | Should -Be $versionName
        }

        It "Should have Data files" {
            $results = Get-DbaDbDetachedFileInfo -SqlInstance $global:instance2 -Path $path
            $results.DataFiles | Should -Not -BeNullOrEmpty
        }

        It "Should have Log files" {
            $results = Get-DbaDbDetachedFileInfo -SqlInstance $global:instance2 -Path $path
            $results.LogFiles | Should -Not -BeNullOrEmpty
        }
    }
}
