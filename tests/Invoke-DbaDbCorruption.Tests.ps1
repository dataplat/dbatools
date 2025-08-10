$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig
. "$PSScriptRoot\..\private\functions\Invoke-DbaDbCorruption.ps1"

Describe "$commandname Unit Tests" -Tags "UnitTests" {

    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'Table', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
    Context "Validate Confirm impact" {
        It "Confirm Impact should be high" {
            $metadata = [System.Management.Automation.CommandMetadata](Get-Command $CommandName)
            $metadata.ConfirmImpact | Should Be 'High'
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $dbname = "dbatoolsci_InvokeDbaDatabaseCorruptionTest"
        $Server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $TableName = "Example"
        # Need a clean empty database
        $null = $Server.Query("Create Database [$dbname]")
        $db = Get-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname
    }

    AfterAll {
        # Cleanup
        Remove-DbaDatabase -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false
    }

    Context "Validating Database Input" {
        # The command does not respect -WarningAction SilentlyContinue inside of this pester test - still don't know why, retest with pester 5
        Invoke-DbaDbCorruption -SqlInstance $TestConfig.instance2 -Database "master"  -WarningVariable systemwarn 3> $null
        It "Should not allow you to corrupt system databases." {
            $systemwarn -match 'may not corrupt system databases' | Should Be $true
        }
        It "Should fail if more than one database is specified" {
            { Invoke-DbaDbCorruption -SqlInstance $TestConfig.instance2 -Database "Database1", "Database2" -EnableException } | Should Throw
        }
    }

    It "Require at least a single table in the database specified" {
        { Invoke-DbaDbCorruption -SqlInstance $TestConfig.instance2 -Database $dbname -EnableException } | Should Throw
    }

    # Creating a table to make sure these are failing for different reasons
    It "Fail if the specified table does not exist" {
        { Invoke-DbaDbCorruption -SqlInstance $TestConfig.instance2 -Database $dbname -Table "DoesntExist$(New-Guid)" -EnableException } | Should Throw
    }

    $null = $db.Query("
        CREATE TABLE dbo.[$TableName] (id int);
        INSERT dbo.[Example]
        SELECT top 1000 1
        FROM sys.objects")

    It "Corrupt a single database" {
        Invoke-DbaDbCorruption -SqlInstance $TestConfig.instance2 -Database $dbname -Confirm:$false | Select-Object -ExpandProperty Status | Should be "Corrupted"
    }

    It "Causes DBCC CHECKDB to fail" {
        $result = Start-DbccCheck -Server $server -dbname $dbname
        $result | Should Not Be 'Success'
    }
}
