param($ModuleName = 'dbatools')

Describe "Get-DbaFile" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaFile
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[] -Mandatory:$false
        }
        It "Should have FileType as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter FileType -Type String[] -Mandatory:$false
        }
        It "Should have Depth as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter Depth -Type Int32 -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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
