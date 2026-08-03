#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaSsisFolder",
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
                "Description",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should expose Name as an alias of Folder" {
            (Get-Command $CommandName).Parameters["Folder"].Aliases | Should -Contain "Name"
        }

        It "Should declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance     = $TestConfig.InstanceSsis
        $simpleFolder     = "dbatoolsci_newfolder1"
        $describedFolder  = "dbatoolsci_newfolder2"
        $whatIfFolder     = "dbatoolsci_newfolder3"
        $existingFolder   = "dbatoolsci_newfolder4"
        $survivorFolder   = "dbatoolsci_newfolder5"
        $aliasFolder      = "dbatoolsci_newfolder6"
        $multiFirst       = "dbatoolsci_newfolder7"
        $multiSecond      = "dbatoolsci_newfolder8"
        $decorationFolder = "dbatoolsci_newfolder9"
        $folderComment    = "dbatools folder create fixture"
        $createdNames     = @($simpleFolder, $describedFolder, $whatIfFolder, $existingFolder, $survivorFolder, $aliasFolder, $multiFirst, $multiSecond, $decorationFolder)

        # A leftover from an interrupted run would make the create legs collide, so the names are
        # cleared before the run rather than only after it.
        foreach ($staleName in $createdNames) {
            $splatStaleCleanup = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @name) EXEC [catalog].[delete_folder] @folder_name = @name;"
                SqlParameter = @{ name = $staleName }
            }
            Invoke-DbaQuery @splatStaleCleanup
        }

        $splatExisting = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "EXEC [catalog].[create_folder] @folder_name = @name, @folder_id = NULL;"
            SqlParameter = @{ name = $existingFolder }
        }
        Invoke-DbaQuery @splatExisting

        function Get-SsisFolderRow {
            param($Name)
            $splatFolderRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT folder_id, name, description FROM [catalog].[folders] WHERE name = @name"
                SqlParameter = @{ name = $Name }
            }
            # The comma keeps the array intact across the return: without it PowerShell unrolls a
            # one-row result to a bare DataRow, and [0] then indexes its first COLUMN, not its
            # first row.
            , @(Invoke-DbaQuery @splatFolderRead)
        }
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        foreach ($leftoverName in @("dbatoolsci_newfolder1", "dbatoolsci_newfolder2", "dbatoolsci_newfolder3", "dbatoolsci_newfolder4", "dbatoolsci_newfolder5", "dbatoolsci_newfolder6", "dbatoolsci_newfolder7", "dbatoolsci_newfolder8", "dbatoolsci_newfolder9")) {
            $splatFolderCleanup = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @name) EXEC [catalog].[delete_folder] @folder_name = @name;"
                SqlParameter = @{ name = $leftoverName }
            }
            Invoke-DbaQuery @splatFolderCleanup
        }
    }

    Context "Creating a folder" {
        It "Creates the folder and returns the id the catalog assigned" {
            $created = @(New-DbaSsisFolder -SqlInstance $ssisInstance -Folder $simpleFolder)
            $created.Count | Should -Be 1
            $created[0].Name | Should -Be $simpleFolder
            $created[0].CreatedByName | Should -Not -BeNullOrEmpty
            $created[0].CreatedTime | Should -Not -BeNullOrEmpty

            $catalogRow = Get-SsisFolderRow -Name $simpleFolder
            $catalogRow.Count | Should -Be 1
            $created[0].FolderId | Should -Be $catalogRow[0].folder_id
            $created[0].FolderId | Should -BeGreaterThan 0
        }

        It "Decorates the new folder exactly like the read command does" {
            $decorated = @(Get-DbaSsisFolder -SqlInstance $ssisInstance -Folder $simpleFolder)[0]
            $created = @(New-DbaSsisFolder -SqlInstance $ssisInstance -Folder $decorationFolder)[0]
            $created.PSObject.TypeNames[0] | Should -Be "dbatools.SsisFolder"
            $created.ComputerName | Should -Not -BeNullOrEmpty
            $created.InstanceName | Should -Not -BeNullOrEmpty
            $created.SqlInstance | Should -Not -BeNullOrEmpty
            $createdDisplaySet = $created.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $readDisplaySet = $decorated.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $readDisplaySet -DifferenceObject $createdDisplaySet | Should -BeNullOrEmpty
        }

        It "Sets the description when one is supplied" {
            $described = @(New-DbaSsisFolder -SqlInstance $ssisInstance -Folder $describedFolder -Description $folderComment)
            $described.Count | Should -Be 1
            $described[0].Description | Should -Be $folderComment
            (Get-SsisFolderRow -Name $describedFolder)[0].description | Should -Be $folderComment
        }

        It "Creates several folders in one call" {
            $both = @(New-DbaSsisFolder -SqlInstance $ssisInstance -Folder $multiFirst, $multiSecond)
            $both.Count | Should -Be 2
            $both.Name | Should -Contain $multiFirst
            $both.Name | Should -Contain $multiSecond
        }

        It "Binds -Name as an alias of -Folder" {
            $viaAlias = @(New-DbaSsisFolder -SqlInstance $ssisInstance -Name $aliasFolder)
            $viaAlias.Count | Should -Be 1
            (Get-SsisFolderRow -Name $aliasFolder).Count | Should -Be 1
        }
    }

    Context "-WhatIf" {
        It "Reports without creating the folder" {
            $whatIfResult = @(New-DbaSsisFolder -SqlInstance $ssisInstance -Folder $whatIfFolder -WhatIf)
            $whatIfResult.Count | Should -Be 0
            (Get-SsisFolderRow -Name $whatIfFolder).Count | Should -Be 0
        }
    }

    Context "Each folder succeeds or fails on its own" {
        It "Errors on the name that already exists and still creates the rest" {
            # Without -EnableException the failure surfaces as the friendly warning, not an error
            # record, so -ErrorVariable would come back empty and prove nothing.
            $splatMixed = @{
                SqlInstance     = $ssisInstance
                Folder          = @($existingFolder, $survivorFolder)
                EnableException = $false
                WarningVariable = "folderWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $mixed = @(New-DbaSsisFolder @splatMixed)
            $mixed.Count | Should -Be 1
            $mixed[0].Name | Should -Be $survivorFolder
            ($folderWarnings -join " ") | Should -BeLike "*already exists*"
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = "dbatoolsci_nocatalogfolder"
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(New-DbaSsisFolder @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            { New-DbaSsisFolder -SqlInstance $TestConfig.InstanceSingle -Folder "dbatoolsci_nocatalogfolder" -EnableException } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
