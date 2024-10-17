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
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String
        }
        It "Should have Table parameter" {
            $CommandUnderTest | Should -HaveParameter Table -Type String
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
            $Server = Connect-DbaInstance -SqlInstance $env:instance2
            $TableName = "Example"
            # Need a clean empty database
            $null = $Server.Query("Create Database [$dbname]")
            $db = Get-DbaDatabase -SqlInstance $env:instance2 -Database $dbname
        }

        AfterAll {
            # Cleanup
            Remove-DbaDatabase -SqlInstance $env:instance2 -Database $dbname -Confirm:$false
        }

        Context "Validating Database Input" {
            It "Should not allow you to corrupt system databases." {
                $systemwarn = $null
                Invoke-DbaDbCorruption -SqlInstance $env:instance2 -Database "master" -WarningAction SilentlyContinue -WarningVariable systemwarn
                $systemwarn | Should -Match 'may not corrupt system databases'
            }

            It "Should fail if more than one database is specified" {
                { Invoke-DbaDbCorruption -SqlInstance $env:instance2 -Database "Database1", "Database2" -EnableException } | Should -Throw
            }
        }

        It "Require at least a single table in the database specified" {
            { Invoke-DbaDbCorruption -SqlInstance $env:instance2 -Database $dbname -EnableException } | Should -Throw
        }

        It "Fail if the specified table does not exist" {
            { Invoke-DbaDbCorruption -SqlInstance $env:instance2 -Database $dbname -Table "DoesntExist$(New-Guid)" -EnableException } | Should -Throw
        }

        It "Corrupt a single database" {
            $null = $db.Query("
                CREATE TABLE dbo.[$TableName] (id int);
                INSERT dbo.[Example]
                SELECT top 1000 1
                FROM sys.objects")

            $result = Invoke-DbaDbCorruption -SqlInstance $env:instance2 -Database $dbname -Confirm:$false
            $result.Status | Should -Be "Corrupted"
        }

        It "Causes DBCC CHECKDB to fail" {
            $result = Start-DbccCheck -Server $server -dbname $dbname
            $result | Should -Not -Be 'Success'
        }
    }
}
