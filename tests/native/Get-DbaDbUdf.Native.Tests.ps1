#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbUdf",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- read-only command without SupportsShouldProcess or WhatIf/Confirm parameters.

Describe "Native user-defined function behavior" -Tag IntegrationTests {
    BeforeAll {
        $nativeUdfCreated = @()
        $nativeUdfServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeUdfSuffix = [Guid]::NewGuid().ToString("N")
        $nativeUdfDatabaseName = "native_udf_" + $nativeUdfSuffix
        $nativeUdfEmptyName = "native_udf_empty_" + $nativeUdfSuffix
        foreach ($nativeUdfName in $nativeUdfDatabaseName, $nativeUdfEmptyName) {
            $nativeUdfNew = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeUdfServer, $nativeUdfName
            $nativeUdfNew.Create()
            $nativeUdfCreated += $nativeUdfName
        }
        $nativeUdfDatabase = $nativeUdfServer.Databases[$nativeUdfDatabaseName]
        $nativeUdfDatabase.ExecuteNonQuery("CREATE SCHEMA [native_other];")
        $nativeUdfDatabase.ExecuteNonQuery("CREATE FUNCTION [dbo].[native_scalar] (@value int) RETURNS int AS BEGIN RETURN @value + 1; END;")
        $nativeUdfDatabase.ExecuteNonQuery("CREATE FUNCTION [native_other].[native_table] () RETURNS TABLE AS RETURN (SELECT 1 AS [value]);")
        $nativeUdfDisplay = "ComputerName,InstanceName,SqlInstance,Database,Schema,CreateDate,DateLastModified,Name,DataType"
    }

    AfterAll {
        if ($nativeUdfCreated) {
            $splatRemoveNativeUdfDatabase = @{
                SqlInstance     = $nativeUdfServer
                Database        = $nativeUdfCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeUdfDatabase
        }
    }

    It "decorates every function with instance, database and display metadata across repeated pipeline records" -Tag "NativeChecklist:pipeline-multiple" {
        $splatNativeUdfRead = @{
            Database         = $nativeUdfDatabaseName, $nativeUdfEmptyName
            ExcludeSystemUdf = $true
            EnableException  = $true
            Verbose          = $true
        }
        $nativeUdfMessages = @(@($nativeUdfServer, $nativeUdfServer) | Get-DbaDbUdf @splatNativeUdfRead 4>&1)
        $nativeUdfRows = @($nativeUdfMessages | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.UserDefinedFunction] })
        $nativeUdfRows.Count | Should -Be 4
        (@($nativeUdfRows.Name | Sort-Object -Unique) -join ",") | Should -BeExactly "native_scalar,native_table"
        foreach ($nativeUdfRow in $nativeUdfRows) {
            $nativeUdfRow.Database | Should -BeExactly $nativeUdfDatabaseName
            $nativeUdfRow.ComputerName | Should -BeExactly $nativeUdfServer.ComputerName
            $nativeUdfRow.InstanceName | Should -BeExactly $nativeUdfServer.ServiceName
            $nativeUdfRow.SqlInstance | Should -BeExactly $nativeUdfServer.DomainInstanceName
            ($nativeUdfRow.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $nativeUdfDisplay
            @($nativeUdfRow.PSObject.Properties | Where-Object Name -eq "Database").Count | Should -Be 1
        }
        @($nativeUdfRows | Where-Object Name -eq "native_scalar" | Where-Object Schema -eq "dbo").Count | Should -Be 2
        @($nativeUdfRows | Where-Object Name -eq "native_table" | Where-Object Schema -eq "native_other").Count | Should -Be 2
        $nativeUdfEmptyMessages = @($nativeUdfMessages | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message -like "*No User Defined Functions or Aggregates exist in the ``[$nativeUdfEmptyName``] database on *" })
        $nativeUdfEmptyMessages.Count | Should -Be 2
    }

    It "applies literal case-insensitive database, schema and name filters with exclusions taking precedence" {
        $splatNativeUdfFilter = @{
            SqlInstance     = $nativeUdfServer
            Database        = $nativeUdfDatabaseName.ToUpperInvariant()
            EnableException = $true
        }
        # SMO lists the sys schema functions of every database too, so without -ExcludeSystemUdf they come back.
        @(Get-DbaDbUdf @splatNativeUdfFilter | Where-Object IsSystemObject).Count | Should -BeGreaterThan 0
        $splatNativeUdfFilter.ExcludeSystemUdf = $true
        @(Get-DbaDbUdf @splatNativeUdfFilter).Count | Should -Be 2
        $nativeUdfSchemaRows = @(Get-DbaDbUdf @splatNativeUdfFilter -Schema "NATIVE_OTHER")
        $nativeUdfSchemaRows.Count | Should -Be 1
        $nativeUdfSchemaRows[0].Name | Should -BeExactly "native_table"
        $nativeUdfNameRows = @(Get-DbaDbUdf @splatNativeUdfFilter -Name "NATIVE_SCALAR", "native_table" -ExcludeSchema "native_other")
        $nativeUdfNameRows.Count | Should -Be 1
        $nativeUdfNameRows[0].Name | Should -BeExactly "native_scalar"
        @(Get-DbaDbUdf @splatNativeUdfFilter -ExcludeName "native_scalar", "native_table").Count | Should -Be 0
        @(Get-DbaDbUdf @splatNativeUdfFilter -ExcludeDatabase $nativeUdfDatabaseName).Count | Should -Be 0
    }

    It "excludes system functions only when the ExcludeSystemUdf switch value is true" -Tag "NativeChecklist:switch-false" {
        $splatNativeUdfSystem = @{
            SqlInstance     = $nativeUdfServer
            Database        = "msdb"
            EnableException = $true
        }
        $nativeUdfAll = @(Get-DbaDbUdf @splatNativeUdfSystem -ExcludeSystemUdf:$false)
        @($nativeUdfAll | Where-Object IsSystemObject).Count | Should -BeGreaterThan 0
        $nativeUdfDefault = @(Get-DbaDbUdf @splatNativeUdfSystem)
        $nativeUdfDefault.Count | Should -Be $nativeUdfAll.Count
        $nativeUdfUser = @(Get-DbaDbUdf @splatNativeUdfSystem -ExcludeSystemUdf)
        @($nativeUdfUser | Where-Object { $PSItem -is [Microsoft.SqlServer.Management.Smo.UserDefinedFunction] -and $PSItem.IsSystemObject }).Count | Should -Be 0
        $nativeUdfUser.Count | Should -BeLessThan $nativeUdfAll.Count
    }

    Context "Documented wildcard database and function name selection" {
        BeforeAll {
            # Pinned help :20 documents wildcards for -Database, :40 for -Name and :44 for -ExcludeName; the
            # source filters with literal -In, -in and -notin (:144, :191, :195), so the documented forms never
            # took effect. -ExcludeDatabase, -Schema and -ExcludeSchema document no wildcards and stay literal.
            $nativeUdfWildcardPrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeUdfWildcardNames = @(
                "${nativeUdfWildcardPrefix}_a"
                "${nativeUdfWildcardPrefix}_b"
                "${nativeUdfWildcardPrefix}_[a]"
            )
            $nativeUdfWildcardFunctions = @("native_wc_name_a", "native_wc_name_b", "native_wc_name_[a]")
            $nativeUdfWildcardCreated = New-Object System.Collections.Generic.List[string]
            foreach ($nativeUdfWildcardName in $nativeUdfWildcardNames) {
                $nativeUdfWildcardDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeUdfServer, $nativeUdfWildcardName
                $nativeUdfWildcardDatabase.Create()
                $nativeUdfWildcardCreated.Add($nativeUdfWildcardName)
                $nativeUdfWildcardDatabase.ExecuteNonQuery("CREATE FUNCTION [dbo].[native_wc_fn] (@value int) RETURNS int AS BEGIN RETURN @value; END;")
            }
            $nativeUdfWildcardFirst = $nativeUdfServer.Databases[$nativeUdfWildcardNames[0]]
            foreach ($nativeUdfWildcardFunction in $nativeUdfWildcardFunctions) {
                $nativeUdfWildcardQuoted = $nativeUdfWildcardFunction.Replace("]", "]]")
                $nativeUdfWildcardFirst.ExecuteNonQuery("CREATE FUNCTION [dbo].[$nativeUdfWildcardQuoted] (@value int) RETURNS int AS BEGIN RETURN @value; END;")
            }
        }

        AfterAll {
            $nativeUdfServer.Databases.Refresh()
            foreach ($nativeUdfWildcardName in $nativeUdfWildcardCreated) {
                if ($nativeUdfServer.Databases[$nativeUdfWildcardName]) {
                    $nativeUdfServer.KillDatabase($nativeUdfWildcardName)
                }
            }
        }

        It "selects databases by a documented wildcard pattern" {
            $splatNativeUdfWildcard = @{
                SqlInstance     = $nativeUdfServer
                Database        = "${nativeUdfWildcardPrefix}_*"
                Name            = "native_wc_fn"
                EnableException = $true
            }
            $nativeUdfWildcardRows = @(Get-DbaDbUdf @splatNativeUdfWildcard)
            (($nativeUdfWildcardRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfWildcardNames | Sort-Object) -join ",")
            $splatNativeUdfWildcard.Database = "${nativeUdfWildcardPrefix}_?"
            $nativeUdfWildcardRows = @(Get-DbaDbUdf @splatNativeUdfWildcard)
            (($nativeUdfWildcardRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfWildcardNames[0, 1] | Sort-Object) -join ",")
        }

        It "selects functions by a documented -Name wildcard pattern" {
            $splatNativeUdfName = @{
                SqlInstance     = $nativeUdfServer
                Database        = $nativeUdfWildcardNames[0]
                Name            = "native_wc_name_*"
                EnableException = $true
            }
            $nativeUdfNameRows = @(Get-DbaDbUdf @splatNativeUdfName)
            (($nativeUdfNameRows.Name | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfWildcardFunctions | Sort-Object) -join ",")
            $splatNativeUdfName.Name = "native_wc_name_?"
            $nativeUdfNameRows = @(Get-DbaDbUdf @splatNativeUdfName)
            (($nativeUdfNameRows.Name | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfWildcardFunctions[0, 1] | Sort-Object) -join ",")
        }

        It "excludes functions by a documented -ExcludeName wildcard pattern" {
            $splatNativeUdfExcludeName = @{
                SqlInstance     = $nativeUdfServer
                Database        = $nativeUdfWildcardNames[0]
                Name            = $nativeUdfWildcardFunctions
                ExcludeName     = "native_wc_name_?"
                EnableException = $true
            }
            $nativeUdfExcludeNameRows = @(Get-DbaDbUdf @splatNativeUdfExcludeName)
            ($nativeUdfExcludeNameRows.Name -join ",") | Should -BeExactly $nativeUdfWildcardFunctions[2]
        }

        It "keeps bracket-only, invalid and undocumented filter values literal" {
            $splatNativeUdfLiteral = @{
                SqlInstance     = $nativeUdfServer
                Database        = $nativeUdfWildcardNames[2]
                Name            = "native_wc_fn"
                EnableException = $true
            }
            ($(@(Get-DbaDbUdf @splatNativeUdfLiteral).Database) -join ",") | Should -BeExactly $nativeUdfWildcardNames[2]
            $splatNativeUdfLiteral.Database = "${nativeUdfWildcardPrefix}_[*"
            @(Get-DbaDbUdf @splatNativeUdfLiteral).Count | Should -Be 0
            $splatNativeUdfLiteral.Database = $nativeUdfWildcardNames
            $splatNativeUdfLiteral.ExcludeDatabase = "${nativeUdfWildcardPrefix}_?"
            (($(@(Get-DbaDbUdf @splatNativeUdfLiteral).Database) | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfWildcardNames | Sort-Object) -join ",")
            $splatNativeUdfLiteral.Remove("ExcludeDatabase")
            $splatNativeUdfLiteral.Schema = "db?"
            @(Get-DbaDbUdf @splatNativeUdfLiteral).Count | Should -Be 0
            $splatNativeUdfLiteral.Remove("Schema")
            $splatNativeUdfLiteral.Database = $nativeUdfWildcardNames[0]
            $splatNativeUdfLiteral.Name = $nativeUdfWildcardFunctions[2]
            ($(@(Get-DbaDbUdf @splatNativeUdfLiteral).Name) -join ",") | Should -BeExactly $nativeUdfWildcardFunctions[2]
            $splatNativeUdfLiteral.Name = "native_wc_name_[*"
            @(Get-DbaDbUdf @splatNativeUdfLiteral).Count | Should -Be 0
            $splatNativeUdfLiteral.Name = $nativeUdfWildcardFunctions
            $splatNativeUdfLiteral.ExcludeName = $nativeUdfWildcardFunctions[2]
            (($(@(Get-DbaDbUdf @splatNativeUdfLiteral).Name) | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfWildcardFunctions[0, 1] | Sort-Object) -join ",")
        }
    }

    Context "Real database names containing wildcard characters" {
        BeforeAll {
            # Rule E+ (pinned help :20 documents -Database wildcards, :40 and :44 -Name and -ExcludeName wildcards; pinned Remove-DbaDbUdf.ps1:136, Set-DbaResourceGovernor.ps1:137 and Uninstall-DbaSqlWatch.ps1:85-86 pass caller or real names): a value equal to a real database name stays
            # literal, so a caller passing a real name containing * or ? never reaches other databases.
            function New-NativeWildcardNameDatabase {
                param($Server, [string]$Name, [string]$FileStem)
                # Names with * or ? are not valid Windows file names, so the files get explicit names.
                $dataDirectory = $Server.DefaultFile
                if (-not $dataDirectory) { $dataDirectory = $Server.MasterDBPath }
                $logDirectory = $Server.DefaultLog
                if (-not $logDirectory) { $logDirectory = $Server.MasterDBLogPath }
                $separator = "\"
                if ($dataDirectory -match "/" -and $dataDirectory -notmatch "\\") { $separator = "/" }
                $database = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $Server, $Name
                $fileGroup = New-Object Microsoft.SqlServer.Management.Smo.FileGroup -ArgumentList $database, "PRIMARY"
                $database.FileGroups.Add($fileGroup)
                $dataPath = $dataDirectory.TrimEnd("\", "/") + $separator + $FileStem + ".mdf"
                $dataFile = New-Object Microsoft.SqlServer.Management.Smo.DataFile -ArgumentList $fileGroup, ($FileStem + "_data"), $dataPath
                $dataFile.IsPrimaryFile = $true
                $fileGroup.Files.Add($dataFile)
                $logPath = $logDirectory.TrimEnd("\", "/") + $separator + $FileStem + "_log.ldf"
                $logFile = New-Object Microsoft.SqlServer.Management.Smo.LogFile -ArgumentList $database, ($FileStem + "_log"), $logPath
                $database.LogFiles.Add($logFile)
                $database.Create()
                $database
            }
            $nativeUdfRealNamePrefix = "native_wc_" + [Guid]::NewGuid().ToString("N")
            $nativeUdfRealNameNames = @("${nativeUdfRealNamePrefix}_*", "${nativeUdfRealNamePrefix}_?", "${nativeUdfRealNamePrefix}_x")
            $nativeUdfRealNameCreated = New-Object System.Collections.Generic.List[string]
            $nativeUdfRealNameFunctions = @("native_wcfn_*", "native_wcfn_?", "native_wcfn_x")
            foreach ($nativeUdfRealNameIndex in 0, 1, 2) {
                $nativeUdfRealNameName = $nativeUdfRealNameNames[$nativeUdfRealNameIndex]
                $nativeUdfRealNameDatabase = New-NativeWildcardNameDatabase -Server $nativeUdfServer -Name $nativeUdfRealNameName -FileStem ("${nativeUdfRealNamePrefix}_file" + $nativeUdfRealNameIndex)
                $nativeUdfRealNameCreated.Add($nativeUdfRealNameName)
                $nativeUdfRealNameDatabase.ExecuteNonQuery("CREATE FUNCTION [dbo].[native_wc_fn] (@value int) RETURNS int AS BEGIN RETURN @value; END;")
            }
            $nativeUdfRealNameFunctionDatabase = $nativeUdfServer.Databases[$nativeUdfRealNameNames[2]]
            foreach ($nativeUdfRealNameFunction in $nativeUdfRealNameFunctions) {
                $nativeUdfRealNameFunctionDatabase.ExecuteNonQuery("CREATE FUNCTION [dbo].[$nativeUdfRealNameFunction] (@value int) RETURNS int AS BEGIN RETURN @value; END;")
            }
        }

        AfterAll {
            $nativeUdfServer.Databases.Refresh()
            foreach ($nativeUdfRealNameName in $nativeUdfRealNameCreated) {
                if ($nativeUdfServer.Databases[$nativeUdfRealNameName]) {
                    $nativeUdfServer.KillDatabase($nativeUdfRealNameName)
                }
            }
        }

        It "selects a real database whose name contains * or ? alone by its exact name" {
            $splatNativeUdfRealNameExact = @{
                SqlInstance     = $nativeUdfServer
                Database        = $nativeUdfRealNameNames[0]
                Name            = "native_wc_fn"
                EnableException = $true
            }
            $nativeUdfRealNameRows = @(Get-DbaDbUdf @splatNativeUdfRealNameExact)
            (($nativeUdfRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly $nativeUdfRealNameNames[0]
            $splatNativeUdfRealNameExact.Database = $nativeUdfRealNameNames[1].ToUpperInvariant()
            $nativeUdfRealNameRows = @(Get-DbaDbUdf @splatNativeUdfRealNameExact)
            (($nativeUdfRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly $nativeUdfRealNameNames[1]
            $splatNativeUdfRealNameExact.Database = $nativeUdfRealNameNames[0, 1]
            $nativeUdfRealNameRows = @(Get-DbaDbUdf @splatNativeUdfRealNameExact)
            (($nativeUdfRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfRealNameNames[0, 1] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside databases whose names contain * or ?" {
            $splatNativeUdfRealNamePattern = @{
                SqlInstance     = $nativeUdfServer
                Database        = "${nativeUdfRealNamePrefix}*"
                Name            = "native_wc_fn"
                EnableException = $true
            }
            $nativeUdfRealNameRows = @(Get-DbaDbUdf @splatNativeUdfRealNamePattern)
            (($nativeUdfRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfRealNameNames | Sort-Object) -join ",")
            # -ExcludeDatabase documents no wildcards, so a real name in it stays literal.
            $splatNativeUdfRealNamePattern.ExcludeDatabase = $nativeUdfRealNameNames[1]
            $nativeUdfRealNameRows = @(Get-DbaDbUdf @splatNativeUdfRealNamePattern)
            (($nativeUdfRealNameRows.Database | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfRealNameNames[0, 2] | Sort-Object) -join ",")
        }

        It "selects a real function whose name contains * or ? alone by its exact name" {
            $splatNativeUdfRealNameFunction = @{
                SqlInstance     = $nativeUdfServer
                Database        = $nativeUdfRealNameNames[2]
                Name            = $nativeUdfRealNameFunctions[0]
                EnableException = $true
            }
            (@(Get-DbaDbUdf @splatNativeUdfRealNameFunction).Name -join ",") | Should -BeExactly $nativeUdfRealNameFunctions[0]
            $splatNativeUdfRealNameFunction.Name = $nativeUdfRealNameFunctions[1].ToUpperInvariant()
            (@(Get-DbaDbUdf @splatNativeUdfRealNameFunction).Name -join ",") | Should -BeExactly $nativeUdfRealNameFunctions[1]
            $splatNativeUdfRealNameFunction.Name = $nativeUdfRealNameFunctions[0, 1]
            ((@(Get-DbaDbUdf @splatNativeUdfRealNameFunction).Name | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfRealNameFunctions[0, 1] | Sort-Object) -join ",")
        }

        It "excludes only a real function whose name contains * or ? when its exact name is excluded" {
            $splatNativeUdfRealNameExcludeName = @{
                SqlInstance     = $nativeUdfServer
                Database        = $nativeUdfRealNameNames[2]
                Name            = $nativeUdfRealNameFunctions
                ExcludeName     = $nativeUdfRealNameFunctions[1]
                EnableException = $true
            }
            ((@(Get-DbaDbUdf @splatNativeUdfRealNameExcludeName).Name | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfRealNameFunctions[0, 2] | Sort-Object) -join ",")
        }

        It "expands a non-colliding pattern beside functions whose names contain * or ?" {
            $splatNativeUdfRealNameFunctionPattern = @{
                SqlInstance     = $nativeUdfServer
                Database        = $nativeUdfRealNameNames[2]
                Name            = "native_wcfn*"
                EnableException = $true
            }
            ((@(Get-DbaDbUdf @splatNativeUdfRealNameFunctionPattern).Name | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfRealNameFunctions | Sort-Object) -join ",")
            $splatNativeUdfRealNameFunctionPattern.ExcludeName = $nativeUdfRealNameFunctions[1]
            ((@(Get-DbaDbUdf @splatNativeUdfRealNameFunctionPattern).Name | Sort-Object) -join ",") | Should -BeExactly (($nativeUdfRealNameFunctions[0, 2] | Sort-Object) -join ",")
        }
    }

    It "continues after connection failure unless EnableException terminates while retaining earlier output" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
        $nativeUdfSavedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
        $nativeUdfListener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
        try {
            $nativeUdfListener.Start()
            $nativeUdfFailedInstance = "127.0.0.1," + $nativeUdfListener.LocalEndpoint.Port
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
            $nativeUdfWarnings = @()
            $nativeUdfPreviousErrors = @($global:Error)
            $splatNativeUdfFailure = @{
                Database        = $nativeUdfDatabaseName
                Name            = "native_scalar"
                EnableException = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "nativeUdfWarnings"
            }
            $nativeUdfContinued = @(@($nativeUdfServer, $nativeUdfFailedInstance, $nativeUdfServer) | Get-DbaDbUdf @splatNativeUdfFailure)
            $nativeUdfContinued.Count | Should -Be 2
            @($nativeUdfContinued | Where-Object Name -ne "native_scalar").Count | Should -Be 0
            ($nativeUdfWarnings -join " ") | Should -BeLike "*Failure*"
            $nativeUdfConnectionError = $global:Error | Where-Object {
                $nativeUdfPreviousErrors -notcontains $PSItem -and $PSItem.FullyQualifiedErrorId -like "dbatools_Get-DbaDbUdf*"
            } | Select-Object -First 1
            $nativeUdfConnectionError | Should -Not -BeNullOrEmpty
            $nativeUdfConnectionError.CategoryInfo.Category | Should -Be "ConnectionError"

            $nativeUdfEarlier = New-Object "System.Collections.Generic.List[object]"
            $nativeUdfCaught = $null
            $splatNativeUdfFailure.EnableException = $true
            try {
                @($nativeUdfServer, $nativeUdfFailedInstance, $nativeUdfServer) |
                    Get-DbaDbUdf @splatNativeUdfFailure |
                    ForEach-Object { $nativeUdfEarlier.Add($PSItem) }
            } catch {
                $nativeUdfCaught = $PSItem
            }
            $nativeUdfEarlier.Count | Should -Be 1
            $nativeUdfEarlier[0].Name | Should -BeExactly "native_scalar"
            $nativeUdfCaught | Should -Not -BeNullOrEmpty
            $nativeUdfCaught.CategoryInfo.Category | Should -Be "ConnectionError"
            [string]$nativeUdfCaught.TargetObject | Should -Be $nativeUdfFailedInstance
        } finally {
            [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $nativeUdfSavedTimeout
            $nativeUdfListener.Stop()
        }
    }
}

Describe "Native Get-DbaDbUdf numeric database selection" -Tag IntegrationTests {
    BeforeAll {
        $nativeUdfNumberServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeUdfNumber = Get-Random -Minimum 100000000 -Maximum 999999999
        $nativeUdfNumberNames = @("0$nativeUdfNumber", "$nativeUdfNumber")
        $nativeUdfNumberCreated = @()
        foreach ($nativeUdfNumberName in $nativeUdfNumberNames) {
            $nativeUdfNumberDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $nativeUdfNumberServer, $nativeUdfNumberName
            $nativeUdfNumberDatabase.Create()
            $nativeUdfNumberCreated += $nativeUdfNumberName
            $nativeUdfNumberDatabase.ExecuteNonQuery("CREATE FUNCTION [dbo].[native_number_scalar] (@value int) RETURNS int AS BEGIN RETURN @value + 1; END;")
        }
    }

    AfterAll {
        if ($nativeUdfNumberCreated.Count -gt 0) {
            $splatRemoveNativeUdfNumberDatabase = @{
                SqlInstance     = $nativeUdfNumberServer
                Database        = $nativeUdfNumberCreated
                Confirm         = $false
                EnableException = $true
            }
            Remove-DbaDatabase @splatRemoveNativeUdfNumberDatabase
        }
    }

    It "converts each database name to the type of a numeric selection value, as Where-Object -In does" {
        $splatNativeUdfNumberInclude = @{
            SqlInstance     = $nativeUdfNumberServer
            Database        = [int]$nativeUdfNumber
            Name            = "native_number_scalar"
            EnableException = $true
        }
        $nativeUdfNumberIncluded = @(Get-DbaDbUdf @splatNativeUdfNumberInclude)
        (($nativeUdfNumberIncluded.Database | Sort-Object -Unique) -join ",") | Should -BeExactly (($nativeUdfNumberNames | Sort-Object) -join ",")

        $splatNativeUdfNumberExclude = @{
            SqlInstance     = $nativeUdfNumberServer
            Database        = $nativeUdfNumberNames
            ExcludeDatabase = [int]$nativeUdfNumber
            Name            = "native_number_scalar"
            EnableException = $true
        }
        @(Get-DbaDbUdf @splatNativeUdfNumberExclude).Count | Should -Be 0
    }
}

Describe "Native Get-DbaDbUdf caller guard for Set-DbaResourceGovernor" -Tag IntegrationTests {
    BeforeAll {
        # Pinned Set-DbaResourceGovernor help documents -ClassifierFunction without wildcards, and its :137
        # forwards the value to Get-DbaDbUdf -Name, whose documented wildcards are now honoured. The caller
        # escapes a value containing * or ?, so a pattern-like name that is no real function still reports
        # that it does not exist instead of matching other functions.
        $nativeUdfGuardServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $nativeUdfGuardPrefix = "native_rg_" + [Guid]::NewGuid().ToString("N")
        $nativeUdfGuardFunctions = @("${nativeUdfGuardPrefix}_x", "${nativeUdfGuardPrefix}_y")
        $nativeUdfGuardCreated = New-Object System.Collections.Generic.List[string]
        $nativeUdfGuardMaster = $nativeUdfGuardServer.Databases["master"]
        foreach ($nativeUdfGuardFunction in $nativeUdfGuardFunctions) {
            $nativeUdfGuardMaster.ExecuteNonQuery("CREATE FUNCTION [dbo].[$nativeUdfGuardFunction]() RETURNS sysname WITH SCHEMABINDING AS BEGIN RETURN N'default'; END;")
            $nativeUdfGuardCreated.Add($nativeUdfGuardFunction)
        }
        $nativeUdfGuardDirect = $nativeUdfGuardServer.ResourceGovernor
        $nativeUdfGuardDirect.Refresh()
        $nativeUdfGuardOriginal = [string]$nativeUdfGuardDirect.ClassifierFunction
    }

    AfterAll {
        foreach ($nativeUdfGuardFunction in $nativeUdfGuardCreated) {
            $nativeUdfGuardMaster.ExecuteNonQuery("IF OBJECT_ID(N'[dbo].[$nativeUdfGuardFunction]') IS NOT NULL DROP FUNCTION [dbo].[$nativeUdfGuardFunction];")
        }
    }

    It "keeps a pattern-like classifier function name literal and alters nothing" {
        $nativeUdfGuardPattern = "${nativeUdfGuardPrefix}_*"
        $nativeUdfGuardWarnings = @()
        $splatNativeUdfGuard = @{
            SqlInstance        = $nativeUdfGuardServer
            ClassifierFunction = $nativeUdfGuardPattern
            EnableException    = $false
            WarningAction      = "SilentlyContinue"
            WarningVariable    = "nativeUdfGuardWarnings"
        }
        @(Set-DbaResourceGovernor @splatNativeUdfGuard).Count | Should -Be 0
        ($nativeUdfGuardWarnings -join " ") | Should -BeLike "*Classifier function '${nativeUdfGuardPrefix}_``*' does not exist.*"
        $nativeUdfGuardDirect.Refresh()
        [string]$nativeUdfGuardDirect.ClassifierFunction | Should -BeExactly $nativeUdfGuardOriginal
    }
}

Describe "Native Get-DbaDbUdf on Azure SQL Database" -Tag IntegrationTests {
    It "reads a user-defined function in Azure SQL Database" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            ConnectTimeout  = 60
            EnableException = $true
        }
        # Only this connect step retries, a fixed number of times; Get-DbaDbUdf runs once on the connected server.
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613, or lets the login time out, while it resumes.
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -eq 40613 -or $azureError.Number -eq -2 -or $azureError.NativeErrorCode -eq 258 -or $azureError.Message -like "*timed out*") { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Six legs share the database: a unique function and cleanup.
        $azureFunctionName = "native_udf_azure_" + [Guid]::NewGuid().ToString("N")
        try {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE FUNCTION [dbo].[$azureFunctionName] (@value int) RETURNS int AS BEGIN RETURN @value + 1; END;")
            $splatAzureUdf = @{
                SqlInstance      = $azureServer
                Database         = $TestConfig.AzureSqlDbName
                Name             = $azureFunctionName
                ExcludeSystemUdf = $true
                EnableException  = $true
            }
            $azureRows = @(Get-DbaDbUdf @splatAzureUdf)
            $azureRows.Count | Should -Be 1
            $azureRows[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.UserDefinedFunction
            $azureRows[0].Schema | Should -BeExactly "dbo"
            $azureRows[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
            $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        } finally {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'[dbo].[$azureFunctionName]', N'FN') IS NOT NULL DROP FUNCTION [dbo].[$azureFunctionName];")
        }
    }
}

Describe "Native Get-DbaDbUdf over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            # Unique per leg and run: the instance is shared.
            $loginDbName = "native_udf_sqllogin_" + [Guid]::NewGuid().ToString("N")
            $loginDatabase = New-Object Microsoft.SqlServer.Management.Smo.Database -ArgumentList $loginServer, $loginDbName
            $loginDatabase.Create()
            $loginDatabase.ExecuteNonQuery("CREATE FUNCTION [dbo].[native_login_udf] (@value int) RETURNS int AS BEGIN RETURN @value + 1; END;")
        }
        AfterAll {
            if ($loginServer) {
                # KillDatabase ends the command's pooled connections before the drop.
                $loginServer.Databases.Refresh()
                if ($loginServer.Databases[$loginDbName]) {
                    $loginServer.KillDatabase($loginDbName)
                }
            }
        }

        It "works with -SqlCredential" {
            $splatLoginUdf = @{
                SqlInstance      = $loginInstance
                SqlCredential    = $loginCred
                Database         = $loginDbName
                ExcludeSystemUdf = $true
                EnableException  = $true
            }
            $loginRows = @(Get-DbaDbUdf @splatLoginUdf)
            ($loginRows.Name -join ",") | Should -BeExactly "native_login_udf"
            $loginRows[0].Database | Should -BeExactly $loginDbName
        }

        It "fails cleanly without the credential: a warning and no output" {
            $loginWarnings = @()
            $splatLoginNoCredential = @{
                SqlInstance     = $loginInstance
                Database        = $loginDbName
                WarningAction   = "SilentlyContinue"
                WarningVariable = "loginWarnings"
            }
            $loginResult = @(Get-DbaDbUdf @splatLoginNoCredential)
            $loginResult.Count | Should -Be 0
            ($loginWarnings -join " ") | Should -BeLike "*Failure*"
        }

        It "fails cleanly without the credential: -EnableException throws a connection error" {
            $loginCaught = $null
            try {
                $null = Get-DbaDbUdf -SqlInstance $loginInstance -Database $loginDbName -EnableException
            } catch {
                $loginCaught = $PSItem
            }
            $loginCaught | Should -Not -BeNullOrEmpty
            $loginCaught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }
}
