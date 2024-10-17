param($ModuleName = 'dbatools')

Describe "New-DbaDbFileGroup" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $db1name = "dbatoolsci_filegroup_test_$random"
        $db2name = "dbatoolsci_filegroup_test2_$random"

        $server = Connect-DbaInstance -SqlInstance $global:instance2
        $newDb1 = New-DbaDatabase -SqlInstance $global:instance2 -Name $db1name
        $newDb2 = New-DbaDatabase -SqlInstance $global:instance2 -Name $db2name

        $fileStreamStatus = Get-DbaFilestream -SqlInstance $global:instance2

        if ($fileStreamStatus.InstanceAccessLevel -eq 0) {
            Enable-DbaFilestream -SqlInstance $global:instance2 -Confirm:$false -Force
            $resetFileStream = $true
        } else {
            $resetFileStream = $false
        }
    }

    AfterAll {
        $newDb1, $newDb2 | Remove-DbaDatabase -Confirm:$false

        if ($resetFileStream) {
            Disable-DbaFilestream -SqlInstance $global:instance2 -Confirm:$false -Force
        }
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaDbFileGroup
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type String[] -Mandatory:$false
        }
        It "Should have FileGroup parameter" {
            $CommandUnderTest | Should -HaveParameter FileGroup -Type String -Mandatory:$false
        }
        It "Should have FileGroupType parameter" {
            $CommandUnderTest | Should -HaveParameter FileGroupType -Type String -Mandatory:$false
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.Smo.Database[] -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command functionality" {
        It "Creates a filegroup" {
            $results = New-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup "filegroup_$random"
            $results.Parent.Name | Should -Be $db1name
            $results.Name | Should -Be "filegroup_$random"
            $results.FileGroupType | Should -Be RowsFileGroup
        }

        It "Check the validation for duplicate filegroup names" {
            $results = New-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup "filegroup_$random"
            $results | Should -BeNullOrEmpty
        }

        It "Creates a filegroup of each FileGroupType" {
            $results = New-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup "filegroup_rows_$random" -FileGroupType RowsFileGroup
            $results.Name | Should -Be "filegroup_rows_$random"
            $results.FileGroupType | Should -Be RowsFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup "filegroup_filestream_$random" -FileGroupType FileStreamDataFileGroup
            $results.Name | Should -Be "filegroup_filestream_$random"
            $results.FileGroupType | Should -Be FileStreamDataFileGroup

            $results = New-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db1name -FileGroup "filegroup_memory_optimized_$random" -FileGroupType MemoryOptimizedDataFileGroup
            $results.Name | Should -Be "filegroup_memory_optimized_$random"
            $results.FileGroupType | Should -Be MemoryOptimizedDataFileGroup
        }

        It "Creates a filegroup using a database from a pipeline" {
            $results = $newDb1 | New-DbaDbFileGroup -FileGroup "filegroup_pipeline_$random"
            $results.Name | Should -Be "filegroup_pipeline_$random"
            $results.Parent.Name | Should -Be $db1name

            $results = $newDb1 | New-DbaDbFileGroup -SqlInstance $global:instance2 -Database $db2name -FileGroup "filegroup_pipeline2_$random"
            $results.Name | Should -Be "filegroup_pipeline2_$random", "filegroup_pipeline2_$random"
            $results.Parent.Name | Should -Be $db1name, $db2name
        }
    }
}
