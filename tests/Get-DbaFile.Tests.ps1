param($ModuleName = 'dbatools')

Describe "Get-DbaFile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaFile
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Path",
                "FileType",
                "Depth",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Returns some files" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $random = Get-Random
            $db = "dbatoolsci_getfile$random"
            $server.Query("CREATE DATABASE $db")
        }
        AfterAll {
            $null = Get-DbaDatabase -SqlInstance $global:instance2 -Database $db | Remove-DbaDatabase -Confirm:$false
        }

        It "Should find the new database file" {
            $results = Get-DbaFile -SqlInstance $global:instance2
            ($results.Filename -match 'dbatoolsci').Count | Should -BeGreaterThan 0
        }

        It "Should find the new database log file" {
            $logPath = (Get-DbaDefaultPath -SqlInstance $global:instance2).Log
            $results = Get-DbaFile -SqlInstance $global:instance2 -Path $logPath
            ($results.Filename -like '*dbatoolsci*ldf').Count | Should -BeGreaterThan 0
        }

        It "Should find the master database file" {
            $masterpath = $server.MasterDBPath
            $results = Get-DbaFile -SqlInstance $global:instance2 -Path $masterpath
            ($results.Filename -match 'master.mdf').Count | Should -BeGreaterThan 0
        }
    }
}
