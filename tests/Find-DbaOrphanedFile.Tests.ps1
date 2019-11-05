$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'FileType', 'LocalOnly', 'RemoteOnly', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Orphaned files are correctly identified" {
        BeforeAll {
            $dbname = "dbatoolsci_orphanedfile"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $null = $server.Query("CREATE DATABASE $dbname")
            $result = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname
            if ($result.count -eq 0) {
                it "has failed setup" {
                    Set-TestInconclusive -message "Setup failed"
                }
                throw "has failed setup"
            }
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }
        $null = Detach-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Force
        $results = Find-DbaOrphanedFile -SqlInstance $script:instance2

        It "Has the correct default properties" {
            $ExpectedStdProps = 'ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename'.Split(',')
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should Be ($ExpectedStdProps | Sort-Object)
        }
        It "Has the correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename,Server'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }

        It "Finds two files" {
            $results.Count | Should Be 2
        }

        $results.FileName | Remove-Item

        $results = Find-DbaOrphanedFile -SqlInstance $script:instance2
        It "Finds zero files after cleaning up" {
            $results.Count | Should Be 0
        }
    }
}