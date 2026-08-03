#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaSsisEnvironment",
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
                "Environment",
                "Description",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should expose Name as an alias of Environment" {
            (Get-Command $CommandName).Parameters["Environment"].Aliases | Should -Contain "Name"
        }

        It "Should declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Contain "WhatIf"
        }

        It "Should take one folder and several environments" {
            (Get-Command $CommandName).Parameters["Folder"].ParameterType.FullName | Should -Be "System.String"
            (Get-Command $CommandName).Parameters["Environment"].ParameterType.FullName | Should -Be "System.String[]"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance     = $TestConfig.InstanceSsis
        $environmentFolder = "dbatoolsci_envfolder1"
        $simpleEnvironment = "dbatoolsci_env1"
        $describedEnvironment = "dbatoolsci_env2"
        $whatIfEnvironment = "dbatoolsci_env3"
        $existingEnvironment = "dbatoolsci_env4"
        $survivorEnvironment = "dbatoolsci_env5"
        $aliasEnvironment = "dbatoolsci_env6"
        $multiFirst       = "dbatoolsci_env7"
        $multiSecond      = "dbatoolsci_env8"
        $environmentComment = "dbatools environment create fixture"
        $createdEnvironments = @($simpleEnvironment, $describedEnvironment, $whatIfEnvironment, $existingEnvironment, $survivorEnvironment, $aliasEnvironment, $multiFirst, $multiSecond)

        function Get-SsisEnvironmentRow {
            param($Folder, $Environment)
            $splatEnvironmentRead = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "SELECT e.environment_id, e.name, e.description FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment"
                SqlParameter = @{ folder = $Folder; environment = $Environment }
            }
            # The comma keeps the array intact across the return: without it PowerShell unrolls a
            # one-row result to a bare DataRow, and [0] then indexes its first COLUMN, not its
            # first row.
            , @(Invoke-DbaQuery @splatEnvironmentRead)
        }

        $splatFolderSetup = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[create_folder] @folder_name = @folder, @folder_id = NULL;"
            SqlParameter = @{ folder = $environmentFolder }
        }
        Invoke-DbaQuery @splatFolderSetup

        # A leftover from an interrupted run would make the create legs collide, so the names are
        # cleared before the run rather than only after it.
        foreach ($staleEnvironment in $createdEnvironments) {
            $splatStaleCleanup = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment) EXEC [catalog].[delete_environment] @folder_name = @folder, @environment_name = @environment;"
                SqlParameter = @{ folder = $environmentFolder; environment = $staleEnvironment }
            }
            Invoke-DbaQuery @splatStaleCleanup
        }

        $splatExisting = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "EXEC [catalog].[create_environment] @folder_name = @folder, @environment_name = @environment, @environment_description = NULL;"
            SqlParameter = @{ folder = $environmentFolder; environment = $existingEnvironment }
        }
        Invoke-DbaQuery @splatExisting
    }

    AfterAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        foreach ($leftoverEnvironment in @("dbatoolsci_env1", "dbatoolsci_env2", "dbatoolsci_env3", "dbatoolsci_env4", "dbatoolsci_env5", "dbatoolsci_env6", "dbatoolsci_env7", "dbatoolsci_env8")) {
            $splatEnvironmentCleanup = @{
                SqlInstance  = $TestConfig.InstanceSsis
                Database     = "SSISDB"
                Query        = "IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE f.name = @folder AND e.name = @environment) EXEC [catalog].[delete_environment] @folder_name = @folder, @environment_name = @environment;"
                SqlParameter = @{ folder = "dbatoolsci_envfolder1"; environment = $leftoverEnvironment }
            }
            Invoke-DbaQuery @splatEnvironmentCleanup
        }

        $splatFolderCleanup = @{
            SqlInstance  = $TestConfig.InstanceSsis
            Database     = "SSISDB"
            Query        = "IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @folder) EXEC [catalog].[delete_folder] @folder_name = @folder;"
            SqlParameter = @{ folder = "dbatoolsci_envfolder1" }
        }
        Invoke-DbaQuery @splatFolderCleanup
    }

    Context "Creating an environment" {
        It "Creates the environment and returns it" {
            $splatCreate = @{
                SqlInstance = $ssisInstance
                Folder      = $environmentFolder
                Environment = $simpleEnvironment
            }
            $created = @(New-DbaSsisEnvironment @splatCreate)
            $created.Count | Should -Be 1
            $created[0].Name | Should -Be $simpleEnvironment
            $created[0].FolderName | Should -Be $environmentFolder
            $created[0].CreatedByName | Should -Not -BeNullOrEmpty
            $created[0].CreatedTime | Should -Not -BeNullOrEmpty

            $catalogRow = Get-SsisEnvironmentRow -Folder $environmentFolder -Environment $simpleEnvironment
            $catalogRow.Count | Should -Be 1
            $created[0].EnvironmentId | Should -Be $catalogRow[0].environment_id
            $created[0].EnvironmentId | Should -BeGreaterThan 0
        }

        It "Decorates the new environment exactly like the read command does" {
            $splatRead = @{
                SqlInstance = $ssisInstance
                Folder      = $environmentFolder
                Environment = $simpleEnvironment
            }
            $read = @(Get-DbaSsisEnvironment @splatRead)[0]
            $created = @(New-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Environment $aliasEnvironment)[0]
            $created.PSObject.TypeNames[0] | Should -Be "dbatools.SsisEnvironment"
            $created.ComputerName | Should -Not -BeNullOrEmpty
            $created.InstanceName | Should -Not -BeNullOrEmpty
            $created.SqlInstance | Should -Not -BeNullOrEmpty
            $createdDisplaySet = $created.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $readDisplaySet = $read.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            Compare-Object -ReferenceObject $readDisplaySet -DifferenceObject $createdDisplaySet | Should -BeNullOrEmpty
        }

        It "Sets the description in the same call that creates the environment" {
            # catalog.create_environment takes the description as its own parameter, so unlike a
            # folder there is no window where the object exists without it.
            $splatDescribed = @{
                SqlInstance = $ssisInstance
                Folder      = $environmentFolder
                Environment = $describedEnvironment
                Description = $environmentComment
            }
            $described = @(New-DbaSsisEnvironment @splatDescribed)
            $described.Count | Should -Be 1
            $described[0].Description | Should -Be $environmentComment
            (Get-SsisEnvironmentRow -Folder $environmentFolder -Environment $describedEnvironment)[0].description | Should -Be $environmentComment
        }

        It "Creates several environments in one call" {
            $splatMulti = @{
                SqlInstance = $ssisInstance
                Folder      = $environmentFolder
                Environment = @($multiFirst, $multiSecond)
            }
            $both = @(New-DbaSsisEnvironment @splatMulti)
            $both.Count | Should -Be 2
            $both.Name | Should -Contain $multiFirst
            $both.Name | Should -Contain $multiSecond
        }

        It "Binds -Name as an alias of -Environment" {
            (Get-SsisEnvironmentRow -Folder $environmentFolder -Environment $aliasEnvironment).Count | Should -Be 1
            $viaAlias = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Name $aliasEnvironment)
            $viaAlias.Count | Should -Be 1
        }
    }

    Context "-WhatIf" {
        It "Reports without creating the environment" {
            $splatWhatIf = @{
                SqlInstance = $ssisInstance
                Folder      = $environmentFolder
                Environment = $whatIfEnvironment
                WhatIf      = $true
            }
            $whatIfResult = @(New-DbaSsisEnvironment @splatWhatIf)
            $whatIfResult.Count | Should -Be 0
            (Get-SsisEnvironmentRow -Folder $environmentFolder -Environment $whatIfEnvironment).Count | Should -Be 0
        }
    }

    Context "Each environment succeeds or fails on its own" {
        It "Errors on the name that already exists and still creates the rest" {
            # Without -EnableException the failure surfaces as the friendly warning, not an error
            # record, so -ErrorVariable would come back empty and prove nothing.
            $splatMixed = @{
                SqlInstance     = $ssisInstance
                Folder          = $environmentFolder
                Environment     = @($existingEnvironment, $survivorEnvironment)
                EnableException = $false
                WarningVariable = "environmentWarnings"
                WarningAction   = "SilentlyContinue"
            }
            $mixed = @(New-DbaSsisEnvironment @splatMixed)
            $mixed.Count | Should -Be 1
            $mixed[0].Name | Should -Be $survivorEnvironment
            ($environmentWarnings -join " ") | Should -BeLike "*$existingEnvironment*"
        }
    }

    Context "A folder that does not exist" {
        It "Refuses rather than creating the folder" {
            $splatMissingFolder = @{
                SqlInstance = $ssisInstance
                Folder      = "dbatoolsci_envnosuchfolder"
                Environment = "dbatoolsci_envorphan"
            }
            { New-DbaSsisEnvironment @splatMissingFolder } | Should -Throw "*dbatoolsci_envnosuchfolder*"

            $splatFolderCheck = @{
                SqlInstance  = $ssisInstance
                Database     = "SSISDB"
                Query        = "SELECT COUNT(*) AS folders FROM [catalog].[folders] WHERE name = @folder"
                SqlParameter = @{ folder = "dbatoolsci_envnosuchfolder" }
            }
            (Invoke-DbaQuery @splatFolderCheck).folders | Should -Be 0
        }
    }

    Context "An instance with no SSIS catalog" {
        # InstanceSingle carries no SSISDB, so this exercises the presence check rather than
        # failing inside the catalog schema.
        It "Warns and returns nothing" {
            $splatNoCatalog = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $environmentFolder
                Environment     = "dbatoolsci_envnocatalog"
                EnableException = $false
                WarningVariable = "warn"
                WarningAction   = "SilentlyContinue"
            }
            $none = @(New-DbaSsisEnvironment @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            $splatNoCatalogThrow = @{
                SqlInstance     = $TestConfig.InstanceSingle
                Folder          = $environmentFolder
                Environment     = "dbatoolsci_envnocatalog"
                EnableException = $true
            }
            { New-DbaSsisEnvironment @splatNoCatalogThrow } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
