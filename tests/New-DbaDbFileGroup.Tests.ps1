param($ModuleName = 'dbatools')

Describe "New-DbaDbFileGroup" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $db1name = "dbatoolsci_filegroup_test_$random"
        $db2name = "dbatoolsci_filegroup_test2_$random"

        $server = Connect-DbaInstance -SqlInstance $env:instance2
        $newDb1 = New-DbaDatabase -SqlInstance $env:instance2 -Name $db1name
        $newDb2 = New-DbaDatabase -SqlInstance $env:instance2 -Name $db2name

        $fileStreamStatus = Get-DbaFilestream -SqlInstance $env:instance2

        if ($fileStreamStatus.InstanceAccessLevel -eq 0) {
            Enable-DbaFilestream -SqlInstance $env:instance2 -Confirm:$false -Force
            $resetFileStream = $true
        } else {
            $resetFileStream = $false
        }
    }

    AfterAll {
        $newDb1, $newDb2 | Remove-DbaDatabase -Confirm:$false

        if ($resetFileStream) {
            Disable-DbaFilestream -SqlInstance $env:instance2 -Confirm:$false -Force
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbFileGroup
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Not -Mandatory
        }
        It "Should have FileGroup parameter" {
            $CommandUnderTest | Should -HaveParameter FileGroup -Type String -Not -Mandatory
        }
        It "Should have FileGroupType parameter" {
            $CommandUnderTest | Should -HaveParameter FileGroupType -Type String -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command functionality" {
        It "Creates a filegroup" {
            $results = New-DbaDbFileGroup -SqlInstance $env:instance2 -Database $db1name -FileGroup "filegroup_$random"
            $results.Parent.Name | Should -Be $db1name
            $results.Name | Should -Be "filegroup_$random"
            $results.FileGroupType | Should -Be RowsFileGroup
        }

        It "Check the validation for duplicate filegroup names" {
            $results = New-DbaDbFileGroup -SqlInstance $env:instance2 -Database $db1name -FileGroup "filegroup_$random"
            $results | Should -BeNullOrEmpty
        }

        It "Creates a filegroup of each FileGroupType" {
            $results = New-DbaDbFileGroup -SqlInstance $env:instance2 -Database $db1name -FileGroup "filegroup_rows_$random" -FileGroupType RowsFileGroup
            $results.Name | Should -Be "filegroup_rows_$random"
            $results.FileGroupType | Should -Be RowsFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $env:instance2 -Database $db1name -FileGroup "filegroup_filestream_$random" -FileGroupType FileStreamDataFileGroup
            $results.Name | Should -Be "filegroup_filestream_$random"
            $results.FileGroupType | Should -Be FileStreamDataFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $env:instance2 -Database $db1name -FileGroup "filegroup_memory_optimized_$random" -FileGroupType MemoryOptimizedDataFileGroup
            $results.Name | Should -Be "filegroup_memory_optimized_$random"
            $results.FileGroupType | Should -Be MemoryOptimizedDataFileGroup
        }

        It "Creates a filegroup using a database from a pipeline" {
            $results = $newDb1 | New-DbaDbFileGroup -FileGroup "filegroup_pipeline_$random"
            $results.Name | Should -Be "filegroup_pipeline_$random"
            $results.Parent.Name | Should -Be $db1name

            $results = $newDb1 | New-DbaDbFileGroup -SqlInstance $env:instance2 -Database $db2name -FileGroup "filegroup_pipeline2_$random"
            $results.Name | Should -Be "filegroup_pipeline2_$random", "filegroup_pipeline2_$random"
            $results.Parent.Name | Should -Be $db1name, $db2name
        }
    }
}
