#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Copy-DbaDbAssembly",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "Source",
                "SourceSqlCredential",
                "Destination",
                "DestinationSqlCredential",
                "Assembly",
                "ExcludeAssembly",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Two source databases on purpose. dbclrasm1 has a matching database on the destination and
        # carries the copy; dbclrasm2 has none, which is the only way to reach the
        # destination-database-missing branch - and because the command scans every accessible
        # source database, a single unfiltered call produces one object from each.
        $sourceInstance = $TestConfig.InstanceCopy1
        $destInstance = $TestConfig.InstanceCopy2

        # clr enabled differs per instance in the lab, so capture rather than assume: restoring a
        # guessed value would leave the instance in a state its other users did not have.
        $originalClrConfig = @{}
        foreach ($instance in $sourceInstance, $destInstance) {
            $originalClrConfig[$instance] = @{
                ClrEnabled = (Get-DbaSpConfigure -SqlInstance $instance -Name IsSqlClrEnabled).ConfiguredValue
                ClrStrict  = (Get-DbaSpConfigure -SqlInstance $instance -Name ClrStrictSecurity).ConfiguredValue
            }
            # Set-DbaSpConfigure throws rather than no-ops when the value already matches, and the
            # two instances do not start from the same values.
            if ($originalClrConfig[$instance].ClrEnabled -ne 1) {
                $null = Set-DbaSpConfigure -SqlInstance $instance -Name IsSqlClrEnabled -Value $true
            }
            if ($originalClrConfig[$instance].ClrStrict -ne 0) {
                $null = Set-DbaSpConfigure -SqlInstance $instance -Name ClrStrictSecurity -Value $false
            }
        }

        $null = New-DbaDatabase -SqlInstance $sourceInstance -Name dbclrasm1, dbclrasm2
        $null = New-DbaDatabase -SqlInstance $destInstance -Name dbclrasm1

        $createAssemblyQuery = "CREATE ASSEMBLY [resolveDNS] AUTHORIZATION [dbo] FROM 0x4D5A90000300000004000000FFFF0000B800000000000000400000000000000000000000000000000000000000000000000000000000000000000000800000000E1FBA0E00B409CD21B8014CCD21546869732070726F6772616D2063616E6E6F742062652072756E20696E20444F53206D6F64652E0D0D0A2400000000000000504500004C010300457830570000000000000000E00002210B010B000008000000060000000000002E260000002000000040000000000010002000000002000004000000000000000400000000000000008000000002000000000000030040850000100000100000000010000010000000000000100000000000000000000000E02500004B00000000400000B002000000000000000000000000000000000000006000000C000000A82400001C0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000080000000000000000000000082000004800000000000000000000002E7465787400000034060000002000000008000000020000000000000000000000000000200000602E72737263000000B00200000040000000040000000A0000000000000000000000000000400000402E72656C6F6300000C0000000060000000020000000E0000000000000000000000000000400000420000000000000000000000000000000010260000000000004800000002000500A42000000404000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001B3001002F000000010000110000026F0500000A280600000A6F0700000A6F0800000A0A06730900000A0BDE0B260002730900000A0BDE0000072A0001100000000001002021000B010000011E02280A00000A2A42534A4201000100000000000C00000076322E302E35303732370000000005006C00000070010000237E0000DC010000A401000023537472696E67730000000080030000080000002355530088030000100000002347554944000000980300006C00000023426C6F620000000000000002000001471502000900000000FA253300160000010000000A0000000200000002000000010000000A0000000400000001000000010000000300000000000A0001000000000006003E0037000A006600510006009D008A000F00B10000000600E000C00006000001C0000A00440129010600590137000E00700165010E007401650100000000010000000000010001000100100019000000050001000100502000000000960070000A0001009C200000000086187D001000020000000100830019007D00140029007D001A0031007D00100039007D00100041006001240049008001280051008D01240009009A01240011007D002E0009007D001000200023001F002E000B0039002E00130042002E001B004B0033000480000000000000000000000000000000001E01000002000000000000000000000001002E00000000000200000000000000000000000100450000000000020000000000000000000000010037000000000000000000003C4D6F64756C653E007265736F6C7665444E532E646C6C0055736572446566696E656446756E6374696F6E73006D73636F726C69620053797374656D004F626A6563740053797374656D2E446174610053797374656D2E446174612E53716C54797065730053716C537472696E67004950746F486F73744E616D65002E63746F72006970616464720053797374656D2E446961676E6F73746963730044656275676761626C6541747472696275746500446562756767696E674D6F6465730053797374656D2E52756E74696D652E436F6D70696C6572536572766963657300436F6D70696C6174696F6E52656C61786174696F6E734174747269627574650052756E74696D65436F6D7061746962696C697479417474726962757465007265736F6C7665444E53004D6963726F736F66742E53716C5365727665722E5365727665720053716C46756E6374696F6E41747472696275746500537472696E67005472696D0053797374656D2E4E657400446E73004950486F7374456E74727900476574486F7374456E747279006765745F486F73744E616D6500546F537472696E6700000003200000000000BBBB2D2F51E12E4791398BFA79459ABA0008B77A5C561934E08905000111090E03200001052001011111042001010804010000000320000E05000112290E042001010E0507020E11090801000701000000000801000800000000001E01000100540216577261704E6F6E457863657074696F6E5468726F7773010000000000004578305700000000020000001C010000C4240000C40600005253445357549849C5462E43AD588F97CA53634201000000633A5C74656D705C4461746162617365315C4461746162617365315C6F626A5C44656275675C7265736F6C7665444E532E706462000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000826000000000000000000001E260000002000000000000000000000000000000000000000000000102600000000000000005F436F72446C6C4D61696E006D73636F7265652E646C6C0000000000FF25002000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100100000001800008000000000000000000000000000000100010000003000008000000000000000000000000000000100000000004800000058400000540200000000000000000000540234000000560053005F00560045005200530049004F004E005F0049004E0046004F0000000000BD04EFFE00000100000000000000000000000000000000003F000000000000000400000002000000000000000000000000000000440000000100560061007200460069006C00650049006E0066006F00000000002400040000005400720061006E0073006C006100740069006F006E00000000000000B004B4010000010053007400720069006E006700460069006C00650049006E0066006F0000009001000001003000300030003000300034006200300000002C0002000100460069006C0065004400650073006300720069007000740069006F006E000000000020000000300008000100460069006C006500560065007200730069006F006E000000000030002E0030002E0030002E003000000040000F00010049006E007400650072006E0061006C004E0061006D00650000007200650073006F006C007600650044004E0053002E0064006C006C00000000002800020001004C006500670061006C0043006F00700079007200690067006800740000002000000048000F0001004F0072006900670069006E0061006C00460069006C0065006E0061006D00650000007200650073006F006C007600650044004E0053002E0064006C006C0000000000340008000100500072006F006400750063007400560065007200730069006F006E00000030002E0030002E0030002E003000000038000800010041007300730065006D0062006C0079002000560065007200730069006F006E00000030002E0030002E0030002E003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000C000000303600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        foreach ($sourceDatabase in "dbclrasm1", "dbclrasm2") {
            Invoke-DbaQuery -SqlInstance $sourceInstance -Database $sourceDatabase -Query $createAssemblyQuery
        }

        # The TRUSTWORTHY branch only fires for an EXTERNAL_ACCESS assembly, and raising the
        # permission set needs the source database trustworthy first. Without this the branch is
        # unreachable on this fixture and its leg would prove nothing.
        Invoke-DbaQuery -SqlInstance $sourceInstance -Database master -Query "ALTER DATABASE [dbclrasm1] SET TRUSTWORTHY ON"
        Invoke-DbaQuery -SqlInstance $sourceInstance -Database dbclrasm1 -Query "ALTER ASSEMBLY [resolveDNS] WITH PERMISSION_SET = EXTERNAL_ACCESS"

        $assemblyHashBytes = Invoke-DbaQuery -SqlInstance $sourceInstance -Database dbclrasm1 -Query "SELECT HASHBYTES('SHA2_512', content) FROM sys.assembly_files WHERE name = 'resolveDNS'" -As SingleValue
        $assemblyHashHex = "0x$(($assemblyHashBytes | ForEach-Object ToString X2) -join '')"
        Invoke-DbaQuery -SqlInstance $destInstance -Query "IF NOT EXISTS (SELECT 1 FROM sys.trusted_assemblies WHERE hash = $assemblyHashHex) EXEC sys.sp_add_trusted_assembly @hash = $assemblyHashHex, @description = N'resolveDNS'"

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # The config restore sits in a finally because these are instance-wide security settings on
        # a shared lab box: anything that throws above it would otherwise leave clr strict security
        # off for every other user of the instance, and the next run would then capture the relaxed
        # value as the one to restore.
        try {
            Get-DbaDatabase -SqlInstance $sourceInstance, $destInstance -Database dbclrasm1, dbclrasm2 | Remove-DbaDatabase

            if ($assemblyHashHex) {
                Invoke-DbaQuery -SqlInstance $destInstance -Query "IF EXISTS (SELECT 1 FROM sys.trusted_assemblies WHERE hash = $assemblyHashHex) EXEC sys.sp_drop_trusted_assembly @hash = $assemblyHashHex"
            }
        } finally {
            foreach ($instance in $sourceInstance, $destInstance) {
                if ((Get-DbaSpConfigure -SqlInstance $instance -Name ClrStrictSecurity).ConfiguredValue -ne $originalClrConfig[$instance].ClrStrict) {
                    $null = Set-DbaSpConfigure -SqlInstance $instance -Name ClrStrictSecurity -Value $originalClrConfig[$instance].ClrStrict
                }
                if ((Get-DbaSpConfigure -SqlInstance $instance -Name IsSqlClrEnabled).ConfiguredValue -ne $originalClrConfig[$instance].ClrEnabled) {
                    $null = Set-DbaSpConfigure -SqlInstance $instance -Name IsSqlClrEnabled -Value $originalClrConfig[$instance].ClrEnabled
                }
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When copying database assemblies" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            Invoke-DbaQuery -SqlInstance $destInstance -Database dbclrasm1 -Query "IF EXISTS (SELECT 1 FROM sys.assemblies WHERE name = 'resolveDNS') DROP ASSEMBLY [resolveDNS]"
            Invoke-DbaQuery -SqlInstance $destInstance -Database master -Query "ALTER DATABASE [dbclrasm1] SET TRUSTWORTHY OFF"

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy the assembly and report one status object per source database" {
            # No -Assembly on purpose. The filter is guarded by a boundness test, not by the value,
            # so a port that reads boundness from the wrong scope reports every parameter bound and
            # this call silently copies nothing.
            $copyResults = @(Copy-DbaDbAssembly -Source $sourceInstance -Destination $destInstance -WarningAction SilentlyContinue)
            $statusObjects = @($copyResults | Where-Object { $PSItem.Type -eq "Database Assembly" })

            $statusObjects.Count | Should -Be 2
            ($statusObjects | Where-Object SourceDatabase -eq "dbclrasm1").Status | Should -Be "Successful"
            ($statusObjects | Where-Object SourceDatabase -eq "dbclrasm2").Status | Should -Be "Skipped"
            ($statusObjects | Where-Object SourceDatabase -eq "dbclrasm2").Notes | Should -Be "Destination database does not exist"
            $statusObjects.Name | Select-Object -Unique | Should -Be "resolveDNS"

            $landedRows = @(Invoke-DbaQuery -SqlInstance $destInstance -Database dbclrasm1 -Query "SELECT name FROM sys.assemblies WHERE name = 'resolveDNS'")
            $landedRows.Count | Should -Be 1
        }

        It "Should set the destination database TRUSTWORTHY for an external-access assembly" {
            (Invoke-DbaQuery -SqlInstance $destInstance -Database master -Query "SELECT CAST(is_trustworthy_on AS int) AS Flag FROM sys.databases WHERE name = 'dbclrasm1'").Flag | Should -Be 0

            $trustResults = @(Copy-DbaDbAssembly -Source $sourceInstance -Destination $destInstance -WarningAction SilentlyContinue)

            (Invoke-DbaQuery -SqlInstance $destInstance -Database master -Query "SELECT CAST(is_trustworthy_on AS int) AS Flag FROM sys.databases WHERE name = 'dbclrasm1'").Flag | Should -Be 1

            # The ALTER DATABASE goes out through the destination server's Query and its empty
            # result set is never suppressed, so a bare element precedes the two status objects.
            # It surfaces as $null under one edition and as a data row under the other, so the
            # assertion tests the shape rather than the type - but it still reds if a port
            # suppressed the leak.
            $trustResults.Count | Should -Be 3
            $trustResults[0].Type | Should -BeNullOrEmpty
        }

        It "Should not create the assembly on the destination with -WhatIf" {
            $splatWhatIf = @{
                Source        = $sourceInstance
                Destination   = $destInstance
                WhatIf        = $true
                WarningAction = "SilentlyContinue"
            }
            $whatIfResults = Copy-DbaDbAssembly @splatWhatIf
            $whatIfResults | Should -BeNullOrEmpty

            @(Invoke-DbaQuery -SqlInstance $destInstance -Database dbclrasm1 -Query "SELECT name FROM sys.assemblies WHERE name = 'resolveDNS'").Count | Should -Be 0
            (Invoke-DbaQuery -SqlInstance $destInstance -Database master -Query "SELECT CAST(is_trustworthy_on AS int) AS Flag FROM sys.databases WHERE name = 'dbclrasm1'").Flag | Should -Be 0
        }

        It "Should skip an assembly that already exists on the destination" {
            $null = Copy-DbaDbAssembly -Source $sourceInstance -Destination $destInstance -WarningAction SilentlyContinue

            $skipResults = @(Copy-DbaDbAssembly -Source $sourceInstance -Destination $destInstance -WarningAction SilentlyContinue)
            $skipObject = $skipResults | Where-Object SourceDatabase -eq "dbclrasm1"
            $skipObject.Status | Should -Be "Skipped"
            $skipObject.Notes | Should -Be "Already exists on destination"
        }

        It "Should drop and recreate the assembly with -Force" {
            $null = Copy-DbaDbAssembly -Source $sourceInstance -Destination $destInstance -WarningAction SilentlyContinue
            $originalAssemblyId = (Invoke-DbaQuery -SqlInstance $destInstance -Database dbclrasm1 -Query "SELECT assembly_id FROM sys.assemblies WHERE name = 'resolveDNS'").assembly_id

            $forceResults = @(Copy-DbaDbAssembly -Source $sourceInstance -Destination $destInstance -Force -WarningAction SilentlyContinue)
            ($forceResults | Where-Object SourceDatabase -eq "dbclrasm1").Status | Should -Be "Successful"

            # Status alone cannot tell a real drop-and-recreate from a no-op that reports success.
            $recreatedAssemblyId = (Invoke-DbaQuery -SqlInstance $destInstance -Database dbclrasm1 -Query "SELECT assembly_id FROM sys.assemblies WHERE name = 'resolveDNS'").assembly_id
            $recreatedAssemblyId | Should -Not -Be $originalAssemblyId
        }

        It "Should honor -ExcludeAssembly when no -Assembly list is supplied" {
            $splatExclude = @{
                Source          = $sourceInstance
                Destination     = $destInstance
                ExcludeAssembly = "dbclrasm1.resolveDNS"
                WarningAction   = "SilentlyContinue"
            }
            $excludeResults = @(Copy-DbaDbAssembly @splatExclude)

            @($excludeResults | Where-Object SourceDatabase -eq "dbclrasm1").Count | Should -Be 0
            @(Invoke-DbaQuery -SqlInstance $destInstance -Database dbclrasm1 -Query "SELECT name FROM sys.assemblies WHERE name = 'resolveDNS'").Count | Should -Be 0
        }

        It "Should copy only the named assembly with -Assembly" {
            $splatFilter = @{
                Source        = $sourceInstance
                Destination   = $destInstance
                Assembly      = "dbclrasm1.resolveDNS"
                WarningAction = "SilentlyContinue"
            }
            $filterResults = @(Copy-DbaDbAssembly @splatFilter)

            ($filterResults | Where-Object SourceDatabase -eq "dbclrasm1").Status | Should -Be "Successful"

            # The missing-destination-database branch runs BEFORE the name filter, so dbclrasm2
            # still reports even though it was not named.
            ($filterResults | Where-Object SourceDatabase -eq "dbclrasm2").Notes | Should -Be "Destination database does not exist"
        }

        It "Should process every destination from one source scan" {
            # The cross-record leg. The source assemblies are collected once, before the destination
            # loop, so a port that consumed that collection as it walked the first destination would
            # hand the second destination nothing - and every per-destination assertion below would
            # still pass on the first pass alone.
            $splatTwoDestinations = @{
                Source        = $sourceInstance
                Destination   = $destInstance, $destInstance
                WarningAction = "SilentlyContinue"
            }
            $crossResults = @(Copy-DbaDbAssembly @splatTwoDestinations | Where-Object { $PSItem.Type -eq "Database Assembly" })

            $crossResults.Count | Should -Be 4
            $crossResults[0].Status | Should -Be "Successful"
            $crossResults[1].Notes | Should -Be "Destination database does not exist"
            $crossResults[2].Notes | Should -Be "Already exists on destination"
            $crossResults[3].Notes | Should -Be "Destination database does not exist"
        }
    }

    Context "When resolving the command name in a cold shell" {
        BeforeAll {
            # Every other leg runs in a session that imported dbatools long before Pester started,
            # so none of them can tell the binary cmdlet apart from the retired script function -
            # whichever got there first answers to the name. This leg starts a shell of the same
            # edition that has imported nothing, loads the module the way a consumer does, and asks
            # what the name resolves to. dbatools.psm1 is the import under test on purpose: it is
            # the loader that pulls the satellite in by path, and importing the manifest by name
            # cannot work in a dev tree because the satellites are not on PSModulePath.
            $moduleBase = @(Get-Module -Name dbatools)[0].ModuleBase
            $shellPath = (Get-Process -Id $PID).Path
            $probePath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$(Get-Random).ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            $probeBody = @"
Import-Module -Name "$moduleBase\dbatools.psm1" -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaDbAssembly -ErrorAction SilentlyContinue
`$allResolved = @(Get-Command -Name Copy-DbaDbAssembly -All -ErrorAction SilentlyContinue)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded"
"@
            Set-Content -Path $probePath -Value $probeBody -Encoding UTF8

            $probeOutput = & $shellPath -NoProfile -NonInteractive -File $probePath 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            Remove-Item -Path $probePath -ErrorAction SilentlyContinue
        }

        It "Should resolve to the binary cmdlet shipped by dbatools.migration" {
            $probeFields[1] | Should -Be "Cmdlet"
            $probeFields[2] | Should -Be "dbatools.migration"
        }

        It "Should load the satellite and leave no retired function shadowing the name" {
            $probeFields[4] | Should -Be "True"
            $probeFields[3] | Should -Be "0"
        }
    }
}