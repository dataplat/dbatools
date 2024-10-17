param($ModuleName = 'dbatools')

Describe "Get-ObjectNameParts" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
        . "$PSScriptRoot\..\private\functions\Get-DirectoryRestoreFile.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-ObjectNameParts
        }
        It "Should have ObjectName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ObjectName -Type String -Mandatory:$false
        }
    }

    Context "Test one part names" {
        BeforeAll {
            $objectName = 'table1', '[table2]', '[tab..le3]', '[table]]x4]', '[table5]]]'
            $table = 'table1', 'table2', 'tab..le3', 'table]]x4', 'table5]]'
        }
        It "Should return correct parts for '<_>'" -ForEach $objectName {
            $result = Get-ObjectNameParts -ObjectName $_
            $result.Parsed | Should -BeTrue
            $result.Database | Should -BeNullOrEmpty
            $result.Schema | Should -BeNullOrEmpty
            $result.Name | Should -Be $table[$objectName.IndexOf($_)]
        }
    }

    Context "Test two part names" {
        BeforeAll {
            $objectName = 'schema1.table1', '[sche..ma2].[table2]', 'schema3.[tab..le3]', '[schema4].[table]]x4]', 'schema5.[table5]]]'
            $table = 'table1', 'table2', 'tab..le3', 'table]]x4', 'table5]]'
            $schema = 'schema1', 'sche..ma2', 'schema3', 'schema4', 'schema5'
        }
        It "Should return correct parts for '<_>'" -ForEach $objectName {
            $result = Get-ObjectNameParts -ObjectName $_
            $result.Parsed | Should -BeTrue
            $result.Database | Should -BeNullOrEmpty
            $result.Schema | Should -Be $schema[$objectName.IndexOf($_)]
            $result.Name | Should -Be $table[$objectName.IndexOf($_)]
        }
    }

    Context "Test three part names" {
        BeforeAll {
            $objectName = 'database1.schema1.table1', 'database2..table2', 'database3..[tab..le3]', 'db4.[sche..ma4].table4'
            $table = 'table1', 'table2', 'tab..le3', 'table4'
            $schema = 'schema1', $null, $null, 'sche..ma4'
            $database = 'database1', 'database2', 'database3', 'db4'
        }
        It "Should return correct parts for '<_>'" -ForEach $objectName {
            $result = Get-ObjectNameParts -ObjectName $_
            $result.Parsed | Should -BeTrue
            $result.Database | Should -Be $database[$objectName.IndexOf($_)]
            $result.Schema | Should -Be $schema[$objectName.IndexOf($_)]
            $result.Name | Should -Be $table[$objectName.IndexOf($_)]
        }
    }

    Context "Test wrong names" {
        It "Should not return parts for 'part1.part2.part3.part4'" {
            (Get-ObjectNameParts -ObjectName 'part1.part2.part3.part4').Parsed | Should -BeFalse
        }
    }
}
