$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Path', 'FileType', 'LocalOnly', 'RemoteOnly', 'Recurse', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Orphaned files are correctly identified" {
        BeforeAll {
            $dbname = "dbatoolsci_orphanedfile"
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $null = $server.Query("CREATE DATABASE $dbname")
            $tmpdir = "c:\temp\orphan_$(Get-Random)"
            if (-not(Test-Path $tmpdir)) {
                $null = New-Item -Path $tmpdir -type Container
            }
            $tmpdirInner = Join-Path $tmpdir "inner"
            $null = New-Item -Path $tmpdirInner -type Container
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
            Remove-Item $tmpdir -Recurse -Force -ErrorAction SilentlyContinue
        }
        It "Has the correct properties" {
            $null = Detach-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Force
            $results = Find-DbaOrphanedFile -SqlInstance $script:instance2
            $ExpectedStdProps = 'ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename'.Split(',')
            ($results[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames | Sort-Object) | Should -Be ($ExpectedStdProps | Sort-Object)
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Filename,RemoteFilename,Server'.Split(',')
            ($results[0].PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }


        It "Finds two files" {
            $results = Find-DbaOrphanedFile -SqlInstance $script:instance2
            $results.Filename.Count | Should -Be 2
        }

        It "Finds zero files after cleaning up" {
            $results = Find-DbaOrphanedFile -SqlInstance $script:instance2
            $results.FileName | Remove-Item
            $results = Find-DbaOrphanedFile -SqlInstance $script:instance2
            $results.Filename.Count | Should -Be 0
        }
        It "works with -Recurse" {
            "a" | out-file (Join-Path $tmpdir "out.mdf")
            $results = Find-DbaOrphanedFile -SqlInstance $script:instance2 -Path $tmpdir
            $results.Filename.Count | Should -Be 1
            move-item "$tmpdir\out.mdf" -destination $tmpdirInner
            $results = Find-DbaOrphanedFile -SqlInstance $script:instance2 -Path $tmpdir
            $results.Filename.Count | Should -Be 0
            $results = Find-DbaOrphanedFile -SqlInstance $script:instance2 -Path $tmpdir -Recurse
            $results.Filename.Count | Should -Be 1
        }
    }
}