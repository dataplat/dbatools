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

        # Two source databases on purpose. The first has a matching database on the destination and
        # carries the copy; the second has none, which is the only way to reach the
        # destination-database-missing branch - and because the command scans every accessible
        # source database, a single unfiltered call produces one object from each. The per-run stem
        # keeps cleanup from ever reaching a database this run did not create; the trailing 1/2
        # keeps the pair in that order when the command enumerates the source.
        $sourceInstance = $TestConfig.InstanceCopy1
        $destInstance = $TestConfig.InstanceCopy2
        # A GUID rather than Get-Random: the cleanup drops these names unconditionally, so a
        # collision with a concurrent run would destroy that run's databases. Get-Random draws from
        # a 32-bit space and repeats often enough on a shared lab to matter.
        $dbStem = "dbatoolsci_clrasm_$([guid]::NewGuid().ToString("N"))_"
        $fixtureDb1 = "${dbStem}1"
        $fixtureDb2 = "${dbStem}2"

        $createdDatabases = @()
        $trustedAssemblyAdded = $false
        $assemblyHashHex = $null

        # clr enabled differs per instance in the lab, so capture rather than assume: restoring a
        # guessed value would leave the instance in a state its other users did not have.
        # Unique on purpose. With both roles pointed at one instance the second pass would capture
        # the values the first pass had just changed, and the cleanup would then "restore" CLR
        # enabled and strict security off onto an instance that started with neither.
        $originalClrConfig = @{}
        foreach ($instance in @($sourceInstance, $destInstance | Select-Object -Unique)) {
            $originalClrConfig[$instance] = @{
                ClrEnabled = (Get-DbaSpConfigure -SqlInstance $instance -Name IsSqlClrEnabled).ConfiguredValue
                ClrStrict  = (Get-DbaSpConfigure -SqlInstance $instance -Name ClrStrictSecurity).ConfiguredValue
            }
            # Set-DbaSpConfigure throws rather than no-ops when the value already matches, and the
            # two instances do not start from the same values.
            if ($originalClrConfig[$instance].ClrEnabled -ne 1) {
                $splatEnableClr = @{
                    SqlInstance = $instance
                    Name        = "IsSqlClrEnabled"
                    Value       = $true
                }
                $null = Set-DbaSpConfigure @splatEnableClr
            }
            if ($originalClrConfig[$instance].ClrStrict -ne 0) {
                $splatRelaxClrStrict = @{
                    SqlInstance = $instance
                    Name        = "ClrStrictSecurity"
                    Value       = $false
                }
                $null = Set-DbaSpConfigure @splatRelaxClrStrict
            }
        }

        # Several legs call the command with no -Assembly, which is the point of them: the filter is
        # guarded by a boundness test. That also means every source database the command considers
        # accessible is scanned and anything it finds lands in a same-named destination database.
        #
        # This enumerates through SMO with the same shape the command uses - Databases filtered on
        # IsAccessible, assemblies filtered on IsSystemObject, each database in its own try/catch -
        # because an inventory that reads a different set of databases than the command scans is not
        # a precondition. The T-SQL cursor this replaced skipped system, single-user and
        # restricted-user databases, all three of which the command will happily walk. A fresh
        # connection per call keeps a database that poisons the enumeration away from the connection
        # the rest of the suite is using.
        function Get-UserAssemblyInventory {
            param($SqlInstance)
            $inventoryServer = Connect-DbaInstance -SqlInstance $SqlInstance
            foreach ($inventoryDatabase in ($inventoryServer.Databases | Where-Object IsAccessible)) {
                try {
                    foreach ($inventoryAssembly in ($inventoryDatabase.Assemblies | Where-Object IsSystemObject -eq $false)) {
                        [PSCustomObject]@{
                            DatabaseName = $inventoryDatabase.Name
                            AssemblyName = $inventoryAssembly.Name
                        }
                    }
                } catch {
                    # The command swallows this same read the same way, so an inventory that threw
                    # here would be stricter than the thing it is measuring.
                    $null = 1
                }
            }
        }
        $originalDestAssemblies = @(Get-UserAssemblyInventory -SqlInstance $destInstance)

        # Copying an external-access assembly flips the destination database's TRUSTWORTHY bit, which
        # is a security property of a database this suite does not own. Recorded over every database
        # rather than user databases alone, for the same scope reason as the assembly inventory.
        $trustworthyInventoryQuery = "SELECT name AS DatabaseName, CAST(is_trustworthy_on AS int) AS IsTrustworthy FROM sys.databases"
        $originalDestTrustworthy = @(Invoke-DbaQuery -SqlInstance $destInstance -Query $trustworthyInventoryQuery)

        # The unfiltered legs hand the command every accessible source database, so what it can reach
        # is exactly the set of user assemblies this instance carries. Establish that the set is
        # empty before the fixture exists and those legs provably cannot copy a stranger's assembly
        # into a same-named destination database or flip that database TRUSTWORTHY. This throws
        # rather than skipping: a leg that quietly stops covering the unfiltered path is worth less
        # than a red one, and the message names what is in the way.
        $preexistingSourceAssemblies = @(Get-UserAssemblyInventory -SqlInstance $sourceInstance)
        if ($preexistingSourceAssemblies.Count -gt 0) {
            $preexistingList = ($preexistingSourceAssemblies | ForEach-Object { "$($PSItem.DatabaseName).$($PSItem.AssemblyName)" }) -join ", "
            throw "$sourceInstance already carries user assemblies ($preexistingList) - the unfiltered legs would copy them, so this suite will not run against it."
        }

        # One call and one record per database. A single two-name call that fails after creating the
        # first one leaks it, because nothing has recorded it yet; recording first and creating
        # second makes the leak impossible in either order, since the cleanup drops through
        # Get-DbaDatabase and a name that was never created finds nothing.
        #
        # Absence is proved before the record goes in, though. Recording first means the cleanup
        # will drop the name whether or not this run is what put it there, so the claim of ownership
        # has to be established rather than assumed - a GUID makes a collision vanishingly unlikely,
        # and this makes it harmless if one ever happens.
        # Written out per database rather than through a helper: a function body is a new scope, and
        # appending to the BeforeAll's $createdDatabases from inside one does not reach the variable
        # the AfterAll reads.
        $plannedFixtures = @(
            @{
                SqlInstance = $sourceInstance
                Name        = $fixtureDb1
            },
            @{
                SqlInstance = $sourceInstance
                Name        = $fixtureDb2
            },
            @{
                SqlInstance = $destInstance
                Name        = $fixtureDb1
            }
        )
        foreach ($plannedFixture in $plannedFixtures) {
            if (Get-DbaDatabase -SqlInstance $plannedFixture.SqlInstance -Database $plannedFixture.Name) {
                throw "$($plannedFixture.Name) already exists on $($plannedFixture.SqlInstance) - this suite will not adopt a database it did not create, because the cleanup would then drop it."
            }
            $createdDatabases += [PSCustomObject]@{
                SqlInstance = $plannedFixture.SqlInstance
                Name        = $plannedFixture.Name
            }
            $null = New-DbaDatabase -SqlInstance $plannedFixture.SqlInstance -Name $plannedFixture.Name
        }

        $createAssemblyQuery = "CREATE ASSEMBLY [resolveDNS] AUTHORIZATION [dbo] FROM 0x4D5A90000300000004000000FFFF0000B800000000000000400000000000000000000000000000000000000000000000000000000000000000000000800000000E1FBA0E00B409CD21B8014CCD21546869732070726F6772616D2063616E6E6F742062652072756E20696E20444F53206D6F64652E0D0D0A2400000000000000504500004C010300457830570000000000000000E00002210B010B000008000000060000000000002E260000002000000040000000000010002000000002000004000000000000000400000000000000008000000002000000000000030040850000100000100000000010000010000000000000100000000000000000000000E02500004B00000000400000B002000000000000000000000000000000000000006000000C000000A82400001C0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000080000000000000000000000082000004800000000000000000000002E7465787400000034060000002000000008000000020000000000000000000000000000200000602E72737263000000B00200000040000000040000000A0000000000000000000000000000400000402E72656C6F6300000C0000000060000000020000000E0000000000000000000000000000400000420000000000000000000000000000000010260000000000004800000002000500A42000000404000001000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001B3001002F000000010000110000026F0500000A280600000A6F0700000A6F0800000A0A06730900000A0BDE0B260002730900000A0BDE0000072A0001100000000001002021000B010000011E02280A00000A2A42534A4201000100000000000C00000076322E302E35303732370000000005006C00000070010000237E0000DC010000A401000023537472696E67730000000080030000080000002355530088030000100000002347554944000000980300006C00000023426C6F620000000000000002000001471502000900000000FA253300160000010000000A0000000200000002000000010000000A0000000400000001000000010000000300000000000A0001000000000006003E0037000A006600510006009D008A000F00B10000000600E000C00006000001C0000A00440129010600590137000E00700165010E007401650100000000010000000000010001000100100019000000050001000100502000000000960070000A0001009C200000000086187D001000020000000100830019007D00140029007D001A0031007D00100039007D00100041006001240049008001280051008D01240009009A01240011007D002E0009007D001000200023001F002E000B0039002E00130042002E001B004B0033000480000000000000000000000000000000001E01000002000000000000000000000001002E00000000000200000000000000000000000100450000000000020000000000000000000000010037000000000000000000003C4D6F64756C653E007265736F6C7665444E532E646C6C0055736572446566696E656446756E6374696F6E73006D73636F726C69620053797374656D004F626A6563740053797374656D2E446174610053797374656D2E446174612E53716C54797065730053716C537472696E67004950746F486F73744E616D65002E63746F72006970616464720053797374656D2E446961676E6F73746963730044656275676761626C6541747472696275746500446562756767696E674D6F6465730053797374656D2E52756E74696D652E436F6D70696C6572536572766963657300436F6D70696C6174696F6E52656C61786174696F6E734174747269627574650052756E74696D65436F6D7061746962696C697479417474726962757465007265736F6C7665444E53004D6963726F736F66742E53716C5365727665722E5365727665720053716C46756E6374696F6E41747472696275746500537472696E67005472696D0053797374656D2E4E657400446E73004950486F7374456E74727900476574486F7374456E747279006765745F486F73744E616D6500546F537472696E6700000003200000000000BBBB2D2F51E12E4791398BFA79459ABA0008B77A5C561934E08905000111090E03200001052001011111042001010804010000000320000E05000112290E042001010E0507020E11090801000701000000000801000800000000001E01000100540216577261704E6F6E457863657074696F6E5468726F7773010000000000004578305700000000020000001C010000C4240000C40600005253445357549849C5462E43AD588F97CA53634201000000633A5C74656D705C4461746162617365315C4461746162617365315C6F626A5C44656275675C7265736F6C7665444E532E706462000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000826000000000000000000001E260000002000000000000000000000000000000000000000000000102600000000000000005F436F72446C6C4D61696E006D73636F7265652E646C6C0000000000FF25002000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000100100000001800008000000000000000000000000000000100010000003000008000000000000000000000000000000100000000004800000058400000540200000000000000000000540234000000560053005F00560045005200530049004F004E005F0049004E0046004F0000000000BD04EFFE00000100000000000000000000000000000000003F000000000000000400000002000000000000000000000000000000440000000100560061007200460069006C00650049006E0066006F00000000002400040000005400720061006E0073006C006100740069006F006E00000000000000B004B4010000010053007400720069006E006700460069006C00650049006E0066006F0000009001000001003000300030003000300034006200300000002C0002000100460069006C0065004400650073006300720069007000740069006F006E000000000020000000300008000100460069006C006500560065007200730069006F006E000000000030002E0030002E0030002E003000000040000F00010049006E007400650072006E0061006C004E0061006D00650000007200650073006F006C007600650044004E0053002E0064006C006C00000000002800020001004C006500670061006C0043006F00700079007200690067006800740000002000000048000F0001004F0072006900670069006E0061006C00460069006C0065006E0061006D00650000007200650073006F006C007600650044004E0053002E0064006C006C0000000000340008000100500072006F006400750063007400560065007200730069006F006E00000030002E0030002E0030002E003000000038000800010041007300730065006D0062006C0079002000560065007200730069006F006E00000030002E0030002E0030002E003000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000002000000C000000303600000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000"
        foreach ($sourceDatabase in $fixtureDb1, $fixtureDb2) {
            $splatCreateAssembly = @{
                SqlInstance = $sourceInstance
                Database    = $sourceDatabase
                Query       = $createAssemblyQuery
            }
            Invoke-DbaQuery @splatCreateAssembly
        }

        # The TRUSTWORTHY branch only fires for an EXTERNAL_ACCESS assembly, and raising the
        # permission set needs the source database trustworthy first. Without this the branch is
        # unreachable on this fixture and its leg would prove nothing.
        $splatSourceTrustworthy = @{
            SqlInstance = $sourceInstance
            Database    = "master"
            Query       = "ALTER DATABASE [$fixtureDb1] SET TRUSTWORTHY ON"
        }
        Invoke-DbaQuery @splatSourceTrustworthy

        $splatExternalAccess = @{
            SqlInstance = $sourceInstance
            Database    = $fixtureDb1
            Query       = "ALTER ASSEMBLY [resolveDNS] WITH PERMISSION_SET = EXTERNAL_ACCESS"
        }
        Invoke-DbaQuery @splatExternalAccess

        $splatAssemblyHash = @{
            SqlInstance = $sourceInstance
            Database    = $fixtureDb1
            Query       = "SELECT HASHBYTES('SHA2_512', content) FROM sys.assembly_files WHERE name = 'resolveDNS'"
            As          = "SingleValue"
        }
        $assemblyHashBytes = Invoke-DbaQuery @splatAssemblyHash
        # Hoisted out of the interpolation: inside a double-quoted string, a nested "" reads as
        # an escaped quote, not as an empty separator.
        $assemblyHashBody = ($assemblyHashBytes | ForEach-Object ToString X2) -join ""
        $assemblyHashHex = "0x$assemblyHashBody"

        # The hash identifies the assembly, not this fixture, so another user of the instance can
        # already have registered it. Record whether this run is the one that inserted it - cleanup
        # drops it only in that case.
        $splatTrustedCount = @{
            SqlInstance = $destInstance
            Query       = "SELECT COUNT(*) FROM sys.trusted_assemblies WHERE hash = $assemblyHashHex"
            As          = "SingleValue"
        }
        if ((Invoke-DbaQuery @splatTrustedCount) -eq 0) {
            Invoke-DbaQuery -SqlInstance $destInstance -Query "EXEC sys.sp_add_trusted_assembly @hash = $assemblyHashHex, @description = N'resolveDNS'"
            $trustedAssemblyAdded = $true
        }

        # Read-backs the legs below share. None of them is ever modified.
        $splatDestAssemblyRows = @{
            SqlInstance = $destInstance
            Database    = $fixtureDb1
            Query       = "SELECT name FROM sys.assemblies WHERE name = 'resolveDNS'"
        }
        $splatDestTrustworthy = @{
            SqlInstance = $destInstance
            Database    = "master"
            Query       = "SELECT CAST(is_trustworthy_on AS int) AS Flag FROM sys.databases WHERE name = '$fixtureDb1'"
        }
        $splatDestAssemblyId = @{
            SqlInstance = $destInstance
            Database    = $fixtureDb1
            Query       = "SELECT assembly_id FROM sys.assemblies WHERE name = 'resolveDNS'"
        }
        $splatCopyAssembly = @{
            Source        = $sourceInstance
            Destination   = $destInstance
            WarningAction = "SilentlyContinue"
        }

        # The same call named down to the fixture assembly. Only the two legs that have to leave
        # -Assembly unbound use the unfiltered splat above; everything else uses this one, because
        # an unfiltered -Force would drop and recreate any assembly the destination happens to share
        # with the source, and those are not this suite's to churn.
        $splatFixtureCopy = @{
            Source        = $sourceInstance
            Destination   = $destInstance
            Assembly      = "$fixtureDb1.resolveDNS"
            WarningAction = "SilentlyContinue"
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Each restoration stands on its own. These are instance-wide security settings and other
        # people's databases on a shared lab box, so one failure must not skip the rest: chaining
        # them once left clr strict security OFF instance-wide because an earlier step threw. The
        # collected failures are re-raised at the end so a broken cleanup still fails the run.
        $cleanupFailures = @()

        # Nothing below this line deletes an object or rewrites a setting that is not demonstrably
        # ours. The BeforeAll precondition established that the source carried no assembly but the
        # fixture's, so the unfiltered legs cannot have created a destination assembly or flipped a
        # foreign TRUSTWORTHY bit; anything that turns up here is therefore either another window's
        # or a sign the precondition stopped holding mid-run. Deleting on that guess is exactly how a
        # cleanup destroys a peer's fixture, so it is reported and re-raised instead - the run goes
        # red, a human reads the names, and the object survives to be looked at.
        try {
            $unexpectedAssemblies = @(Get-UserAssemblyInventory -SqlInstance $destInstance) |
                Where-Object { $PSItem.DatabaseName -notin $fixtureDb1, $fixtureDb2 } |
                Where-Object {
                    $candidate = $PSItem
                    @($originalDestAssemblies | Where-Object { $PSItem.DatabaseName -eq $candidate.DatabaseName -and $PSItem.AssemblyName -eq $candidate.AssemblyName }).Count -eq 0
                }
            if (@($unexpectedAssemblies).Count -gt 0) {
                $unexpectedList = (@($unexpectedAssemblies) | ForEach-Object { "$($PSItem.DatabaseName).$($PSItem.AssemblyName)" }) -join ", "
                $cleanupFailures += "assemblies appeared on $destInstance that this run cannot account for and has left in place: $unexpectedList"
            }
        } catch {
            $cleanupFailures += "destination assembly inventory: $($PSItem.Exception.Message)"
        }

        try {
            $currentTrustworthy = @(Invoke-DbaQuery -SqlInstance $destInstance -Query $trustworthyInventoryQuery)
            $unexpectedTrustworthy = @()
            foreach ($databaseState in $currentTrustworthy) {
                if ($databaseState.DatabaseName -in $fixtureDb1, $fixtureDb2) { continue }
                $originalState = @($originalDestTrustworthy | Where-Object { $PSItem.DatabaseName -eq $databaseState.DatabaseName })
                if ($originalState.Count -eq 0 -or $originalState[0].IsTrustworthy -eq $databaseState.IsTrustworthy) { continue }
                $unexpectedTrustworthy += "$($databaseState.DatabaseName) ($($originalState[0].IsTrustworthy) -> $($databaseState.IsTrustworthy))"
            }
            if ($unexpectedTrustworthy.Count -gt 0) {
                $cleanupFailures += "TRUSTWORTHY changed on $destInstance for databases this run cannot account for and has left as found: $($unexpectedTrustworthy -join ", ")"
            }
        } catch {
            $cleanupFailures += "destination TRUSTWORTHY inventory: $($PSItem.Exception.Message)"
        }

        foreach ($createdDatabase in $createdDatabases) {
            try {
                $splatRemoveFixtureDb = @{
                    SqlInstance = $createdDatabase.SqlInstance
                    Database    = $createdDatabase.Name
                }
                Get-DbaDatabase @splatRemoveFixtureDb | Remove-DbaDatabase
            } catch {
                $cleanupFailures += "database $($createdDatabase.Name) on $($createdDatabase.SqlInstance): $($PSItem.Exception.Message)"
            }
        }

        try {
            if ($trustedAssemblyAdded) {
                Invoke-DbaQuery -SqlInstance $destInstance -Query "EXEC sys.sp_drop_trusted_assembly @hash = $assemblyHashHex"
            }
        } catch {
            $cleanupFailures += "trusted assembly: $($PSItem.Exception.Message)"
        }

        # Driven by what was captured, not by the two instance names: a setup that threw before the
        # snapshot of the second instance leaves no entry for it, and the missing entry would hand
        # Set-DbaSpConfigure a $null Value that binds as 0 - switching strict security off on an
        # instance this run never touched.
        foreach ($restoreInstance in @($originalClrConfig.Keys)) {
            try {
                if ((Get-DbaSpConfigure -SqlInstance $restoreInstance -Name ClrStrictSecurity).ConfiguredValue -ne $originalClrConfig[$restoreInstance].ClrStrict) {
                    $splatRestoreClrStrict = @{
                        SqlInstance = $restoreInstance
                        Name        = "ClrStrictSecurity"
                        Value       = $originalClrConfig[$restoreInstance].ClrStrict
                    }
                    $null = Set-DbaSpConfigure @splatRestoreClrStrict
                }
            } catch {
                $cleanupFailures += "clr strict security on ${restoreInstance}: $($PSItem.Exception.Message)"
            }

            try {
                if ((Get-DbaSpConfigure -SqlInstance $restoreInstance -Name IsSqlClrEnabled).ConfiguredValue -ne $originalClrConfig[$restoreInstance].ClrEnabled) {
                    $splatRestoreClrEnabled = @{
                        SqlInstance = $restoreInstance
                        Name        = "IsSqlClrEnabled"
                        Value       = $originalClrConfig[$restoreInstance].ClrEnabled
                    }
                    $null = Set-DbaSpConfigure @splatRestoreClrEnabled
                }
            } catch {
                $cleanupFailures += "clr enabled on ${restoreInstance}: $($PSItem.Exception.Message)"
            }
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

        if ($cleanupFailures.Count -gt 0) {
            throw "AfterAll could not restore: $($cleanupFailures -join " | ")"
        }
    }

    Context "When copying database assemblies" {
        BeforeEach {
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatDropDestAssembly = @{
                SqlInstance = $destInstance
                Database    = $fixtureDb1
                Query       = "IF EXISTS (SELECT 1 FROM sys.assemblies WHERE name = 'resolveDNS') DROP ASSEMBLY [resolveDNS]"
            }
            Invoke-DbaQuery @splatDropDestAssembly

            $splatClearDestTrustworthy = @{
                SqlInstance = $destInstance
                Database    = "master"
                Query       = "ALTER DATABASE [$fixtureDb1] SET TRUSTWORTHY OFF"
            }
            Invoke-DbaQuery @splatClearDestTrustworthy

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "Should copy the assembly and report one status object per source database" {
            # No -Assembly on purpose. The filter is guarded by a boundness test, not by the value,
            # so a port that reads boundness from the wrong scope reports every parameter bound and
            # this call silently copies nothing. That makes this one of the two legs that cannot be
            # narrowed to the fixture.
            #
            # Re-checked here and not only in BeforeAll: this is the moment the blast radius matters,
            # and the source is shared - another window can have created an assembly since. Asserting
            # before the call means a foreign assembly reds this leg instead of being copied by it.
            $foreignSourceAssemblies = @(Get-UserAssemblyInventory -SqlInstance $sourceInstance) |
                Where-Object { $PSItem.DatabaseName -notin $fixtureDb1, $fixtureDb2 }
            @($foreignSourceAssemblies).Count | Should -Be 0 -Because "an unfiltered copy would carry a foreign assembly into a same-named destination database"

            $copyResults = @(Copy-DbaDbAssembly @splatCopyAssembly)
            $statusObjects = @($copyResults | Where-Object { $PSItem.Type -eq "Database Assembly" })

            $statusObjects.Count | Should -Be 2
            ($statusObjects | Where-Object SourceDatabase -eq $fixtureDb1).Status | Should -Be "Successful"
            ($statusObjects | Where-Object SourceDatabase -eq $fixtureDb2).Status | Should -Be "Skipped"
            ($statusObjects | Where-Object SourceDatabase -eq $fixtureDb2).Notes | Should -Be "Destination database does not exist"
            $statusObjects.Name | Select-Object -Unique | Should -Be "resolveDNS"

            $landedRows = @(Invoke-DbaQuery @splatDestAssemblyRows)
            $landedRows.Count | Should -Be 1
        }

        It "Should set the destination database TRUSTWORTHY for an external-access assembly" {
            (Invoke-DbaQuery @splatDestTrustworthy).Flag | Should -Be 0

            $trustResults = @(Copy-DbaDbAssembly @splatFixtureCopy)

            (Invoke-DbaQuery @splatDestTrustworthy).Flag | Should -Be 1

            # The ALTER DATABASE goes out through the destination server's Query and its empty
            # result set is never suppressed, so a bare element precedes the two status objects.
            # It surfaces as $null under one edition and as a data row under the other, so the
            # assertion tests the shape rather than the type - but it still reds if a port
            # suppressed the leak.
            $trustResults.Count | Should -Be 3
            $trustResults[0].Type | Should -BeNullOrEmpty
        }

        It "Should not create the assembly on the destination with -WhatIf" {
            $whatIfResults = Copy-DbaDbAssembly @splatFixtureCopy -WhatIf
            $whatIfResults | Should -BeNullOrEmpty

            @(Invoke-DbaQuery @splatDestAssemblyRows).Count | Should -Be 0
            (Invoke-DbaQuery @splatDestTrustworthy).Flag | Should -Be 0
        }

        It "Should skip an assembly that already exists on the destination" {
            $null = Copy-DbaDbAssembly @splatFixtureCopy

            $skipResults = @(Copy-DbaDbAssembly @splatFixtureCopy)
            $skipObject = $skipResults | Where-Object SourceDatabase -eq $fixtureDb1
            $skipObject.Status | Should -Be "Skipped"
            $skipObject.Notes | Should -Be "Already exists on destination"
        }

        It "Should drop and recreate the assembly with -Force" {
            $null = Copy-DbaDbAssembly @splatFixtureCopy
            $originalAssemblyId = (Invoke-DbaQuery @splatDestAssemblyId).assembly_id

            $forceResults = @(Copy-DbaDbAssembly @splatFixtureCopy -Force)
            ($forceResults | Where-Object SourceDatabase -eq $fixtureDb1).Status | Should -Be "Successful"

            # Status alone cannot tell a real drop-and-recreate from a no-op that reports success.
            $recreatedAssemblyId = (Invoke-DbaQuery @splatDestAssemblyId).assembly_id
            $recreatedAssemblyId | Should -Not -Be $originalAssemblyId
        }

        It "Should honor -ExcludeAssembly when no -Assembly list is supplied" {
            # The second leg that cannot be narrowed: naming -Assembly here would test a different
            # branch than the one the title claims. Same live re-check as the leg above, for the
            # same reason - unfiltered means the source's whole assembly inventory is in scope.
            $excludeLegForeignAssemblies = @(Get-UserAssemblyInventory -SqlInstance $sourceInstance) |
                Where-Object { $PSItem.DatabaseName -notin $fixtureDb1, $fixtureDb2 }
            @($excludeLegForeignAssemblies).Count | Should -Be 0 -Because "an unfiltered copy would carry a foreign assembly into a same-named destination database"

            $splatExcludeAssembly = @{
                Source          = $sourceInstance
                Destination     = $destInstance
                ExcludeAssembly = "$fixtureDb1.resolveDNS"
                WarningAction   = "SilentlyContinue"
            }
            $excludeResults = @(Copy-DbaDbAssembly @splatExcludeAssembly)

            @($excludeResults | Where-Object SourceDatabase -eq $fixtureDb1).Count | Should -Be 0
            @(Invoke-DbaQuery @splatDestAssemblyRows).Count | Should -Be 0
        }

        It "Should copy only the named assembly with -Assembly" {
            $splatFilterAssembly = @{
                Source        = $sourceInstance
                Destination   = $destInstance
                Assembly      = "$fixtureDb1.resolveDNS"
                WarningAction = "SilentlyContinue"
            }
            $filterResults = @(Copy-DbaDbAssembly @splatFilterAssembly)

            ($filterResults | Where-Object SourceDatabase -eq $fixtureDb1).Status | Should -Be "Successful"

            # The missing-destination-database branch runs BEFORE the name filter, so the second
            # source database still reports even though it was not named.
            ($filterResults | Where-Object SourceDatabase -eq $fixtureDb2).Notes | Should -Be "Destination database does not exist"
        }

        It "Should process every destination from one source scan" {
            # The cross-record leg. The source assemblies are collected once, before the destination
            # loop, so a port that consumed that collection as it walked the first destination would
            # hand the second destination nothing - and every per-destination assertion below would
            # still pass on the first pass alone.
            $splatTwoDestinations = @{
                Source        = $sourceInstance
                Destination   = $destInstance, $destInstance
                Assembly      = "$fixtureDb1.resolveDNS"
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
            # This file is EXECUTED, so where it lives matters as much as what is in it. It goes in
            # a per-invocation directory that only its creator and the machine's administrators can
            # write to, rather than in the shared temp root, under a GUID name, and created below
            # with CreateNew rather than written over whatever is at the path. Closing the write
            # handle before the run is only safe because of the directory: on the shared temp root
            # there is a window between the write and the run in which anyone can substitute the
            # script.
            $probeDirectory = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath "dbatoolsci-resolve-$([guid]::NewGuid().ToString("N"))"
            # A GUID makes this unreachable in practice, but every create-directory API below
            # succeeds silently on a path that already exists and leaves its permissions
            # alone, so the one thing that must not happen is adopting somebody else's
            # directory and executing a script out of it.
            if (Test-Path -LiteralPath $probeDirectory) {
                throw "$probeDirectory already exists - this run will not execute a script out of a directory it did not create"
            }
            $probeDirectoryInfo = New-Object System.IO.DirectoryInfo($probeDirectory)
            if ([System.Environment]::OSVersion.Platform -eq "Win32NT") {
                # The running identity owns it, not Administrators: only an elevated run can hand
                # ownership to a group it is not in, and a descriptor that omits the creator locks
                # the creator out of the directory it just made. Administrators and SYSTEM are on it
                # because they can reach the file whatever this says, so excluding them buys nothing
                # and costs the elevated case.
                $currentSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User
                $administratorsSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
                $systemSid = New-Object System.Security.Principal.SecurityIdentifier([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
                $probeSecurity = New-Object System.Security.AccessControl.DirectorySecurity
                $probeSecurity.SetAccessRuleProtection($true, $false)
                $probeSecurity.SetOwner($currentSid)
                foreach ($trusteeSid in $currentSid, $administratorsSid, $systemSid) {
                    $probeRule = New-Object System.Security.AccessControl.FileSystemAccessRule($trusteeSid, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
                    $probeSecurity.AddAccessRule($probeRule)
                }
                # Created WITH the descriptor, never created and then secured - the gap between
                # those two calls carries inherited permissions. Which call does it differs by
                # edition: .NET Framework has DirectoryInfo.Create(DirectorySecurity), .NET moved it
                # out to FileSystemAclExtensions, and Directory.CreateDirectory(path, security)
                # exists on neither PowerShell 7 nor v3. Probing for the overload rather than the
                # PSEdition because it is the overload that decides.
                $probeNativeCreate = [System.IO.DirectoryInfo].GetMethod("Create", [Type[]]@([System.Security.AccessControl.DirectorySecurity]))
                if ($probeNativeCreate) {
                    $probeDirectoryInfo.Create($probeSecurity)
                } else {
                    [System.IO.FileSystemAclExtensions]::Create($probeDirectoryInfo, $probeSecurity)
                }
            } else {
                # DirectorySecurity is Windows-only and throws PlatformNotSupportedException
                # everywhere else, so the mode carries the same job there. The umask cannot: under a
                # permissive one the directory comes out group- or world-writable and the executed
                # script is substitutable. Created WITH 0700 where the runtime offers that overload,
                # for the same reason the Windows branch creates with a descriptor; where it does
                # not, the chmod follows immediately, and resolve.ps1 is written with CreateNew
                # either way, so anything planted in the gap throws instead of being executed.
                # mkdir rather than a .NET call, for the exclusivity: every managed
                # create-directory API succeeds silently on a directory that already exists and
                # leaves that directory's permissions alone, so a pre-created one would be used as
                # is. mkdir without -p fails instead, and -m carries the mode in the same call.
                # It also sidesteps UnixFileMode, which is .NET 7 and absent on PowerShell 7.2/7.3.
                # A non-zero exit is fatal: carrying on would execute a script out of a directory
                # whose permissions are unknown.
                $null = & /bin/mkdir -m 700 $probeDirectory
                if ($LASTEXITCODE -ne 0) {
                    throw "could not create $probeDirectory with owner-only permissions (mkdir exited $LASTEXITCODE)"
                }
            }
            $probePath = Join-Path -Path $probeDirectory -ChildPath "resolve.ps1"

            # Get-Command -All so a retired function shadowing the cmdlet shows up as a second
            # entry rather than silently winning; the count is what proves it is not there.
            $probeBody = @"
param(`$ModuleBase)
# The module path is an ARGUMENT, not interpolated text: this script is executed, and a
# path carrying a quote or a $ would otherwise close the string and run as code.
Import-Module -Name (Join-Path -Path `$ModuleBase -ChildPath "dbatools.psm1") -DisableNameChecking
`$resolved = Get-Command -Name Copy-DbaDbAssembly -ErrorAction SilentlyContinue
`$splatResolveAll = @{
    Name        = "Copy-DbaDbAssembly"
    All         = `$true
    ErrorAction = "SilentlyContinue"
}
`$allResolved = @(Get-Command @splatResolveAll)
`$functionCount = @(`$allResolved | Where-Object { `$PSItem.CommandType -eq "Function" }).Count
`$satelliteLoaded = [bool](Get-Module -Name dbatools.migration)
"RESOLVED|`$(`$resolved.CommandType)|`$(`$resolved.ModuleName)|`$functionCount|`$satelliteLoaded"
"@
            $probeStream = New-Object System.IO.FileStream($probePath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
            try {
                $probeBytes = [System.Text.Encoding]::UTF8.GetBytes($probeBody)
                $probeStream.Write($probeBytes, 0, $probeBytes.Length)
            } finally {
                $probeStream.Dispose()
            }

            $probeArguments = @("-NoProfile", "-NonInteractive", "-File", $probePath, $moduleBase)
            $probeOutput = & $shellPath @probeArguments 2>&1
            $probeFields = @("$(@($probeOutput | Where-Object { "$PSItem" -like "RESOLVED|*" })[0])" -split "\|")
        }

        AfterAll {
            $splatRemoveProbeDirectory = @{
                Path        = $probeDirectory
                Recurse     = $true
                Force       = $true
                ErrorAction = "SilentlyContinue"
            }
            Remove-Item @splatRemoveProbeDirectory
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