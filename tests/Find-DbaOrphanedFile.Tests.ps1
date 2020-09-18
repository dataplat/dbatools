$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'FileType', 'LocalOnly', 'RemoteOnly', 'EnableException', 'Recurse'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
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
                It "has failed setup" {
                    Set-TestInconclusive -Message "Setup failed"
                }
                throw "has failed setup"
            }
            $guid = (New-Guid).Guid
            $userdir = New-Item -Path "C:\$guid" -ItemType Container
            New-Item -Path $userdir -ItemType File -Name 'file1.txt' | Out-Null
            New-Item -Path "$userdir\subdir" -ItemType Container | Out-Null
            New-Item -Path "$userdir\subdir" -ItemType File -Name 'file2.txt' | Out-Null
        }
        AfterAll {
            Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        }
        $null = Dismount-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Force
        $results = Find-DbaOrphanedFile -SqlInstance $script:instance2
        $userpathresults = Find-DbaOrphanedFile -SqlInstance $script:instance2 -Path $userdir.FullName -FileType 'txt'
        $recurseresults = Find-DbaOrphanedFile -SqlInstance $script:instance2 -Path $userdir.FullName -FileType 'txt' -Recurse

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

        It "Finds 3 files: including $userdir" {
            $userpathresults.Count | Should Be 3
        }

        It "Finds 4 files: recursing $userdir" {
            $recurseresults.Count | Should Be 4
        }

        $results.FileName | Remove-Item
        $userdir | Remove-Item -Recurse

        $results = Find-DbaOrphanedFile -SqlInstance $script:instance2
        $userpathresults = Find-DbaOrphanedFile -SqlInstance $script:instance2 -Path $userdir.FullName -FileType 'txt'
        $recurseresults = Find-DbaOrphanedFile -SqlInstance $script:instance2 -Path $userdir.FullName -FileType 'txt' -Recurse
        It "Finds zero files after cleaning up" {
            $results.Count | Should Be 0
            $userpathresults.Count | Should Be 0
            $recurseresults.Count | Should Be 0
        }
    }
}