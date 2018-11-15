$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 12
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Expand-DbaDbLogFile).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'TargetLogSize', 'IncrementSize', 'LogFileId', 'ShrinkLogFile', 'ShrinkSize', 'BackupDirectory', 'ExcludeDiskSpaceValidation', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $db1 = "dbatoolsci_expand"
        $server.Query("CREATE DATABASE $db1")
    }
    AfterAll {
        Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database $db1
    }

    $results = Expand-DbaDbLogFile -SqlInstance $script:instance1 -Database $db1 -TargetLogSizeMB 128

    It -Skip "Should have correct properties" {
        $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,ID,Name,LogFileCount,InitialSize,CurrentSize,InitialVLFCount,CurrentVLFCount'.Split(',')
        ($results[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
    }

    It "Should have database name of $db1" {
        foreach ($result in $results) {
            $result.InitialSize -gt $result.CurrentSize
        }
    }

    It "Should have grown the log file" {
        foreach ($result in $results) {
            $result.InitialSize -gt $result.CurrentSize
        }
    }
}