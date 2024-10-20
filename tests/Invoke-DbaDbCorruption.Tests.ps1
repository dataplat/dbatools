param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbCorruption" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Invoke-DbaDbCorruption.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbCorruption
        }

        It "has all the required parameters" {
            $params = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
                "EnableException"
            )
            It "has the required parameter: <_>" -ForEach $params {
                $CommandUnderTest | Should -HaveParameter $PSItem
            }
        }
    }

    Context "Validate Confirm impact" {
        It "Confirm Impact should be high" {
            $metadata = [System.Management.Automation.CommandMetadata](Get-Command $CommandName)
            $metadata.ConfirmImpact | Should -Be 'High'
        }
    }

    Context "Integration Tests" {
        BeforeAll {
            $dbname = "dbatoolsci_InvokeDbaDatabaseCorruptionTest"
            $Server = Connect-DbaInstance -SqlInstance $global:instance2
            $TableName = "Example"
            # Need a clean empty database
            $null = $Server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $global:instance2 -Database $dbname
        }

        AfterAll {
            # Cleanup
            Remove-DbaDatabase -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
        }

        Context "Validating Database Input" {
            It "Should not allow you to corrupt system databases." {
                $systemwarn = $null
                Invoke-DbaDbCorruption -SqlInstance $global:instance2 -Database "master" -WarningAction SilentlyContinue -WarningVariable systemwarn
                $systemwarn | Should -Match 'may not corrupt system databases'
            }

            It "Should fail if more than one database is specified" {
                { Invoke-DbaDbCorruption -SqlInstance $global:instance2 -Database "Database1", "Database2" -EnableException } | Should -Throw
            }
        }

        It "Require at least a single table in the database specified" {
            { Invoke-DbaDbCorruption -SqlInstance $global:instance2 -Database $dbname -EnableException } | Should -Throw
        }

        It "Fail if the specified table does not exist" {
            { Invoke-DbaDbCorruption -SqlInstance $global:instance2 -Database $dbname -Table "DoesntExist$(New-Guid)" -EnableException } | Should -Throw
        }

        It "Corrupt a single database" {
            $null = $db.Query("
                CREATE TABLE dbo.[$TableName] (id int);
                INSERT dbo.[Example]
                SELECT top 1000 1
                FROM sys.objects")

            $result = Invoke-DbaDbCorruption -SqlInstance $global:instance2 -Database $dbname -Confirm:$false
            $result.Status | Should -Be "Corrupted"
        }

        It "Causes DBCC CHECKDB to fail" {
            $result = Start-DbccCheck -Server $server -dbname $dbname
            $result | Should -Not -Be 'Success'
        }
    }
}
