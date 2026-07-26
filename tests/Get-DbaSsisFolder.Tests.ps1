#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSsisFolder",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Folder",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should expose Name as an alias of Folder" {
            (Get-Command $CommandName).Parameters["Folder"].Aliases | Should -Contain "Name"
        }

        It "Should not declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Not -Contain "WhatIf"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance   = $TestConfig.InstanceSsis
        $folderName     = "dbatoolsci_ssisfolder"
        # The sibling name has the first as an exact prefix: a LIKE or wildcard implementation of
        # -Folder would return both, an exact-name implementation returns only the first.
        $siblingName    = "dbatoolsci_ssisfolder2"
        $folderComment  = "dbatools folder read fixture"

        $splatSetup = @{
            SqlInstance = $ssisInstance
            Database    = "SSISDB"
            Query       = "
                IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @first)
                    EXEC [catalog].[create_folder] @folder_name = @first, @folder_id = NULL;
                IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @second)
                    EXEC [catalog].[create_folder] @folder_name = @second, @folder_id = NULL;
                EXEC [catalog].[set_folder_description] @folder_name = @first, @folder_description = @comment;"
            SqlParameter = @{
                first   = $folderName
                second  = $siblingName
                comment = $folderComment
            }
        }
        Invoke-DbaQuery @splatSetup
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $splatTeardown = @{
            SqlInstance  = $TestConfig.InstanceSsis
            Database     = "SSISDB"
            Query        = "
                IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @first)
                    EXEC [catalog].[delete_folder] @folder_name = @first;
                IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @second)
                    EXEC [catalog].[delete_folder] @folder_name = @second;"
            SqlParameter = @{
                first  = "dbatoolsci_ssisfolder"
                second = "dbatoolsci_ssisfolder2"
            }
        }
        Invoke-DbaQuery @splatTeardown
    }

    Context "Reading the catalog" {
        It "Returns both fixture folders when unfiltered" {
            $allFolders = @(Get-DbaSsisFolder -SqlInstance $ssisInstance)
            $allFolders.Name | Should -Contain $folderName
            $allFolders.Name | Should -Contain $siblingName
        }

        It "Returns the verified catalog.folders columns" {
            $single = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $folderName)
            $single.Count | Should -Be 1
            $single[0].Name | Should -Be $folderName
            $single[0].Description | Should -Be $folderComment
            $single[0].FolderId | Should -BeGreaterThan 0
            $single[0].CreatedByName | Should -Not -BeNullOrEmpty
            $single[0].CreatedTime | Should -Not -BeNullOrEmpty
        }

        It "Accepts the instance from the pipeline" {
            $piped = @($ssisInstance | Get-DbaSsisFolder -Folder $folderName)
            $piped.Count | Should -Be 1
            $piped[0].Name | Should -Be $folderName
        }

        It "Accepts several folder names at once" {
            $both = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $folderName, $siblingName)
            $both.Count | Should -Be 2
        }

        It "Binds -Name as an alias of -Folder" {
            $viaAlias = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Name $folderName)
            $viaAlias.Count | Should -Be 1
            $viaAlias[0].Name | Should -Be $folderName
        }
    }

    Context "-Folder is an exact name list" {
        It "Does not return the folder whose name merely starts with the requested one" {
            $exact = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $folderName)
            $exact.Name | Should -Not -Contain $siblingName
        }

        It "Treats a LIKE metacharacter as a literal, returning nothing" {
            $withPercent = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder "$folderName%")
            $withPercent.Count | Should -Be 0
        }

        It "Treats a wildcard as a literal, returning nothing" {
            $withStar = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder "$folderName*")
            $withStar.Count | Should -Be 0
        }
    }

    Context "Output decoration" {
        It "Carries the instance property triple" {
            $decorated = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $folderName)[0]
            $decorated.ComputerName | Should -Not -BeNullOrEmpty
            $decorated.InstanceName | Should -Not -BeNullOrEmpty
            $decorated.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Carries the dbatools.SsisFolder type name" {
            $decorated = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $folderName)[0]
            $decorated.PSObject.TypeNames[0] | Should -Be "dbatools.SsisFolder"
        }

        It "Keeps FolderId on the object but off the default view" {
            $decorated = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $folderName)[0]
            $displaySet = $decorated.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $displaySet | Should -Contain "Name"
            $displaySet | Should -Contain "CreatedTime"
            $displaySet | Should -Not -Contain "FolderId"
            $decorated.PSObject.Properties.Name | Should -Contain "FolderId"
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(Get-DbaSsisFolder @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            { Get-DbaSsisFolder -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
