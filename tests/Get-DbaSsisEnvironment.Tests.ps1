#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaSsisEnvironment",
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
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Should expose Name as an alias of Environment" {
            (Get-Command $CommandName).Parameters["Environment"].Aliases | Should -Contain "Name"
        }

        It "Should not declare ShouldProcess" {
            (Get-Command $CommandName).Parameters.Keys | Should -Not -Contain "WhatIf"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*:EnableException"] = $true

        $ssisInstance      = $TestConfig.InstanceSsis
        $environmentFolder = "dbatoolsci_ssisenvfolder"
        # The sibling names have the first as an exact prefix: a LIKE or wildcard implementation of
        # -Folder or -Environment would return both, an exact-name implementation returns only the first.
        $siblingFolder      = "dbatoolsci_ssisenvfolder2"
        $environmentName    = "dbatoolsci_ssisenv"
        $siblingEnvironment = "dbatoolsci_ssisenv2"
        $environmentComment = "dbatools environment read fixture"

        $splatSetup = @{
            SqlInstance  = $ssisInstance
            Database     = "SSISDB"
            Query        = "
                IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @firstFolder)
                    EXEC [catalog].[create_folder] @folder_name = @firstFolder, @folder_id = NULL;
                IF NOT EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @secondFolder)
                    EXEC [catalog].[create_folder] @folder_name = @secondFolder, @folder_id = NULL;
                IF NOT EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE e.name = @firstEnv AND f.name = @firstFolder)
                    EXEC [catalog].[create_environment] @folder_name = @firstFolder, @environment_name = @firstEnv, @environment_description = @comment;
                IF NOT EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE e.name = @secondEnv AND f.name = @firstFolder)
                    EXEC [catalog].[create_environment] @folder_name = @firstFolder, @environment_name = @secondEnv, @environment_description = @comment;
                IF NOT EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE e.name = @firstEnv AND f.name = @secondFolder)
                    EXEC [catalog].[create_environment] @folder_name = @secondFolder, @environment_name = @firstEnv, @environment_description = @comment;"
            SqlParameter = @{
                firstFolder  = $environmentFolder
                secondFolder = $siblingFolder
                firstEnv     = $environmentName
                secondEnv    = $siblingEnvironment
                comment      = $environmentComment
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
                IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE e.name = @firstEnv AND f.name = @firstFolder)
                    EXEC [catalog].[delete_environment] @folder_name = @firstFolder, @environment_name = @firstEnv;
                IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE e.name = @secondEnv AND f.name = @firstFolder)
                    EXEC [catalog].[delete_environment] @folder_name = @firstFolder, @environment_name = @secondEnv;
                IF EXISTS (SELECT 1 FROM [catalog].[environments] e JOIN [catalog].[folders] f ON f.folder_id = e.folder_id WHERE e.name = @firstEnv AND f.name = @secondFolder)
                    EXEC [catalog].[delete_environment] @folder_name = @secondFolder, @environment_name = @firstEnv;
                IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @firstFolder)
                    EXEC [catalog].[delete_folder] @folder_name = @firstFolder;
                IF EXISTS (SELECT 1 FROM [catalog].[folders] WHERE name = @secondFolder)
                    EXEC [catalog].[delete_folder] @folder_name = @secondFolder;"
            SqlParameter = @{
                firstFolder  = "dbatoolsci_ssisenvfolder"
                secondFolder = "dbatoolsci_ssisenvfolder2"
                firstEnv     = "dbatoolsci_ssisenv"
                secondEnv    = "dbatoolsci_ssisenv2"
            }
        }
        Invoke-DbaQuery @splatTeardown
    }

    Context "Reading the catalog" {
        It "Returns every fixture environment when unfiltered" {
            $allEnvironments = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance)
            $allEnvironments.Name | Should -Contain $environmentName
            $allEnvironments.Name | Should -Contain $siblingEnvironment
        }

        It "Returns the verified catalog.environments columns" {
            $single = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Environment $environmentName)
            $single.Count | Should -Be 1
            $single[0].Name | Should -Be $environmentName
            $single[0].FolderName | Should -Be $environmentFolder
            $single[0].Description | Should -Be $environmentComment
            $single[0].EnvironmentId | Should -BeGreaterThan 0
            $single[0].FolderId | Should -BeGreaterThan 0
            $single[0].CreatedByName | Should -Not -BeNullOrEmpty
            $single[0].CreatedTime | Should -Not -BeNullOrEmpty
        }

        It "Accepts the instance from the pipeline" {
            $piped = @($ssisInstance | Get-DbaSsisEnvironment -Folder $environmentFolder -Environment $environmentName)
            $piped.Count | Should -Be 1
            $piped[0].Name | Should -Be $environmentName
        }

        It "Processes every piped instance record" {
            $repeated = @($ssisInstance, $ssisInstance | Get-DbaSsisEnvironment -Folder $environmentFolder -Environment $environmentName)
            $repeated.Count | Should -Be 2
        }

        It "Accepts several environment names at once" {
            $both = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Environment $environmentName, $siblingEnvironment)
            $both.Count | Should -Be 2
        }

        It "Binds -Name as an alias of -Environment" {
            $viaAlias = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Name $environmentName)
            $viaAlias.Count | Should -Be 1
            $viaAlias[0].Name | Should -Be $environmentName
        }
    }

    Context "-Environment and -Folder are exact name lists" {
        It "Does not return the environment whose name merely starts with the requested one" {
            $exact = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Environment $environmentName)
            $exact.Name | Should -Not -Contain $siblingEnvironment
        }

        It "Treats a LIKE metacharacter in -Environment as a literal, returning nothing" {
            $withPercent = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Environment "$environmentName%")
            $withPercent.Count | Should -Be 0
        }

        It "Treats a wildcard in -Environment as a literal, returning nothing" {
            $withStar = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Environment "$environmentName*")
            $withStar.Count | Should -Be 0
        }

        It "Does not return environments from the folder whose name merely starts with the requested one" {
            $oneFolder = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder)
            $oneFolder.Count | Should -Be 2
            $oneFolder.FolderName | Should -Not -Contain $siblingFolder
        }

        It "Reports the folder each environment actually lives in" {
            $sameNameTwice = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder, $siblingFolder -Environment $environmentName)
            $sameNameTwice.Count | Should -Be 2
            $sameNameTwice.FolderName | Should -Contain $environmentFolder
            $sameNameTwice.FolderName | Should -Contain $siblingFolder
            ($sameNameTwice | Where-Object FolderName -eq $siblingFolder).Name | Should -Be $environmentName
        }

        It "Gives each returned environment its own identity" {
            $multiple = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder)
            $multiple.Count | Should -Be 2
            ($multiple.EnvironmentId | Sort-Object -Unique).Count | Should -Be 2
            ($multiple.Name | Sort-Object -Unique).Count | Should -Be 2
        }
    }

    Context "Feeding the variable command" {
        # Get-DbaSsisEnvironmentVariable goes through the Integration Services object model and
        # refuses to run on PowerShell Core, so the composition is asserted on the values and the
        # parameter names rather than by calling it - a call here would only be green on 5.1.
        It "Emits folder and environment names that Get-DbaSsisEnvironmentVariable takes verbatim" {
            $environment = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Environment $environmentName)[0]
            $environment.FolderName | Should -BeOfType [string]
            $environment.Name | Should -BeOfType [string]
            $environment.FolderName | Should -Be $environmentFolder
            $environment.Name | Should -Be $environmentName
            $variableParameters = (Get-Command -Name Get-DbaSsisEnvironmentVariable).Parameters
            $variableParameters.Keys | Should -Contain "Folder"
            $variableParameters.Keys | Should -Contain "Environment"
        }
    }

    Context "Output decoration" {
        It "Carries the instance property triple" {
            $decorated = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Environment $environmentName)[0]
            $decorated.ComputerName | Should -Not -BeNullOrEmpty
            $decorated.InstanceName | Should -Not -BeNullOrEmpty
            $decorated.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Carries the dbatools.SsisEnvironment type name" {
            $decorated = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Environment $environmentName)[0]
            $decorated.PSObject.TypeNames[0] | Should -Be "dbatools.SsisEnvironment"
        }

        It "Keeps EnvironmentId on the object but off the default view" {
            $decorated = @(Get-DbaSsisEnvironment -SqlInstance $ssisInstance -Folder $environmentFolder -Environment $environmentName)[0]
            $displaySet = $decorated.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $displaySet | Should -Contain "FolderName"
            $displaySet | Should -Contain "CreatedTime"
            $displaySet | Should -Not -Contain "EnvironmentId"
            $decorated.PSObject.Properties.Name | Should -Contain "EnvironmentId"
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
            $none = @(Get-DbaSsisEnvironment @splatNoCatalog)
            $none.Count | Should -Be 0
            ($warn -join " ") | Should -BeLike "*No SSIS catalog (SSISDB) found*"
        }

        It "Throws under -EnableException" {
            { Get-DbaSsisEnvironment -SqlInstance $TestConfig.InstanceSingle -EnableException } | Should -Throw "*No SSIS catalog (SSISDB) found*"
        }
    }
}
